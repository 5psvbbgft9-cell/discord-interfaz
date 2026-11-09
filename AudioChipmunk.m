#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "Comun.h"

float gGainDB = 0.0f;
float gPitchSemitones = 0.0f;
BOOL gMuteMicOnPlay = NO;
BOOL gIsMp3Playing = NO;
int gSpooferMode = 0;

// Buffers separados para Izquierda y Derecha (Estéreo Real)
static SInt16 *mp3Left = NULL;
static SInt16 *mp3Right = NULL;
static long mp3TotalFrames = 0;
static long mp3CurrentFrame = 0;

#define PITCH_BUFFER_SIZE 2048
static float pitchBuffer[PITCH_BUFFER_SIZE];
static int pitchWriteIdx = 0;
static float pitchReadIdxA = 0.0f;
static float pitchReadIdxB = (float)(PITCH_BUFFER_SIZE / 2);

#define DYLD_INTERPOSE(_replacement, _replacee) \
__attribute__((used)) static struct { \
    const void *replacement; \
    const void *replacee; \
} _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

static OSStatus (*orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *) = AudioUnitRender;

void CargarMP3(NSURL *url) {
    NSError *error;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (error) return;

    AVAudioFormat *fileFormat = file.processingFormat;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fileFormat frameCapacity:(AVAudioFrameCount)file.length];
    [file readIntoBuffer:buffer error:&error];

    if (mp3Left) { free(mp3Left); mp3Left = NULL; }
    if (mp3Right) { free(mp3Right); mp3Right = NULL; }
    
    // Forzar a 48kHz manualmente
    double targetRate = 48000.0; 
    double sourceRate = fileFormat.sampleRate;
    double ratio = sourceRate / targetRate;
    
    long sourceLength = buffer.frameLength;
    long targetLength = (long)(sourceLength / ratio) + 1;
    
    mp3Left = (SInt16 *)malloc(targetLength * sizeof(SInt16));
    mp3Right = (SInt16 *)malloc(targetLength * sizeof(SInt16));
    mp3TotalFrames = targetLength;
    
    float *floatL = buffer.floatChannelData[0]; 
    float *floatR = (fileFormat.channelCount > 1) ? buffer.floatChannelData[1] : floatL;
    
    // Remuestreo Estéreo de Alta Calidad
    for (long i = 0; i < targetLength; i++) {
        double srcIndex = i * ratio;
        long idx1 = (long)srcIndex;
        long idx2 = (idx1 + 1 < sourceLength) ? idx1 + 1 : idx1;
        double frac = srcIndex - idx1;
        
        float s1L = floatL[idx1];
        float s2L = floatL[idx2];
        float sampleL = s1L * (1.0 - frac) + s2L * frac;
        
        float s1R = floatR[idx1];
        float s2R = floatR[idx2];
        float sampleR = s1R * (1.0 - frac) + s2R * frac;
        
        mp3Left[i] = (SInt16)(sampleL * 32767.0f);
        mp3Right[i] = (SInt16)(sampleR * 32767.0f);
    }
    
    mp3CurrentFrame = 0;
    gIsMp3Playing = NO;
    memset(pitchBuffer, 0, sizeof(pitchBuffer));
    pitchWriteIdx = 0;
    pitchReadIdxA = 0;
    pitchReadIdxB = PITCH_BUFFER_SIZE / 2;
}

void PlayMP3(void) { mp3CurrentFrame = 0; gIsMp3Playing = YES; }
void StopMP3(void) { gIsMp3Playing = NO; }

static float ApplyPitch(float sample) {
    pitchBuffer[pitchWriteIdx] = sample;
    float pitchFactor = powf(2.0f, gPitchSemitones / 12.0f);
    
    int idxA = (int)pitchReadIdxA;
    int idxB = (int)pitchReadIdxB;
    float fracA = pitchReadIdxA - idxA;
    float fracB = pitchReadIdxB - idxB;
    
    float valA = pitchBuffer[idxA] * (1.0f - fracA) + pitchBuffer[(idxA + 1) % PITCH_BUFFER_SIZE] * fracA;
    float valB = pitchBuffer[idxB] * (1.0f - fracB) + pitchBuffer[(idxB + 1) % PITCH_BUFFER_SIZE] * fracB;
    
    float posA = (float)idxA / (PITCH_BUFFER_SIZE / 2.0f); 
    float fade = (posA < 1.0f) ? posA : 2.0f - posA;
    if (fade < 0) fade = 0;
    if (fade > 1) fade = 1;
    
    float outSample = valA * fade + valB * (1.0f - fade);
    
    pitchWriteIdx = (pitchWriteIdx + 1) % PITCH_BUFFER_SIZE;
    pitchReadIdxA += pitchFactor;
    pitchReadIdxB += pitchFactor;
    
    if (pitchReadIdxA >= PITCH_BUFFER_SIZE) pitchReadIdxA -= PITCH_BUFFER_SIZE;
    if (pitchReadIdxB >= PITCH_BUFFER_SIZE) pitchReadIdxB -= PITCH_BUFFER_SIZE;
    
    return outSample;
}

static OSStatus MyAudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    
    if (status == noErr && inOutputBusNumber == 1 && ioData != NULL) {
        float gainLinear = powf(10.0f, (gGainDB / 20.0f));
        
        // Detectar si Discord pide el audio entrelazado (1 buffer) o separado (2 buffers)
        BOOL isInterleaved = (ioData->mNumberBuffers == 1);
        
        for (UInt32 i = 0; i < ioData->mNumberBuffers; i++) {
            SInt16 *samples = (SInt16 *)ioData->mBuffers[i].mData;
            UInt32 numSamples = ioData->mBuffers[i].mDataByteSize / sizeof(SInt16);
            if (!samples) continue;

            for (UInt32 j = 0; j < numSamples; j++) {
                // Lógica para saber qué canal estamos procesando
                int frameIndex = isInterleaved ? (j / 2) : j;
                int channel = isInterleaved ? (j % 2) : i;
                
                float micSample = (float)samples[j] / 32768.0f;
                if (gMuteMicOnPlay && gIsMp3Playing) micSample = 0.0f;

                float mp3Sample = 0.0f;
                if (gIsMp3Playing && mp3Left && mp3Right && mp3TotalFrames > 0) {
                    long readIdx = mp3CurrentFrame + frameIndex;
                    if (readIdx >= mp3TotalFrames) readIdx = readIdx % mp3TotalFrames;
                    
                    SInt16 *mp3ChanData = (channel == 0) ? mp3Left : mp3Right;
                    mp3Sample = (float)mp3ChanData[readIdx] / 32768.0f;
                }

                // MEZCLA CON HEADROOM (Evita saturación)
                // Bajamos un poco el volumen de ambos para que no saturen juntos
                float mixedSample = (micSample * 0.8f) + (mp3Sample * 0.8f);
                
                // BYPASS DE PITCH: Solo se procesa si el slider NO está en 0
                if (gPitchSemitones != 0.0f) {
                    mixedSample = ApplyPitch(mixedSample);
                }
                
                mixedSample *= gainLinear;
                
                // Soft Clipping (Limitador suave)
                if (mixedSample > 1.0f) mixedSample = tanhf(mixedSample);
                if (mixedSample < -1.0f) mixedSample = tanhf(mixedSample);

                samples[j] = (SInt16)(mixedSample * 32767.0f);
            }
        }
        
        // Avanzar el frame del MP3 DESPUÉS de procesar los buffers
        UInt32 framesProcessed = isInterleaved ? (ioData->mBuffers[0].mDataByteSize / sizeof(SInt16) / 2) : (ioData->mBuffers[0].mDataByteSize / sizeof(SInt16));
        if (gIsMp3Playing) {
            mp3CurrentFrame += framesProcessed;
            if (mp3CurrentFrame >= mp3TotalFrames) mp3CurrentFrame = 0;
        }
    }
    return status;
}
DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

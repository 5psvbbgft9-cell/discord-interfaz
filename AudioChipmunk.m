#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>
#import "Comun.h"

float gGainDB = 0.0f;
float gPitchSemitones = 0.0f;
BOOL gMuteMicOnPlay = NO;
BOOL gIsMp3Playing = NO;
int gSpooferMode = 0;

static float *mp3Left = NULL;
static float *mp3Right = NULL;
static long mp3TotalFrames = 0;
static double mp3Playhead = 0.0;

#define PITCH_BUFFER_SIZE 8192
static float pitchBuffer[PITCH_BUFFER_SIZE];
static int pitchWriteIdx = 0;
static float pitchReadIdxA = 0.0f;
static float pitchReadIdxB = (float)(PITCH_BUFFER_SIZE / 2);
static float windowTable[PITCH_BUFFER_SIZE];
static BOOL isPitchInitialized = NO;

static void InitPitch() {
    if (isPitchInitialized) return;
    for (int i = 0; i < PITCH_BUFFER_SIZE; i++) {
        windowTable[i] = 0.5f - 0.5f * cosf(2.0f * M_PI * i / PITCH_BUFFER_SIZE);
    }
    isPitchInitialized = YES;
}

#define DYLD_INTERPOSE(_replacement, _replacee) \
__attribute__((used)) static struct { \
    const void *replacement; \
    const void *replacee; \
} _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

static OSStatus (*orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *) = AudioUnitRender;

void CargarMP3(NSURL *url) {
    gIsMp3Playing = NO; // Detener reproducción antes de liberar memoria
    usleep(50000); // Esperar 50ms para que el hilo de audio no esté leyendo

    NSError *error;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (error) return;

    AVAudioFormat *fileFormat = file.processingFormat;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fileFormat frameCapacity:(AVAudioFrameCount)file.length];
    [file readIntoBuffer:buffer error:&error];

    if (mp3Left) { free(mp3Left); mp3Left = NULL; }
    if (mp3Right) { free(mp3Right); mp3Right = NULL; }
    
    double targetRate = 48000.0; 
    double sourceRate = fileFormat.sampleRate;
    double ratio = sourceRate / targetRate;
    
    long sourceLength = buffer.frameLength;
    long targetLength = (long)(sourceLength / ratio) + 1;
    
    mp3Left = (float *)malloc(targetLength * sizeof(float));
    mp3Right = (float *)malloc(targetLength * sizeof(float));
    mp3TotalFrames = targetLength;
    
    float *floatL = buffer.floatChannelData[0]; 
    float *floatR = (fileFormat.channelCount > 1) ? buffer.floatChannelData[1] : floatL;
    
    for (long i = 0; i < targetLength; i++) {
        double srcIndex = i * ratio;
        long idx1 = (long)srcIndex;
        long idx2 = (idx1 + 1 < sourceLength) ? idx1 + 1 : idx1;
        double frac = srcIndex - idx1;
        
        mp3Left[i] = floatL[idx1] * (1.0 - frac) + floatL[idx2] * frac;
        mp3Right[i] = floatR[idx1] * (1.0 - frac) + floatR[idx2] * frac;
    }
    
    mp3Playhead = 0.0;
    gIsMp3Playing = NO;
    
    memset(pitchBuffer, 0, sizeof(pitchBuffer));
    pitchWriteIdx = 0;
    pitchReadIdxA = 0;
    pitchReadIdxB = PITCH_BUFFER_SIZE / 2;
    InitPitch();
}

void PlayMP3(void) { mp3Playhead = 0.0; gIsMp3Playing = YES; }
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
    
    float fade = windowTable[idxA];
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
    
    // PROTECCIÓN TOTAL CONTRA CRASHES
    if (status != noErr || !ioData || ioData->mNumberBuffers == 0 || inOutputBusNumber != 1) return status;
    
    UInt32 numBuffers = ioData->mNumberBuffers;
    UInt32 numChannels = ioData->mBuffers[0].mNumberChannels;
    UInt32 numSamples = ioData->mBuffers[0].mDataByteSize / sizeof(SInt16);
    
    // Si el tamaño no coincide con lo esperado, no hacemos nada para evitar crasheos
    if (numSamples == 0) return status;

    SInt16 *buf0 = (SInt16 *)ioData->mBuffers[0].mData;
    SInt16 *buf1 = (numBuffers > 1) ? (SInt16 *)ioData->mBuffers[1].mData : NULL;

    if (!buf0) return status;

    InitPitch();
    float gainLinear = powf(10.0f, (gGainDB / 20.0f));
    
    // Iteramos de forma segura frame por frame
    for (UInt32 f = 0; f < inNumberFrames; f++) {
        
        float micL = 0.0f, micR = 0.0f;
        
        // LECTURA SEGURA DEL MICRÓFONO
        if (numBuffers == 1) {
            if (numChannels == 2) {
                if (f * 2 + 1 < numSamples) {
                    micL = (float)buf0[f * 2] / 32768.0f;
                    micR = (float)buf0[f * 2 + 1] / 32768.0f;
                }
            } else {
                if (f < numSamples) {
                    micL = micR = (float)buf0[f] / 32768.0f;
                }
            }
        } else {
            if (f < numSamples) {
                micL = (float)buf0[f] / 32768.0f;
                micR = buf1 ? (float)buf1[f] / 32768.0f : micL;
            }
        }
        
        if (gMuteMicOnPlay && gIsMp3Playing) { micL = 0.0f; micR = 0.0f; }

        float mp3L = 0.0f, mp3R = 0.0f;
        
        // LECTURA SEGURA DEL MP3
        if (gIsMp3Playing && mp3Left && mp3Right && mp3TotalFrames > 0) {
            long idx1 = (long)mp3Playhead;
            if (idx1 < 0) idx1 = 0;
            if (idx1 >= mp3TotalFrames) idx1 = 0; // Prevenir crash si se pasa del límite
            
            long idx2 = (idx1 + 1 < mp3TotalFrames) ? idx1 + 1 : 0;
            float frac = mp3Playhead - idx1;
            
            mp3L = mp3Left[idx1] * (1.0f - frac) + mp3Left[idx2] * frac;
            mp3R = mp3Right[idx1] * (1.0f - frac) + mp3Right[idx2] * frac;
            
            mp3Playhead += 1.0;
            if (mp3Playhead >= mp3TotalFrames) mp3Playhead = 0.0;
        }

        // Mezclar con Headroom (Evita el hundimiento)
        float mixedL = (micL * 0.5f) + (mp3L * 0.5f);
        float mixedR = (micR * 0.5f) + (mp3R * 0.5f);
        
        // Pitch Bypass (Si está en 0, no se procesa, calidad original)
        if (fabs(gPitchSemitones) > 0.01f) {
            mixedL = ApplyPitch(mixedL);
            mixedR = ApplyPitch(mixedR);
        }
        
        mixedL *= gainLinear;
        mixedR *= gainLinear;
        
        // LIMITADOR DURO (Evita que se unda al saturar)
        if (mixedL > 1.0f) mixedL = 1.0f;
        if (mixedL < -1.0f) mixedL = -1.0f;
        if (mixedR > 1.0f) mixedR = 1.0f;
        if (mixedR < -1.0f) mixedR = -1.0f;

        // ESCRITURA SEGURA
        if (numBuffers == 1) {
            if (numChannels == 2) {
                if (f * 2 + 1 < numSamples) {
                    buf0[f * 2] = (SInt16)(mixedL * 32767.0f);
                    buf0[f * 2 + 1] = (SInt16)(mixedR * 32767.0f);
                }
            } else {
                if (f < numSamples) {
                    buf0[f] = (SInt16)(((mixedL + mixedR) * 0.5f) * 32767.0f);
                }
            }
        } else {
            if (f < numSamples) {
                buf0[f] = (SInt16)(mixedL * 32767.0f);
                if (buf1) buf1[f] = (SInt16)(mixedR * 32767.0f);
            }
        }
    }
    
    return status;
}
DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

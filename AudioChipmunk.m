#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>
#import "Comun.h"

float gGainDB = 0.0f;
float gPitchSemitones = 0.0f;
BOOL gMuteMicOnPlay = NO;
BOOL gIsMp3Playing = NO;
BOOL gStreamMode = NO;
int gSpooferMode = 0;

static float *mp3Left = NULL;
static float *mp3Right = NULL;
static long mp3TotalFrames = 0;
static double mp3FileSampleRate = 44100.0;

// Buffer de 4096 para calidad, ventana de Hanning suave
#define PITCH_BUFFER_SIZE 4096
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
    gIsMp3Playing = NO;
    usleep(50000);

    NSError *error;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (error || !file) return;

    AVAudioFormat *fileFormat = file.processingFormat;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fileFormat frameCapacity:(AVAudioFrameCount)file.length];
    [file readIntoBuffer:buffer error:&error];
    if (error || !buffer) return;

    if (mp3Left) { free(mp3Left); mp3Left = NULL; }
    if (mp3Right) { free(mp3Right); mp3Right = NULL; }
    
    mp3FileSampleRate = fileFormat.sampleRate; 
    
    long sourceLength = buffer.frameLength;
    mp3Left = (float *)malloc(sourceLength * sizeof(float));
    mp3Right = (float *)malloc(sourceLength * sizeof(float));
    mp3TotalFrames = sourceLength;
    
    float *floatL = buffer.floatChannelData[0]; 
    float *floatR = (fileFormat.channelCount > 1) ? buffer.floatChannelData[1] : floatL;
    
    for (long i = 0; i < sourceLength; i++) {
        mp3Left[i] = floatL[i];
        mp3Right[i] = floatR[i];
    }
    
    gIsMp3Playing = NO;
    
    memset(pitchBuffer, 0, sizeof(pitchBuffer));
    pitchWriteIdx = 0;
    pitchReadIdxA = 0;
    pitchReadIdxB = PITCH_BUFFER_SIZE / 2;
    InitPitch();
}

void PlayMP3(void) { gIsMp3Playing = YES; }
void StopMP3(void) { gIsMp3Playing = NO; }

static float ApplyPitch(float sample) {
    if (isnan(sample) || isinf(sample)) sample = 0.0f;
    
    pitchBuffer[pitchWriteIdx] = sample;
    float pitchFactor = powf(2.0f, gPitchSemitones / 12.0f);
    
    if (pitchReadIdxA < 0 || pitchReadIdxA >= PITCH_BUFFER_SIZE) pitchReadIdxA = 0;
    if (pitchReadIdxB < 0 || pitchReadIdxB >= PITCH_BUFFER_SIZE) pitchReadIdxB = PITCH_BUFFER_SIZE / 2;
    
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
    
    // Control de seguridad para evitar el ruido robótico
    float distA = (float)pitchWriteIdx - pitchReadIdxA;
    if (distA < 0) distA += PITCH_BUFFER_SIZE;
    if (distA < 256) { 
        pitchReadIdxA -= 512; 
        if (pitchReadIdxA < 0) pitchReadIdxA += PITCH_BUFFER_SIZE; 
    }
    
    float distB = (float)pitchWriteIdx - pitchReadIdxB;
    if (distB < 0) distB += PITCH_BUFFER_SIZE;
    if (distB < 256) { 
        pitchReadIdxB -= 512; 
        if (pitchReadIdxB < 0) pitchReadIdxB += PITCH_BUFFER_SIZE; 
    }
    
    return outSample;
}

static OSStatus MyAudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    
    if (status != noErr || !ioData || ioData->mNumberBuffers == 0 || inOutputBusNumber != 1) return status;
    
    // --- NUEVA FORMA DE REPRODUCIR: SINCRONIZACIÓN POR RELOJ ---
    Float64 hwSR = [AVAudioSession sharedInstance].sampleRate;
    if (hwSR <= 0) hwSR = 48000.0;
    
    // Calculamos la proporción entre el MP3 y el hardware de Discord
    double ratio = mp3FileSampleRate / hwSR;
    
    // El reloj exacto del frame actual
    double startTime = 0;
    if (inTimeStamp && (inTimeStamp->mFlags & kAudioTimeStampSampleTimeValid)) {
        startTime = inTimeStamp->mSampleTime;
    }
    
    float gainLinear = powf(10.0f, (gGainDB / 20.0f));
    BOOL isInterleaved = (ioData->mNumberBuffers == 1);
    
    UInt32 samplesPerBuffer = ioData->mBuffers[0].mDataByteSize / sizeof(SInt16);
    SInt16 *buf0 = (SInt16 *)ioData->mBuffers[0].mData;
    SInt16 *buf1 = (ioData->mNumberBuffers > 1) ? (SInt16 *)ioData->mBuffers[1].mData : NULL;
    
    if (!buf0) return status;
    
    UInt32 framesToProcess = isInterleaved ? (samplesPerBuffer / 2) : samplesPerBuffer;
    if (framesToProcess > inNumberFrames) framesToProcess = inNumberFrames;

    for (UInt32 frame = 0; frame < framesToProcess; frame++) {
        float micL = 0.0f, micR = 0.0f;
        
        if (isInterleaved) {
            if (frame * 2 + 1 < samplesPerBuffer) {
                micL = (float)buf0[frame * 2] / 32768.0f;
                micR = (float)buf0[frame * 2 + 1] / 32768.0f;
            }
        } else {
            if (buf1 && frame < (ioData->mBuffers[1].mDataByteSize / sizeof(SInt16))) {
                micL = (float)buf0[frame] / 32768.0f;
                micR = (float)buf1[frame] / 32768.0f;
            } else {
                micL = (float)buf0[frame] / 32768.0f;
                micR = micL;
            }
        }
        
        if (gMuteMicOnPlay && gIsMp3Playing) { micL = 0.0f; micR = 0.0f; }

        float mp3L = 0.0f, mp3R = 0.0f;
        if (gIsMp3Playing && mp3Left && mp3Right && mp3TotalFrames > 0) {
            // EL SECRETO: Calculamos la posición exacta basándonos en el reloj de Discord
            double currentSampleTime = startTime + frame;
            double mp3Pos = currentSampleTime * ratio;
            
            // Bucle infinito para que la canción se repita
            double mp3PosLooped = fmod(mp3Pos, (double)mp3TotalFrames);
            if (mp3PosLooped < 0) mp3PosLooped += mp3TotalFrames;
            
            long idx1 = (long)mp3PosLooped;
            long idx2 = (idx1 + 1 < mp3TotalFrames) ? idx1 + 1 : 0;
            float frac = mp3PosLooped - idx1;
            
            mp3L = mp3Left[idx1] * (1.0f - frac) + mp3Left[idx2] * frac;
            mp3R = mp3Right[idx1] * (1.0f - frac) + mp3Right[idx2] * frac;
        }

        // Volumen completo
        float mixL = micL + mp3L;
        float mixR = micR + mp3R;
        
        if (fabsf(gPitchSemitones) > 0.01f) {
            mixL = ApplyPitch(mixL);
            mixR = ApplyPitch(mixR);
        }
        
        mixL *= gainLinear;
        mixR *= gainLinear;
        
        if (mixL > 1.0f || mixL < -1.0f) mixL = tanhf(mixL);
        if (mixR > 1.0f || mixR < -1.0f) mixR = tanhf(mixR);
        
        if (mixL > 1.0f) mixL = 1.0f; if (mixL < -1.0f) mixL = -1.0f;
        if (mixR > 1.0f) mixR = 1.0f; if (mixR < -1.0f) mixR = -1.0f;

        if (isInterleaved) {
            if (frame * 2 + 1 < samplesPerBuffer) {
                buf0[frame * 2] = (SInt16)(mixL * 32767.0f);
                buf0[frame * 2 + 1] = (SInt16)(mixR * 32767.0f);
            }
        } else {
            buf0[frame] = (SInt16)(mixL * 32767.0f);
            if (buf1) buf1[frame] = (SInt16)(mixR * 32767.0f);
        }
    }
    return status;
}
DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

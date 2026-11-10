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
static double mp3Playhead = 0.0;
static double mp3FileSampleRate = 48000.0;

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
    gIsMp3Playing = NO;
    usleep(50000); // Esperar a que el hilo libere el audio

    NSError *error;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (error || !file) return;

    AVAudioFormat *fileFormat = file.processingFormat;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fileFormat frameCapacity:(AVAudioFrameCount)file.length];
    [file readIntoBuffer:buffer error:&error];
    if (error || !buffer) return;

    if (mp3Left) { free(mp3Left); mp3Left = NULL; }
    if (mp3Right) { free(mp3Right); mp3Right = NULL; }
    
    // Forzamos la carga a 48kHz (Velocidad nativa de Discord)
    double targetRate = 48000.0; 
    mp3FileSampleRate = fileFormat.sampleRate;
    double ratio = mp3FileSampleRate / targetRate;
    
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
    if (isnan(sample) || isinf(sample)) sample = 0.0f;
    
    pitchBuffer[pitchWriteIdx] = sample;
    float pitchFactor = powf(2.0f, gPitchSemitones / 12.0f);
    
    if (pitchReadIdxA < 0 || pitchReadIdxA >= PITCH_BUFFER_SIZE) pitchReadIdxA = 0;
    if (pitchReadIdxB < 0 || pitchReadIdxB >= PITCH_BUFFER_SIZE) pitchReadIdxB = PITCH_BUFFER_SIZE / 2;
    
    int idxA = (int)pitchReadIdxA;
    int idxB = (int)pitchReadIdxB;
    
    float valA = pitchBuffer[idxA] * (1.0f - (pitchReadIdxA - idxA)) + pitchBuffer[(idxA + 1) % PITCH_BUFFER_SIZE] * (pitchReadIdxA - idxA);
    float valB = pitchBuffer[idxB] * (1.0f - (pitchReadIdxB - idxB)) + pitchBuffer[(idxB + 1) % PITCH_BUFFER_SIZE] * (pitchReadIdxB - idxB);
    
    float fade = windowTable[idxA];
    float outSample = valA * fade + valB * (1.0f - fade);
    
    pitchWriteIdx = (pitchWriteIdx + 1) % PITCH_BUFFER_SIZE;
    pitchReadIdxA += pitchFactor;
    pitchReadIdxB += pitchFactor;
    
    if (pitchReadIdxA >= PITCH_BUFFER_SIZE) pitchReadIdxA -= PITCH_BUFFER_SIZE;
    if (pitchReadIdxB >= PITCH_BUFFER_SIZE) pitchReadIdxB -= PITCH_BUFFER_SIZE;
    
    // Seguro anti-eco
    float distA = pitchWriteIdx - pitchReadIdxA;
    if (distA < 0) distA += PITCH_BUFFER_SIZE;
    if (distA < 512) { pitchReadIdxA -= 512; if (pitchReadIdxA < 0) pitchReadIdxA += PITCH_BUFFER_SIZE; }
    
    float distB = pitchWriteIdx - pitchReadIdxB;
    if (distB < 0) distB += PITCH_BUFFER_SIZE;
    if (distB < 512) { pitchReadIdxB -= 512; if (pitchReadIdxB < 0) pitchReadIdxB += PITCH_BUFFER_SIZE; }
    
    return outSample;
}

static OSStatus MyAudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    
    if (status != noErr || !ioData || ioData->mNumberBuffers == 0 || inOutputBusNumber != 1) return status;
    
    Float64 hwSR = 48000.0;
    UInt32 size = sizeof(hwSR);
    AudioUnitGetProperty(inUnit, kAudioUnitProperty_SampleRate, kAudioUnitScope_Output, 0, &hwSR, &size);
    
    // STEP DINÁMICO: Evita la lentitud si Discord usa 24kHz o 16kHz
    double step = (hwSR > 0) ? (mp3FileSampleRate / hwSR) : 1.0;
    
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
            long idx1 = (long)mp3Playhead;
            if (idx1 < 0) idx1 = 0;
            if (idx1 >= mp3TotalFrames) idx1 = 0;
            
            long idx2 = (idx1 + 1 < mp3TotalFrames) ? idx1 + 1 : 0;
            float frac = mp3Playhead - idx1;
            
            mp3L = mp3Left[idx1] * (1.0f - frac) + mp3Left[idx2] * frac;
            mp3R = mp3Right[idx1] * (1.0f - frac) + mp3Right[idx2] * frac;
            
            mp3Playhead += step; // Avanza con velocidad real
            if (mp3Playhead >= mp3TotalFrames) mp3Playhead = 0.0;
        }

        float mixL = (micL * 0.5f) + (mp3L * 0.5f);
        float mixR = (micR * 0.5f) + (mp3R * 0.5f);
        
        if (fabs(gPitchSemitones) > 0.01f) {
            mixL = ApplyPitch(mixL);
            mixR = ApplyPitch(mixR);
        }
        
        mixL *= gainLinear;
        mixR *= gainLinear;
        
        // Limitador duro para evitar el "hundimiento"
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

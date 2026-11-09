#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "Comun.h"

float gGainDB = 0.0f;
float gPitchSemitones = 0.0f;
BOOL gMuteMicOnPlay = NO;
BOOL gIsMp3Playing = NO;
int gSpooferMode = 0;

static SInt16 *mp3Samples = NULL;
static long mp3TotalSamples = 0;
static long mp3CurrentIndex = 0;

#define PITCH_BUFFER_SIZE 8192
static float pitchBuffer[PITCH_BUFFER_SIZE];
static int pitchWriteIdx = 0;
static float pitchReadIdxA = 0.0f;
static float pitchReadIdxB = (float)(PITCH_BUFFER_SIZE / 2);
static float windowTable[PITCH_BUFFER_SIZE];
static BOOL isPitchInitialized = NO;
static float smoothSample = 0.0f;

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
    NSError *error;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (error) return;

    AVAudioFormat *fileFormat = file.processingFormat;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fileFormat frameCapacity:(AVAudioFrameCount)file.length];
    [file readIntoBuffer:buffer error:&error];

    if (mp3Samples) { free(mp3Samples); mp3Samples = NULL; }
    
    // CONVERSIÓN MANUAL A 48kHz (La solución al relentizado)
    double targetRate = 48000.0; 
    double sourceRate = fileFormat.sampleRate;
    double ratio = sourceRate / targetRate;
    
    long sourceLength = buffer.frameLength;
    long targetLength = (long)(sourceLength / ratio) + 1;
    
    mp3Samples = (SInt16 *)malloc(targetLength * sizeof(SInt16));
    mp3TotalSamples = targetLength;
    
    // Tomamos el canal izquierdo (o mono) para inyectarlo al micrófono
    float *floatData = buffer.floatChannelData[0]; 
    
    // Remuestreo con interpolación lineal
    for (long i = 0; i < targetLength; i++) {
        double srcIndex = i * ratio;
        long idx1 = (long)srcIndex;
        long idx2 = (idx1 + 1 < sourceLength) ? idx1 + 1 : idx1;
        double frac = srcIndex - idx1;
        
        float s1 = floatData[idx1];
        float s2 = floatData[idx2];
        float sample = s1 * (1.0 - frac) + s2 * frac;
        
        mp3Samples[i] = (SInt16)(sample * 32767.0f);
    }
    
    mp3CurrentIndex = 0;
    gIsMp3Playing = NO;
    
    // Limpiamos el buffer del pitch para que no haya ecos raros al cargar nueva canción
    memset(pitchBuffer, 0, sizeof(pitchBuffer));
    pitchWriteIdx = 0;
    pitchReadIdxA = 0;
    pitchReadIdxB = PITCH_BUFFER_SIZE / 2;
    smoothSample = 0;
    InitPitch();
}

void PlayMP3(void) { mp3CurrentIndex = 0; gIsMp3Playing = YES; }
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
    
    smoothSample = smoothSample * 0.5f + outSample * 0.5f;
    return smoothSample;
}

static OSStatus MyAudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    
    if (status == noErr && inOutputBusNumber == 1 && ioData != NULL) {
        InitPitch();
        float gainLinear = powf(10.0f, (gGainDB / 20.0f));
        
        for (UInt32 i = 0; i < ioData->mNumberBuffers; i++) {
            SInt16 *samples = (SInt16 *)ioData->mBuffers[i].mData;
            UInt32 numSamples = ioData->mBuffers[i].mDataByteSize / sizeof(SInt16);
            if (!samples) continue;

            for (UInt32 j = 0; j < numSamples; j++) {
                float micSample = (float)samples[j] / 32768.0f;
                
                // Si el mute automático está activo y hay música, silenciamos el mic
                if (gMuteMicOnPlay && gIsMp3Playing) micSample = 0.0f;

                float mp3Sample = 0.0f;
                if (gIsMp3Playing && mp3Samples && mp3TotalSamples > 0) {
                    mp3Sample = (float)mp3Samples[mp3CurrentIndex] / 32768.0f;
                    mp3CurrentIndex++;
                    if (mp3CurrentIndex >= mp3TotalSamples) mp3CurrentIndex = 0;
                }

                float mixedSample = micSample + mp3Sample;
                
                // SOLO aplicar pitch si el usuario lo movió de 0
                if (gPitchSemitones != 0.0f) {
                    mixedSample = ApplyPitch(mixedSample);
                }
                
                mixedSample *= gainLinear;
                
                // Evitar distorsión (Clipping)
                if (mixedSample > 1.0f || mixedSample < -1.0f) {
                    mixedSample = tanhf(mixedSample); 
                }

                samples[j] = (SInt16)(mixedSample * 32767.0f);
            }
        }
    }
    return status;
}
DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

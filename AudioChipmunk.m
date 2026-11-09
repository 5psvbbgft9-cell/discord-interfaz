#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "Comun.h"

float gGainDB = 0.0f;
float gPitchAmount = 1.0f;
BOOL gMuteMicOnPlay = NO;
BOOL gSelfMonitor = NO;
BOOL gIsMp3Playing = NO;
int gSpooferMode = 0;

static SInt16 *mp3Samples = NULL;
static long mp3TotalSamples = 0;
static long mp3CurrentIndex = 0;

#define PITCH_BUFFER_SIZE 2048
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

static OSStatus (*orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *,
                                         const AudioTimeStamp *, UInt32, UInt32,
                                         AudioBufferList *) = AudioUnitRender;

void CargarMP3(NSURL *url) {
    NSError *error;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (error) return;

    AVAudioFormat *format = file.processingFormat;
    AVAudioFrameCount length = (AVAudioFrameCount)file.length;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:length];
    [file readIntoBuffer:buffer error:&error];

    if (mp3Samples) { free(mp3Samples); mp3Samples = NULL; }
    
    mp3TotalSamples = length * format.channelCount;
    mp3Samples = (SInt16 *)malloc(mp3TotalSamples * sizeof(SInt16));
    
    for (int ch = 0; ch < format.channelCount; ch++) {
        float *channelData = buffer.floatChannelData[ch];
        for (long i = 0; i < length; i++) {
            mp3Samples[i * format.channelCount + ch] = (SInt16)(channelData[i] * 32767.0f);
        }
    }
    mp3CurrentIndex = 0;
    gIsMp3Playing = NO;
    InitPitch();
}

void PlayMP3(void) { mp3CurrentIndex = 0; gIsMp3Playing = YES; }
void StopMP3(void) { gIsMp3Playing = NO; }

static float ApplyPitch(float sample) {
    pitchBuffer[pitchWriteIdx] = sample;
    int idxA = (int)pitchReadIdxA;
    int idxB = (int)pitchReadIdxB;
    float fracA = pitchReadIdxA - idxA;
    float fracB = pitchReadIdxB - idxB;
    
    float valA = pitchBuffer[idxA] * (1.0f - fracA) + pitchBuffer[(idxA + 1) % PITCH_BUFFER_SIZE] * fracA;
    float valB = pitchBuffer[idxB] * (1.0f - fracB) + pitchBuffer[(idxB + 1) % PITCH_BUFFER_SIZE] * fracB;
    
    float fade = windowTable[idxA];
    float outSample = valA * fade + valB * (1.0f - fade);
    
    pitchWriteIdx = (pitchWriteIdx + 1) % PITCH_BUFFER_SIZE;
    pitchReadIdxA += gPitchAmount;
    pitchReadIdxB += gPitchAmount;
    
    if (pitchReadIdxA >= PITCH_BUFFER_SIZE) pitchReadIdxA -= PITCH_BUFFER_SIZE;
    if (pitchReadIdxB >= PITCH_BUFFER_SIZE) pitchReadIdxB -= PITCH_BUFFER_SIZE;
    
    return outSample;
}

static OSStatus MyAudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags,
                                   const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber,
                                   UInt32 inNumberFrames, AudioBufferList *ioData) {
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
                if (gMuteMicOnPlay && gIsMp3Playing) micSample = 0.0f;

                float mp3Sample = 0.0f;
                if (gIsMp3Playing && mp3Samples && mp3TotalSamples > 0) {
                    mp3Sample = (float)mp3Samples[mp3CurrentIndex] / 32768.0f;
                    mp3CurrentIndex++;
                    if (mp3CurrentIndex >= mp3TotalSamples) mp3CurrentIndex = 0;
                }

                float mixedSample = micSample + mp3Sample;
                float processedSample = ApplyPitch(mixedSample);
                processedSample *= gainLinear;
                
                if (processedSample > 1.0f || processedSample < -1.0f) {
                    processedSample = tanhf(processedSample); 
                }

                samples[j] = (SInt16)(processedSample * 32767.0f);
            }
        }
    }
    return status;
}
DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

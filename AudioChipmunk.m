#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "Comun.h"

float gGainDB = 0.0f;
float gPitchSemitones = 0.0f;
BOOL gMuteMicOnPlay = NO;
BOOL gIsMp3Playing = NO;
int gSpooferMode = 0;

// Buffers del MP3 en Flotante (Calidad Original)
static float *mp3Left = NULL;
static float *mp3Right = NULL;
static long mp3TotalFrames = 0;
static double mp3Playhead = 0.0; 
static double mp3FileSampleRate = 48000.0;

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
    
    mp3TotalFrames = buffer.frameLength;
    mp3FileSampleRate = fileFormat.sampleRate;
    
    mp3Left = (float *)malloc(mp3TotalFrames * sizeof(float));
    mp3Right = (float *)malloc(mp3TotalFrames * sizeof(float));
    
    float *floatL = buffer.floatChannelData[0]; 
    float *floatR = (fileFormat.channelCount > 1) ? buffer.floatChannelData[1] : floatL;
    
    for (long i = 0; i < mp3TotalFrames; i++) {
        mp3Left[i] = floatL[i];
        mp3Right[i] = floatR[i];
    }
    
    mp3Playhead = 0.0;
    gIsMp3Playing = NO;
    memset(pitchBuffer, 0, sizeof(pitchBuffer));
    pitchWriteIdx = 0;
    pitchReadIdxA = 0;
    pitchReadIdxB = PITCH_BUFFER_SIZE / 2;
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
        // 1. LEER LA FRECUENCIA REAL DE DISCORD (Evita el ralentizado)
        Float64 hardwareSampleRate = 48000.0;
        UInt32 size = sizeof(hardwareSampleRate);
        AudioUnitGetProperty(inUnit, kAudioUnitProperty_SampleRate, kAudioUnitScope_Output, 0, &hardwareSampleRate, &size);
        
        // 2. CALCULAR LA VELOCIDAD (Si Discord está a 24kHz, el paso será 2.0)
        double step = mp3FileSampleRate / hardwareSampleRate;
        
        float gainLinear = powf(10.0f, (gGainDB / 20.0f));
        BOOL isInterleaved = (ioData->mNumberBuffers == 1);
        
        for (UInt32 i = 0; i < ioData->mNumberBuffers; i++) {
            SInt16 *samples = (SInt16 *)ioData->mBuffers[i].mData;
            UInt32 numSamples = ioData->mBuffers[i].mDataByteSize / sizeof(SInt16);
            if (!samples) continue;

            for (UInt32 j = 0; j < numSamples; j++) {
                int channel = isInterleaved ? (j % 2) : i;
                
                float micSample = (float)samples[j] / 32768.0f;
                if (gMuteMicOnPlay && gIsMp3Playing) micSample = 0.0f;

                float mp3Sample = 0.0f;
                if (gIsMp3Playing && mp3Left && mp3Right && mp3TotalFrames > 0) {
                    long idx1 = (long)mp3Playhead;
                    long idx2 = (idx1 + 1 < mp3TotalFrames) ? idx1 + 1 : idx1;
                    float frac = mp3Playhead - idx1;
                    
                    float *mp3ChanData = (channel == 0) ? mp3Left : mp3Right;
                    mp3Sample = mp3ChanData[idx1] * (1.0f - frac) + mp3ChanData[idx2] * frac;
                    
                    // Avanzar el playhead usando la velocidad calculada
                    if (channel == 0 || !isInterleaved) {
                        mp3Playhead += step;
                        if (mp3Playhead >= mp3TotalFrames) mp3Playhead = 0.0;
                    }
                }

                float mixedSample = (micSample * 0.8f) + (mp3Sample * 0.8f);
                
                if (gPitchSemitones != 0.0f) {
                    mixedSample = ApplyPitch(mixedSample);
                }
                
                mixedSample *= gainLinear;
                if (mixedSample > 1.0f) mixedSample = tanhf(mixedSample);
                if (mixedSample < -1.0f) mixedSample = tanhf(mixedSample);

                samples[j] = (SInt16)(mixedSample * 32767.0f);
            }
        }
    }
    return status;
}
DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

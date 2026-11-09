//
// AudioChipmunk.m
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

// Variables globales controladas por la Interfaz
float gGainDB = 0.0f;
float gPitchAmount = 1.0f;
BOOL gMuteMic = NO;

// Variables para el reproductor MP3
static SInt16 *mp3Samples = NULL;
static long mp3TotalSamples = 0;
static long mp3CurrentIndex = 0;
BOOL gIsMp3Playing = NO;

// Variables para el Pitch Shifter
#define RING_SIZE 8192
static float ringBuffer[RING_SIZE];
static int writeIndex = 0;
static float readIndex = 0.0f;

#define DYLD_INTERPOSE(_replacement, _replacee) \
__attribute__((used)) static struct { \
    const void *replacement; \
    const void *replacee; \
} _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

static OSStatus (*orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *,
                                         const AudioTimeStamp *, UInt32, UInt32,
                                         AudioBufferList *) = AudioUnitRender;

// Función para cargar el MP3 a memoria (Se llama desde la UI)
void CargarMP3(NSURL *url) {
    NSError *error;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (error) { NSLog(@"Error MP3: %@", error); return; }

    AVAudioFormat *format = file.processingFormat;
    AVAudioFrameCount length = (AVAudioFrameCount)file.length;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:length];
    [file readIntoBuffer:buffer error:&error];

    if (mp3Samples) { free(mp3Samples); mp3Samples = NULL; }
    
    // Convertir a SInt16
    mp3TotalSamples = length * format.channelCount;
    mp3Samples = (SInt16 *)malloc(mp3TotalSamples * sizeof(SInt16));
    
    float *floatData = buffer.floatChannelData[0];
    for (long i = 0; i < mp3TotalSamples; i++) {
        mp3Samples[i] = (SInt16)(floatData[i] * 32767.0f);
    }
    
    mp3CurrentIndex = 0;
    gIsMp3Playing = NO;
}

void PlayMP3(void) { mp3CurrentIndex = 0; gIsMp3Playing = YES; }
void StopMP3(void) { gIsMp3Playing = NO; }

// EL HOOK REAL
static OSStatus MyAudioUnitRender(AudioUnit inUnit,
                                   AudioUnitRenderActionFlags *ioActionFlags,
                                   const AudioTimeStamp *inTimeStamp,
                                   UInt32 inOutputBusNumber,
                                   UInt32 inNumberFrames,
                                   AudioBufferList *ioData) {
    
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    
    if (status == noErr && inOutputBusNumber == 1 && ioData != NULL) {
        float gainLinear = powf(10.0f, (gGainDB / 20.0f)); // Convertir dB a lineal
        if (gainLinear > 100.0f) gainLinear = 100.0f; // Límite de seguridad
        
        for (UInt32 i = 0; i < ioData->mNumberBuffers; i++) {
            SInt16 *samples = (SInt16 *)ioData->mBuffers[i].mData;
            UInt32 numSamples = ioData->mBuffers[i].mDataByteSize / sizeof(SInt16);
            if (!samples) continue;

            for (UInt32 j = 0; j < numSamples; j++) {
                float micSample = (float)samples[j] / 32768.0f;
                
                // 1. Silenciar micrófono si se pide
                if (gMuteMic && gIsMp3Playing) micSample = 0.0f;

                // 2. Mezclar MP3
                float mp3Sample = 0.0f;
                if (gIsMp3Playing && mp3Samples && mp3TotalSamples > 0) {
                    mp3Sample = (float)mp3Samples[mp3CurrentIndex] / 32768.0f;
                    mp3CurrentIndex++;
                    if (mp3CurrentIndex >= mp3TotalSamples) mp3CurrentIndex = 0; // Loop
                }

                float mixedSample = micSample + mp3Sample;

                // 3. Aplicar Pitch (Algoritmo de buffer circular simple)
                ringBuffer[writeIndex] = mixedSample;
                writeIndex = (writeIndex + 1) % RING_SIZE;
                
                int idx0 = (int)readIndex;
                int idx1 = (idx0 + 1) % RING_SIZE;
                float frac = readIndex - idx0;
                float pitchSample = ringBuffer[idx0 % RING_SIZE] * (1.0f - frac) + ringBuffer[idx1] * frac;
                
                readIndex += gPitchAmount;
                if (readIndex >= RING_SIZE) readIndex -= RING_SIZE;
                
                float dist = writeIndex - readIndex;
                if (dist < 0) dist += RING_SIZE;
                if (dist < 256) { readIndex -= 256; if (readIndex < 0) readIndex += RING_SIZE; }

                // 4. Aplicar Ganancia
                pitchSample *= gainLinear;

                // 5. Clipping para evitar distorsión
                if (pitchSample > 1.0f) pitchSample = 1.0f;
                if (pitchSample < -1.0f) pitchSample = -1.0f;

                samples[j] = (SInt16)(pitchSample * 32767.0f);
            }
        }
    }
    return status;
}

DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "Comun.h"

float gGainDB = 0.0f;
float gPitchSemitones = 0.0f;
BOOL gMuteMicOnPlay = NO;
BOOL gIsMp3Playing = NO;
int gSpooferMode = 0;

// Buffers del MP3 (Float para calidad original)
static float *mp3Left = NULL;
static float *mp3Right = NULL;
static long mp3TotalFrames = 0;
static double mp3Playhead = 0.0; 
static double mp3FileSampleRate = 48000.0;

// Pitch Shifter de Alta Calidad
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
    
    // Limpiar el Pitch para que no quede eco de la canción anterior
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
    
    float valA = pitchBuffer[idxA] * (1.0f - (pitchReadIdxA - idxA)) + pitchBuffer[(idxA + 1) % PITCH_BUFFER_SIZE] * (pitchReadIdxA - idxA);
    float valB = pitchBuffer[idxB] * (1.0f - (pitchReadIdxB - idxB)) + pitchBuffer[(idxB + 1) % PITCH_BUFFER_SIZE] * (pitchReadIdxB - idxB);
    
    float fade = windowTable[idxA];
    float outSample = valA * fade + valB * (1.0f - fade);
    
    pitchWriteIdx = (pitchWriteIdx + 1) % PITCH_BUFFER_SIZE;
    pitchReadIdxA += pitchFactor;
    pitchReadIdxB += pitchFactor;
    
    if (pitchReadIdxA >= PITCH_BUFFER_SIZE) pitchReadIdxA -= PITCH_BUFFER_SIZE;
    if (pitchReadIdxB >= PITCH_BUFFER_SIZE) pitchReadIdxB -= PITCH_BUFFER_SIZE;
    
    // EL ARREGLO DEL ECO/DOBLE: Si la lectura alcanza a la escritura, la empujamos atrás
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
    
    if (status == noErr && inOutputBusNumber == 1 && ioData != NULL) {
        // 1. Obtener la frecuencia REAL de Discord
        Float64 hwSR = 48000.0;
        UInt32 size = sizeof(hwSR);
        AudioUnitGetProperty(inUnit, kAudioUnitProperty_SampleRate, kAudioUnitScope_Output, 0, &hwSR, &size);
        
        // 2. Calcular el paso exacto para evitar el ralentizado
        double step = (hwSR > 0) ? (mp3FileSampleRate / hwSR) : 1.0;
        
        float gainLinear = powf(10.0f, (gGainDB / 20.0f));
        BOOL isInterleaved = (ioData->mNumberBuffers == 1);
        
        SInt16 *buf0 = (SInt16 *)ioData->mBuffers[0].mData;
        SInt16 *buf1 = isInterleaved ? NULL : (SInt16 *)ioData->mBuffers[1].mData;

        for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
            
            float micL = 0.0f, micR = 0.0f;
            if (isInterleaved) {
                micL = (float)buf0[frame * 2] / 32768.0f;
                micR = (float)buf0[frame * 2 + 1] / 32768.0f;
            } else {
                micL = (float)buf0[frame] / 32768.0f;
                micR = (float)buf1[frame] / 32768.0f;
            }
            
            if (gMuteMicOnPlay && gIsMp3Playing) { micL = 0.0f; micR = 0.0f; }

            float mp3L = 0.0f, mp3R = 0.0f;
            if (gIsMp3Playing && mp3Left && mp3Right && mp3TotalFrames > 0) {
                long idx1 = (long)mp3Playhead;
                long idx2 = (idx1 + 1 < mp3TotalFrames) ? idx1 + 1 : 0;
                float frac = mp3Playhead - idx1;
                
                mp3L = mp3Left[idx1] * (1.0f - frac) + mp3Left[idx2] * frac;
                mp3R = mp3Right[idx1] * (1.0f - frac) + mp3Right[idx2] * frac;
                
                // Avanzar usando el paso calculado (Soluciona el ralentizado)
                mp3Playhead += step;
                if (mp3Playhead >= mp3TotalFrames) mp3Playhead -= mp3TotalFrames;
            }

            // Mezcla con Headroom
            float mixL = (micL * 0.8f) + (mp3L * 0.8f);
            float mixR = (micR * 0.8f) + (mp3R * 0.8f);
            
            if (gPitchSemitones != 0.0f) {
                mixL = ApplyPitch(mixL);
                mixR = ApplyPitch(mixR);
            }
            
            mixL *= gainLinear;
            mixR *= gainLinear;
            
            // Limitador (Evita el corte/undimiento al saturar)
            if (mixL > 1.0f) mixL = 1.0f; if (mixL < -1.0f) mixL = -1.0f;
            if (mixR > 1.0f) mixR = 1.0f; if (mixR < -1.0f) mixR = -1.0f;

            if (isInterleaved) {
                buf0[frame * 2] = (SInt16)(mixL * 32767.0f);
                buf0[frame * 2 + 1] = (SInt16)(mixR * 32767.0f);
            } else {
                buf0[frame] = (SInt16)(mixL * 32767.0f);
                buf1[frame] = (SInt16)(mixR * 32767.0f);
            }
        }
    }
    return status;
}
DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

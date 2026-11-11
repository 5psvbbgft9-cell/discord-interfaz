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
static double mp3FileSampleRate = 44100.0;

// --- PITCH SHIFTER ESTÉREO (Dos cerebros separados) ---
#define PITCH_BUFFER_SIZE 4096

typedef struct {
    float buffer[PITCH_BUFFER_SIZE];
    int writeIdx;
    float readIdxA;
    float readIdxB;
} PitchShifter;

static PitchShifter pitchL;
static PitchShifter pitchR;
static float windowTable[PITCH_BUFFER_SIZE];
static BOOL isPitchInitialized = NO;

static void InitPitch() {
    if (isPitchInitialized) return;
    for (int i = 0; i < PITCH_BUFFER_SIZE; i++) {
        windowTable[i] = 0.5f - 0.5f * cosf(2.0f * M_PI * i / PITCH_BUFFER_SIZE);
    }
    
    // Inicializar ambos canales
    memset(&pitchL, 0, sizeof(PitchShifter));
    memset(&pitchR, 0, sizeof(PitchShifter));
    pitchL.readIdxB = PITCH_BUFFER_SIZE / 2;
    pitchR.readIdxB = PITCH_BUFFER_SIZE / 2;
    
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
    
    mp3Playhead = 0.0;
    gIsMp3Playing = NO;
    
    isPitchInitialized = NO;
    InitPitch();
}

void PlayMP3(void) { mp3Playhead = 0.0; gIsMp3Playing = YES; }
void StopMP3(void) { gIsMp3Playing = NO; }

// Procesar Pitch individual (Evita la mezcla de canales)
static float ProcessPitch(PitchShifter *ps, float sample) {
    if (isnan(sample) || isinf(sample)) sample = 0.0f;
    
    ps->buffer[ps->writeIdx] = sample;
    float pitchFactor = powf(2.0f, gPitchSemitones / 12.0f);
    
    if (ps->readIdxA < 0 || ps->readIdxA >= PITCH_BUFFER_SIZE) ps->readIdxA = 0;
    if (ps->readIdxB < 0 || ps->readIdxB >= PITCH_BUFFER_SIZE) ps->readIdxB = PITCH_BUFFER_SIZE / 2;
    
    int idxA = (int)ps->readIdxA;
    int idxB = (int)ps->readIdxB;
    
    float fracA = ps->readIdxA - idxA;
    float fracB = ps->readIdxB - idxB;
    
    float valA = ps->buffer[idxA] * (1.0f - fracA) + ps->buffer[(idxA + 1) % PITCH_BUFFER_SIZE] * fracA;
    float valB = ps->buffer[idxB] * (1.0f - fracB) + ps->buffer[(idxB + 1) % PITCH_BUFFER_SIZE] * fracB;
    
    float fade = windowTable[idxA];
    float outSample = valA * fade + valB * (1.0f - fade);
    
    ps->writeIdx = (ps->writeIdx + 1) % PITCH_BUFFER_SIZE;
    ps->readIdxA += pitchFactor;
    ps->readIdxB += pitchFactor;
    
    if (ps->readIdxA >= PITCH_BUFFER_SIZE) ps->readIdxA -= PITCH_BUFFER_SIZE;
    if (ps->readIdxB >= PITCH_BUFFER_SIZE) ps->readIdxB -= PITCH_BUFFER_SIZE;
    
    // Control de seguridad anti-ruido
    float distA = (float)ps->writeIdx - ps->readIdxA;
    if (distA < 0) distA += PITCH_BUFFER_SIZE;
    if (distA < 256) { 
        ps->readIdxA -= 512; 
        if (ps->readIdxA < 0) ps->readIdxA += PITCH_BUFFER_SIZE; 
    }
    
    float distB = (float)ps->writeIdx - ps->readIdxB;
    if (distB < 0) distB += PITCH_BUFFER_SIZE;
    if (distB < 256) { 
        ps->readIdxB -= 512; 
        if (ps->readIdxB < 0) ps->readIdxB += PITCH_BUFFER_SIZE; 
    }
    
    return outSample;
}

static OSStatus MyAudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    
    if (status != noErr || !ioData || ioData->mNumberBuffers == 0 || inOutputBusNumber != 1) return status;
    
    Float64 hwSR = [AVAudioSession sharedInstance].sampleRate;
    if (hwSR <= 0) hwSR = 48000.0;
    
    // PROPORCIÓN EXACTA (Ej: 44100 / 48000 = 0.91875)
    double step = mp3FileSampleRate / hwSR;
    
    float gainLinear = powf(10.0f, (gGainDB / 20.0f));
    BOOL isInterleaved = (ioData->mNumberBuffers == 1);
    
    SInt16 *buf0 = (SInt16 *)ioData->mBuffers[0].mData;
    SInt16 *buf1 = (ioData->mNumberBuffers > 1) ? (SInt16 *)ioData->mBuffers[1].mData : NULL;
    
    if (!buf0) return status;

    // Bucle estricto usando inNumberFrames (La única verdad)
    for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
        float micL = 0.0f, micR = 0.0f;
        
        // LECTURA SEGURA
        if (isInterleaved) {
            micL = (float)buf0[frame * 2] / 32768.0f;
            micR = (float)buf0[frame * 2 + 1] / 32768.0f;
        } else {
            micL = (float)buf0[frame] / 32768.0f;
            micR = buf1 ? (float)buf1[frame] / 32768.0f : micL;
        }
        
        if (gMuteMicOnPlay && gIsMp3Playing) { micL = 0.0f; micR = 0.0f; }

        float mp3L = 0.0f, mp3R = 0.0f;
        
        // REPRODUCCIÓN EXACTA DEL MP3
        if (gIsMp3Playing && mp3Left && mp3Right && mp3TotalFrames > 0) {
            long idx1 = (long)mp3Playhead;
            if (idx1 < 0) idx1 = 0;
            if (idx1 >= mp3TotalFrames) idx1 = 0;
            
            long idx2 = (idx1 + 1 < mp3TotalFrames) ? idx1 + 1 : 0;
            float frac = mp3Playhead - idx1;
            
            mp3L = mp3Left[idx1] * (1.0f - frac) + mp3Left[idx2] * frac;
            mp3R = mp3Right[idx1] * (1.0f - frac) + mp3Right[idx2] * frac;
            
            // Avanzar exactamente 1 frame
            mp3Playhead += step; 
            if (mp3Playhead >= mp3TotalFrames) mp3Playhead -= mp3TotalFrames;
        }

        // Mezclar
        float mixL = micL + mp3L;
        float mixR = micR + mp3R;
        
        // APLICAR PITCH (Separado por canal)
        if (fabsf(gPitchSemitones) > 0.01f) {
            mixL = ProcessPitch(&pitchL, mixL);
            mixR = ProcessPitch(&pitchR, mixR);
        }
        
        mixL *= gainLinear;
        mixR *= gainLinear;
        
        if (mixL > 1.0f || mixL < -1.0f) mixL = tanhf(mixL);
        if (mixR > 1.0f || mixR < -1.0f) mixR = tanhf(mixR);
        
        if (mixL > 1.0f) mixL = 1.0f; if (mixL < -1.0f) mixL = -1.0f;
        if (mixR > 1.0f) mixR = 1.0f; if (mixR < -1.0f) mixR = -1.0f;

        // ESCRITURA SEGURA
        if (isInterleaved) {
            buf0[frame * 2] = (SInt16)(mixL * 32767.0f);
            buf0[frame * 2 + 1] = (SInt16)(mixR * 32767.0f);
        } else {
            buf0[frame] = (SInt16)(mixL * 32767.0f);
            if (buf1) buf1[frame] = (SInt16)(mixR * 32767.0f);
        }
    }
    return status;
}
DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

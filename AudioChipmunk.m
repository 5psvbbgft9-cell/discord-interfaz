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
static double mp3FileSampleRate = 48000.0;

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
    if (error || !file) return;

    AVAudioFormat *fileFormat = file.processingFormat;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fileFormat frameCapacity:(AVAudioFrameCount)file.length];
    [file readIntoBuffer:buffer error:&error];
    if (error || !buffer) return;

    if (mp3Left) { free(mp3Left); mp3Left = NULL; }
    if (mp3Right) { free(mp3Right); mp3Right = NULL; }
    
    mp3TotalFrames = buffer.frameLength;
    if (mp3TotalFrames <= 0) return;
    
    mp3FileSampleRate = fileFormat.sampleRate; 
    
    mp3Left = (float *)malloc(mp3TotalFrames * sizeof(float));
    mp3Right = (float *)malloc(mp3TotalFrames * sizeof(float));
    
    if (!mp3Left || !mp3Right) return; // Seguridad por si no hay memoria
    
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
    InitPitch();
}

void PlayMP3(void) { mp3Playhead = 0.0; gIsMp3Playing = YES; }
void StopMP3(void) { gIsMp3Playing = NO; }

static float ApplyPitch(float sample) {
    // Protección contra valores infinitos o NaN
    if (isnan(sample) || isinf(sample)) sample = 0.0f;
    
    pitchBuffer[pitchWriteIdx] = sample;
    float pitchFactor = powf(2.0f, gPitchSemitones / 12.0f);
    
    // Asegurar que los índices estén en rango válido
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
    
    // Evitar el "doble/eco" alejando los punteros
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
    
    // PROTECCIÓN 1: Validar que ioData y los buffers existan
    if (status != noErr || !ioData || ioData->mNumberBuffers == 0 || inOutputBusNumber != 1) {
        return status;
    }
    
    Float64 hwSR = 48000.0;
    UInt32 size = sizeof(hwSR);
    AudioUnitGetProperty(inUnit, kAudioUnitProperty_SampleRate, kAudioUnitScope_Output, 0, &hwSR, &size);
    double step = (hwSR > 0) ? (mp3FileSampleRate / hwSR) : 1.0;
    
    float gainLinear = powf(10.0f, (gGainDB / 20.0f));
    
    // PROTECCIÓN 2: Identificar si es entrelazado (1 buffer) o separado (2 buffers)
    BOOL isInterleaved = (ioData->mNumberBuffers == 1);
    
    SInt16 *buf0 = (SInt16 *)ioData->mBuffers[0].mData;
    SInt16 *buf1 = (ioData->mNumberBuffers > 1) ? (SInt16 *)ioData->mBuffers[1].mData : NULL;

    if (!buf0) return status;

    // PROTECCIÓN 3: Asegurar que no iteramos más muestras de las que hay en el buffer
    UInt32 samplesPerBuffer = ioData->mBuffers[0].mDataByteSize / sizeof(SInt16);
    UInt32 framesToProcess = isInterleaved ? (samplesPerBuffer / 2) : samplesPerBuffer;
    if (framesToProcess > inNumberFrames) framesToProcess = inNumberFrames; // Límite duro

    for (UInt32 frame = 0; frame < framesToProcess; frame++) {
        
        float micL = 0.0f, micR = 0.0f;
        
        // LECTURA SEGURA DEL MICRÓFONO
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
                micR = micL; // Si es mono, copiamos
            }
        }
        
        if (gMuteMicOnPlay && gIsMp3Playing) { micL = 0.0f; micR = 0.0f; }

        float mp3L = 0.0f, mp3R = 0.0f;
        
        // LECTURA SEGURA DEL MP3
        if (gIsMp3Playing && mp3Left && mp3Right && mp3TotalFrames > 0) {
            long idx1 = (long)mp3Playhead;
            if (idx1 < 0) idx1 = 0;
            if (idx1 >= mp3TotalFrames) idx1 = mp3TotalFrames - 1;
            
            long idx2 = (idx1 + 1 < mp3TotalFrames) ? idx1 + 1 : 0;
            float frac = mp3Playhead - idx1;
            if (frac < 0) frac = 0; if (frac > 1) frac = 1;
            
            mp3L = mp3Left[idx1] * (1.0f - frac) + mp3Left[idx2] * frac;
            mp3R = mp3Right[idx1] * (1.0f - frac) + mp3Right[idx2] * frac;
            
            mp3Playhead += step;
            if (mp3Playhead >= mp3TotalFrames) mp3Playhead = 0.0;
        }

        float mixL = (micL * 0.8f) + (mp3L * 0.8f);
        float mixR = (micR * 0.8f) + (mp3R * 0.8f);
        
        if (gPitchSemitones != 0.0f) {
            mixL = ApplyPitch(mixL);
            mixR = ApplyPitch(mixR);
        }
        
        mixL *= gainLinear;
        mixR *= gainLinear;
        
        // Clipping
        if (mixL > 1.0f) mixL = 1.0f; if (mixL < -1.0f) mixL = -1.0f;
        if (mixR > 1.0f) mixR = 1.0f; if (mixR < -1.0f) mixR = -1.0f;

        // ESCRITURA SEGURA EN EL BUFFER
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

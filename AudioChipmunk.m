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

// --- TRADUCCIÓN EXACTA DEL WK_PITCH DE JAVASCRIPT ---
#define PITCH_BUFFER_SIZE 1024

typedef struct {
    float buffer[PITCH_BUFFER_SIZE];
    int write_ptr;
    float phase;
    float current_ratio;
    float target_ratio;
    float smooth;
} PitchState;

static PitchState stateL;
static PitchState stateR;

static void InitPitch() {
    memset(&stateL, 0, sizeof(PitchState));
    memset(&stateR, 0, sizeof(PitchState));
    stateL.smooth = 0.01f;
    stateR.smooth = 0.01f;
    stateL.current_ratio = 1.0f;
    stateR.current_ratio = 1.0f;
    stateL.target_ratio = 1.0f;
    stateR.target_ratio = 1.0f;
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

    // Guardamos la frecuencia original del MP3
    AVAudioFormat *fileFormat = file.processingFormat;
    mp3FileSampleRate = fileFormat.sampleRate; 
    
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fileFormat frameCapacity:(AVAudioFrameCount)file.length];
    [file readIntoBuffer:buffer error:&error];
    if (error || !buffer) return;

    if (mp3Left) { free(mp3Left); mp3Left = NULL; }
    if (mp3Right) { free(mp3Right); mp3Right = NULL; }
    
    mp3TotalFrames = buffer.frameLength;
    mp3Left = (float *)malloc(mp3TotalFrames * sizeof(float));
    mp3Right = (float *)malloc(mp3TotalFrames * sizeof(float));
    
    float *floatL = buffer.floatChannelData[0]; 
    float *floatR = (fileFormat.channelCount > 1) ? buffer.floatChannelData[1] : floatL;
    
    // Guardamos el MP3 en Float32 (Calidad original)
    for (long i = 0; i < mp3TotalFrames; i++) {
        mp3Left[i] = floatL[i];
        mp3Right[i] = floatR[i];
    }
    
    mp3Playhead = 0.0;
    gIsMp3Playing = NO;
    InitPitch();
}

void PlayMP3(void) { mp3Playhead = 0.0; gIsMp3Playing = YES; }
void StopMP3(void) { gIsMp3Playing = NO; }

static float ProcessPitch(PitchState *state, float input) {
    // Suavizado
    state->current_ratio += (state->target_ratio - state->current_ratio) * state->smooth;

    if (fabsf(state->current_ratio - 1.0f) < 0.001f) {
        state->buffer[state->write_ptr] = input;
        state->write_ptr = (state->write_ptr + 1) % PITCH_BUFFER_SIZE;
        return input;
    }

    state->buffer[state->write_ptr] = input;

    float sh = state->current_ratio - 1.0f;
    float hh = PITCH_BUFFER_SIZE / 2.0f;

    state->phase += sh;
    while (state->phase >= PITCH_BUFFER_SIZE) state->phase -= PITCH_BUFFER_SIZE;
    while (state->phase < 0) state->phase += PITCH_BUFFER_SIZE;

    float p1 = state->phase;
    float p2 = fmodf(state->phase + hh, PITCH_BUFFER_SIZE);

    int rp1 = (state->write_ptr - (int)floorf(p1) + PITCH_BUFFER_SIZE) % PITCH_BUFFER_SIZE;
    int rp2 = (state->write_ptr - (int)floorf(p2) + PITCH_BUFFER_SIZE) % PITCH_BUFFER_SIZE;

    float w1 = 0.5f - 0.5f * cosf(2.0f * M_PI * p1 / PITCH_BUFFER_SIZE);
    float w2 = 0.5f - 0.5f * cosf(2.0f * M_PI * p2 / PITCH_BUFFER_SIZE);

    float output = state->buffer[rp1] * w1 + state->buffer[rp2] * w2;

    state->write_ptr = (state->write_ptr + 1) % PITCH_BUFFER_SIZE;

    return output;
}

static OSStatus MyAudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    
    if (status != noErr || !ioData || ioData->mNumberBuffers == 0 || inOutputBusNumber != 1) return status;
    
    // --- LA SOLUCIÓN AL AUDIO LENTO ---
    // Obtenemos la frecuencia real a la que está operando Discord ahora mismo
    Float64 hwSR = [AVAudioSession sharedInstance].sampleRate;
    if (hwSR <= 0) hwSR = 48000.0;
    
    // Calculamos el paso exacto. Si el MP3 es 44100 y Discord es 48000, el paso es 0.91875
    double step = mp3FileSampleRate / hwSR;
    
    float ratio = powf(2.0f, gPitchSemitones / 12.0f);
    stateL.target_ratio = ratio;
    stateR.target_ratio = ratio;

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
        
        // 1. Leer Micrófono
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

        // 2. Leer MP3 con Interpolación Lineal (Calidad de estudio)
        float mp3L = 0.0f, mp3R = 0.0f;
        if (gIsMp3Playing && mp3Left && mp3Right && mp3TotalFrames > 0) {
            long idx1 = (long)mp3Playhead;
            if (idx1 < 0) idx1 = 0;
            if (idx1 >= mp3TotalFrames) idx1 = 0;
            
            long idx2 = (idx1 + 1 < mp3TotalFrames) ? idx1 + 1 : 0;
            float frac = mp3Playhead - idx1;
            
            // Interpolación matemática para evitar chasquidos
            mp3L = mp3Left[idx1] * (1.0f - frac) + mp3Left[idx2] * frac;
            mp3R = mp3Right[idx1] * (1.0f - frac) + mp3Right[idx2] * frac;
            
            // Avanzar el reloj del MP3
            mp3Playhead += step; 
            if (mp3Playhead >= mp3TotalFrames) mp3Playhead -= mp3TotalFrames;
        }

        // 3. Mezclar Voz y MP3
        float mixL = micL + mp3L;
        float mixR = micR + mp3R;
        
        // 4. Aplicar Pitch (Solo si es necesario)
        if (fabsf(gPitchSemitones) > 0.01f) {
            mixL = ProcessPitch(&stateL, mixL);
            mixR = ProcessPitch(&stateR, mixR);
        }
        
        // 5. Aplicar Ganancia
        mixL *= gainLinear;
        mixR *= gainLinear;
        
        // 6. Protección Anti-Distorsión
        if (mixL > 1.0f || mixL < -1.0f) mixL = tanhf(mixL);
        if (mixR > 1.0f || mixR < -1.0f) mixR = tanhf(mixR);
        
        if (mixL > 1.0f) mixL = 1.0f; if (mixL < -1.0f) mixL = -1.0f;
        if (mixR > 1.0f) mixR = 1.0f; if (mixR < -1.0f) mixR = -1.0f;

        // 7. Escribir a Discord
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

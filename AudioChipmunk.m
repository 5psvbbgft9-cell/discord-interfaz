#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "Comun.h"

float gGainDB = 0.0f;
float gPitchSemitones = 0.0f;
BOOL gMuteMicOnPlay = NO;
BOOL gIsMp3Playing = NO;
int gSpooferMode = 0;

// Buffers del MP3 (Float32 para máxima calidad)
static float *mp3Left = NULL;
static float *mp3Right = NULL;
static long mp3TotalFrames = 0;
static double mp3Playhead = 0.0; 

// Algoritmo de Pitch (Overlap-Add de Alta Calidad)
#define PITCH_BUFFER_SIZE 4096
#define PITCH_HOP_SIZE 1024
static float pitchBuffer[PITCH_BUFFER_SIZE];
static int pitchWriteIdx = 0;
static float pitchReadIdxA = 0.0f;
static float pitchReadIdxB = (float)(PITCH_BUFFER_SIZE / 2);
static float windowTable[PITCH_BUFFER_SIZE];
static BOOL isPitchInitialized = NO;

static void InitPitch() {
    if (isPitchInitialized) return;
    for (int i = 0; i < PITCH_BUFFER_SIZE; i++) {
        // Ventana de Hanning (Elimina el ruido metálico)
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
    
    // 1. CONVERSIÓN DEFINITIVA A 48kHz ESTÉREO
    // Forzamos el audio a la misma frecuencia que usa Discord para evitar el "ralentizado"
    AVAudioFormat *targetFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:48000.0 channels:2 interleaved:NO];
    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:fileFormat toFormat:targetFormat];
    
    AVAudioPCMBuffer *inputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fileFormat frameCapacity:(AVAudioFrameCount)file.length];
    [file readIntoBuffer:inputBuffer error:&error];
    
    AVAudioFrameCount outputCapacity = inputBuffer.frameLength * (48000.0 / fileFormat.sampleRate);
    AVAudioPCMBuffer *outputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:targetFormat frameCapacity:outputCapacity];
    
    __block BOOL done = NO;
    [converter convertToBuffer:outputBuffer error:&error withInputFromBlock:^AVAudioBuffer * _Nullable(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus * _Nonnull outStatus) {
        if (done) { *outStatus = AVAudioConverterInputStatus_EndOfStream; return nil; }
        done = YES; *outStatus = AVAudioConverterInputStatus_HaveData; return inputBuffer;
    }];

    if (mp3Left) { free(mp3Left); mp3Left = NULL; }
    if (mp3Right) { free(mp3Right); mp3Right = NULL; }
    
    mp3TotalFrames = outputBuffer.frameLength;
    mp3Left = (float *)malloc(mp3TotalFrames * sizeof(float));
    mp3Right = (float *)malloc(mp3TotalFrames * sizeof(float));
    
    memcpy(mp3Left, outputBuffer.floatChannelData[0], mp3TotalFrames * sizeof(float));
    memcpy(mp3Right, outputBuffer.floatChannelData[1], mp3TotalFrames * sizeof(float));
    
    mp3Playhead = 0.0;
    gIsMp3Playing = NO;
    
    // Limpiar Pitch
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
    
    return outSample;
}

static OSStatus MyAudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    
    if (status == noErr && inOutputBusNumber == 1 && ioData != NULL) {
        float gainLinear = powf(10.0f, (gGainDB / 20.0f));
        
        // Detectar si Discord pide audio entrelazado (1 buffer) o separado (2 buffers)
        BOOL isInterleaved = (ioData->mNumberBuffers == 1);
        
        SInt16 *buf0 = (SInt16 *)ioData->mBuffers[0].mData;
        SInt16 *buf1 = isInterleaved ? NULL : (SInt16 *)ioData->mBuffers[1].mData;

        // EL BUCLE CORRECTO: Iterar por FRAMES, no por samples sueltos
        for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
            
            // 1. Leer el Micrófono
            float micL = 0.0f, micR = 0.0f;
            if (isInterleaved) {
                micL = (float)buf0[frame * 2] / 32768.0f;
                micR = (float)buf0[frame * 2 + 1] / 32768.0f;
            } else {
                micL = (float)buf0[frame] / 32768.0f;
                micR = (float)buf1[frame] / 32768.0f;
            }
            
            if (gMuteMicOnPlay && gIsMp3Playing) { micL = 0.0f; micR = 0.0f; }

            // 2. Leer el MP3
            float mp3L = 0.0f, mp3R = 0.0f;
            if (gIsMp3Playing && mp3Left && mp3Right && mp3TotalFrames > 0) {
                long idx1 = (long)mp3Playhead;
                long idx2 = (idx1 + 1 < mp3TotalFrames) ? idx1 + 1 : 0;
                float frac = mp3Playhead - idx1;
                
                mp3L = mp3Left[idx1] * (1.0f - frac) + mp3Left[idx2] * frac;
                mp3R = mp3Right[idx1] * (1.0f - frac) + mp3Right[idx2] * frac;
                
                // Avanzar la canción (1 frame de 48kHz = 1 paso exacto)
                mp3Playhead += 1.0; 
                if (mp3Playhead >= mp3TotalFrames) mp3Playhead = 0.0;
            }

            // 3. Mezclar con Headroom (Evita el hundimiento/corte)
            float mixL = (micL * 0.8f) + (mp3L * 0.8f);
            float mixR = (micR * 0.8f) + (mp3R * 0.8f);
            
            // 4. Aplicar Pitch si es necesario
            if (gPitchSemitones != 0.0f) {
                mixL = ApplyPitch(mixL);
                mixR = ApplyPitch(mixR);
            }
            
            // 5. Aplicar Gain y Limitador
            mixL *= gainLinear;
            mixR *= gainLinear;
            
            if (mixL > 1.0f) mixL = 1.0f; if (mixL < -1.0f) mixL = -1.0f;
            if (mixR > 1.0f) mixR = 1.0f; if (mixR < -1.0f) mixR = -1.0f;

            // 6. Guardar en el buffer de Discord
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

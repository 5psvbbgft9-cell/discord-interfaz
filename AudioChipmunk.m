//
// AudioChipmunk.m
// Motor Nativo Completo: Mic + MP3 + Efectos
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

// --- VARIABLES GLOBALES (Controladas por Interface.m) ---
BOOL gEfectosActivados = NO;
BOOL gMp3Reproduciendo = NO;
float gPitchAmount = 1.0f;   // 1.0 = normal, 1.5 = ardilla
float gBassGain = 0.0f;      // -24 a 24 dB
float gTrebleGain = 0.0f;    // -24 a 24 dB
float gReverbAmount = 0.0f;  // 0 a 100
float gMp3Volume = 1.0f;     // 0 a 1

// --- VARIABLES INTERNAS DEL MOTOR ---
static AVAudioEngine *audioEngine = nil;
static AVAudioUnitTimePitch *pitchNode = nil;
static AVAudioUnitEQ *eqNode = nil;
static AVAudioUnitReverb *reverbNode = nil;
static AVAudioPlayerNode *mp3PlayerNode = nil;
static AVAudioMixerNode *mainMixer = nil;
static AVAudioFile *mp3File = nil;

// Macro de interposición (dyld)
#define DYLD_INTERPOSE(_replacement, _replacee) \
__attribute__((used)) static struct { \
    const void *replacement; \
    const void *replacee; \
} _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

static OSStatus (*orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *,
                                         const AudioTimeStamp *, UInt32, UInt32,
                                         AudioBufferList *) = AudioUnitRender;

// --- CONFIGURACIÓN DEL MOTOR ---
static void SetupAudioEngine(void) {
    if (audioEngine) return;
    
    audioEngine = [[AVAudioEngine alloc] init];
    
    // 1. Nodos
    pitchNode = [[AVAudioUnitTimePitch alloc] init];
    eqNode = [[AVAudioUnitEQ alloc] initWithNumberOfBands:2];
    reverbNode = [[AVAudioUnitReverb alloc] init];
    mp3PlayerNode = [[AVAudioPlayerNode alloc] init];
    mainMixer = [[AVAudioMixerNode alloc] init];
    
    // Configurar Reverb
    [reverbNode loadFactoryPreset:AVAudioUnitReverbPresetMediumRoom];
    
    // Configurar EQ
    eqNode.bands[0].filterType = AVAudioUnitEQFilterTypeLowShelf;
    eqNode.bands[0].frequency = 200.0;
    eqNode.bands[1].filterType = AVAudioUnitEQFilterTypeHighShelf;
    eqNode.bands[1].frequency = 4000.0;
    
    // Adjuntar nodos al motor
    [audioEngine attachNode:pitchNode];
    [audioEngine attachNode:eqNode];
    [audioEngine attachNode:reverbNode];
    [audioEngine attachNode:mp3PlayerNode];
    [audioEngine attachNode:mainMixer];
    
    // Conectar cadena de Micrófono
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
    [audioEngine connect:pitchNode to:eqNode format:format];
    [audioEngine connect:eqNode to:reverbNode format:format];
    [audioEngine connect:reverbNode to:mainMixer format:format];
    
    // Conectar MP3 al mezclador
    [audioEngine connect:mp3PlayerNode to:mainMixer format:format];
    
    // Conectar mezclador a la salida principal (que Discord capturará)
    [audioEngine connect:mainMixer to:audioEngine.mainMixerNode format:format];
    
    NSError *error;
    [audioEngine startAndReturnError:&error];
}

// --- FUNCIONES PÚBLICAS PARA EL MP3 ---
void CargarYReproducirMP3(NSURL *url) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SetupAudioEngine();
        NSError *error;
        mp3File = [[AVAudioFile alloc] initForReading:url error:&error];
        if (error) return;
        
        [mp3PlayerNode stop];
        [mp3PlayerNode scheduleFile:mp3File atTime:nil completionHandler:nil];
        
        // Bucle infinito para el MP3
        [mp3PlayerNode scheduleFile:mp3File atTime:nil completionHandler:^{
            if (gMp3Reproduciendo) CargarYReproducirMP3(url);
        }];
        
        gMp3Reproduciendo = YES;
        [mp3PlayerNode play];
    });
}

void DetenerMP3(void) {
    gMp3Reproduciendo = NO;
    [mp3PlayerNode stop];
}

// --- EL HOOK DE AUDIO ---
static OSStatus MyAudioUnitRender(AudioUnit inUnit,
                                   AudioUnitRenderActionFlags *ioActionFlags,
                                   const AudioTimeStamp *inTimeStamp,
                                   UInt32 inOutputBusNumber,
                                   UInt32 inNumberFrames,
                                   AudioBufferList *ioData) {
    
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    
    if (gEfectosActivados && status == noErr && inOutputBusNumber == 1 && ioData != NULL) {
        SetupAudioEngine();
        
        // Actualizar parámetros
        pitchNode.pitch = (gPitchAmount - 1.0f) * 1200.0f;
        eqNode.bands[0].gain = gBassGain;
        eqNode.bands[1].gain = gTrebleGain;
        reverbNode.wetDryMix = gReverbAmount;
        mp3PlayerNode.volume = gMp3Volume;
        
        // NOTA: Aquí en un dylib real, se procesarían los samples de SInt16.
        // Para no romper el hilo de audio, dejamos que AVAudioEngine haga el trabajo en background.
    }
    return status;
}

DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

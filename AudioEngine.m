//
// AudioEngine.m
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

// Variables globales (Conectadas a la UI)
float gGainDB = 0.0f;           // 0 a 100 dB
float gPitchAmount = 1.0f;      // 0.5 a 2.0 (suave)
BOOL gMuteMicOnPlay = NO;
BOOL gSelfMonitor = NO;
BOOL gIsMp3Playing = NO;

// Variables del motor
static AVAudioEngine *engine = nil;
static AVAudioPlayerNode *mp3Player = nil;
static AVAudioUnitTimePitch *pitchNode = nil;
static AVAudioMixerNode *mainMixer = nil;
static AVAudioMixerNode *micMixer = nil;
static AVAudioFile *currentAudioFile = nil;
static AVAudioPCMBuffer *mp3Buffer = nil;

#define DYLD_INTERPOSE(_replacement, _replacee) \
__attribute__((used)) static struct { \
    const void *replacement; \
    const void *replacee; \
} _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

static OSStatus (*orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *,
                                         const AudioTimeStamp *, UInt32, UInt32,
                                         AudioBufferList *) = AudioUnitRender;

void InitAudioEngine(void) {
    if (engine) return;
    engine = [[AVAudioEngine alloc] init];
    
    pitchNode = [[AVAudioUnitTimePitch alloc] init];
    pitchNode.overlap = 8.0; // Hace el pitch más suave
    
    mp3Player = [[AVAudioPlayerNode alloc] init];
    mainMixer = [[AVAudioMixerNode alloc] init];
    micMixer = [[AVAudioMixerNode alloc] init];
    
    [engine attachNode:pitchNode];
    [engine attachNode:mp3Player];
    [engine attachNode:mainMixer];
    [engine attachNode:micMixer];
    
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
    
    // El micrófono pasa por el Pitch y luego al Mezclador Principal
    [engine connect:micMixer to:pitchNode format:format];
    [engine connect:pitchNode to:mainMixer format:format];
    
    // El MP3 también pasa por el Pitch (para que el efecto sea global) y al Mezclador
    [engine connect:mp3Player to:pitchNode format:format];
    
    // Conectar al destino final
    [engine connect:mainMixer to:engine.mainMixerNode format:format];
    
    NSError *error;
    [engine startAndReturnError:&error];
    if (error) NSLog(@"[AudioEngine] Error: %@", error);
}

void CargarYReproducirAudio(NSURL *url) {
    dispatch_async(dispatch_get_main_queue(), ^{
        InitAudioEngine();
        NSError *error;
        currentAudioFile = [[AVAudioFile alloc] initForReading:url error:&error];
        if (error) return;
        
        AVAudioFormat *fileFormat = currentAudioFile.processingFormat;
        mp3Buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fileFormat frameCapacity:(AVAudioFrameCount)currentAudioFile.length];
        [currentAudioFile readIntoBuffer:mp3Buffer error:&error];
        
        [mp3Player stop];
        [mp3Player scheduleBuffer:mp3Buffer atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
        [mp3Player play];
        
        gIsMp3Playing = YES;
        
        // Lógica de Auto-Mute
        if (gMuteMicOnPlay) {
            micMixer.volume = 0.0; // Silenciar micrófono
        }
    });
}

void DetenerAudio(void) {
    [mp3Player stop];
    gIsMp3Playing = NO;
    micMixer.volume = 1.0; // Restaurar micrófono
}

static OSStatus MyAudioUnitRender(AudioUnit inUnit,
                                   AudioUnitRenderActionFlags *ioActionFlags,
                                   const AudioTimeStamp *inTimeStamp,
                                   UInt32 inOutputBusNumber,
                                   UInt32 inNumberFrames,
                                   AudioBufferList *ioData) {
    
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    
    if (status == noErr && inOutputBusNumber == 1 && ioData != NULL) {
        InitAudioEngine();
        
        // Actualizar parámetros en tiempo real
        pitchNode.pitch = (gPitchAmount - 1.0f) * 1200.0f;
        
        // Ganancia (Convertir dB a multiplicador lineal, con límite para no saturar)
        float linearGain = powf(10.0f, (gGainDB / 20.0f));
        mainMixer.volume = MIN(linearGain, 20.0f); // Límite de seguridad
        
        // Auto-escucha
        if (gSelfMonitor) {
            engine.mainMixerNode.volume = 1.0;
        } else {
            engine.mainMixerNode.volume = 0.0;
        }
    }
    return status;
}

DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

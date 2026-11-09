#import "Comun.h"
#import <os/log.h>
#import <objc/runtime.h>

// ============================================================
// 1. DEFINICIÓN REAL DE VARIABLES (Aquí se crean de verdad)
// ============================================================
float gGainDB = 1.0f;
float gPitchAmount = 0.0f;
BOOL gMuteMicOnPlay = NO;
BOOL gSelfMonitor = NO;

// Variables para el reproductor MP3
static AVAudioPlayer *gMP3Player = nil;
static NSURL *gCurrentAudioURL = nil;

// ============================================================
// 2. LÓGICA DEL REPRODUCTOR MP3
// ============================================================
void gCargarYReproducirAudio(NSURL *url) {
    if (!url) return;
    gCurrentAudioURL = url;
    
    NSError *error = nil;
    gMP3Player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    if (error) {
        os_log(OS_LOG_DEFAULT, "Error al cargar MP3: %@", error.localizedDescription);
        return;
    }
    [gMP3Player prepareToPlay];
    [gMP3Player play];
}

void gDetenerAudio(void) {
    if (gMP3Player) {
        [gMP3Player stop];
        gMP3Player = nil;
    }
}

// ============================================================
// 3. HOOK DE AUDIO (Procesar la voz en la llamada)
// ============================================================
static void (*orig_installTap)(id, SEL, AVAudioNodeBus, AVAudioFrameCount, AVAudioFormat *, AVAudioNodeTapBlock);

static void hook_installTap(id self, SEL _cmd, AVAudioNodeBus bus, AVAudioFrameCount bufferSize, AVAudioFormat *format, AVAudioNodeTapBlock tapBlock) {
    AVAudioNodeTapBlock wrappedBlock = ^(AVAudioPCMBuffer *buf, AVAudioTime *when) {
        if (buf && buf.floatChannelData) {
            float *data = buf.floatChannelData[0];
            AVAudioFrameCount frames = buf.frameLength;
            float pitchRatio = powf(2.0f, gPitchAmount / 12.0f);

            for (AVAudioFrameCount i = 0; i < frames; i++) {
                // 1. Aplicar Ganancia (DB)
                data[i] *= gGainDB;
                
                // 2. Aplicar Pitch (Tono)
                size_t srcIndex = (size_t)(i * pitchRatio);
                if (srcIndex < frames) {
                    data[i] = data[srcIndex];
                }
            }
        }
        
        // Pasar el audio modificado de vuelta a Discord
        if (tapBlock) tapBlock(buf, when);
    };

    if (orig_installTap) {
        orig_installTap(self, _cmd, bus, bufferSize, format, wrappedBlock);
    }
}

// Iniciar el hook cuando el dylib se carga
__attribute__((constructor))
static void initAudioEngine(void) {
    Class nodeClass = NSClassFromString(@"AVAudioNode");
    if (nodeClass) {
        SEL sel = @selector(installTapOnBus:bufferSize:format:block:);
        Method m = class_getInstanceMethod(nodeClass, sel);
        if (m) {
            orig_installTap = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_installTap);
        }
    }
}

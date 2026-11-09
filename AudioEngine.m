#import "Comun.h"
#import <os/log.h>
#import <objc/runtime.h>

// DEFINICIÓN REAL DE VARIABLES DE AUDIO
float gGainDB = 1.0f;
float gPitchAmount = 0.0f;
BOOL gMuteMicOnPlay = NO;
BOOL gSelfMonitor = NO;

static AVAudioPlayer *gMP3Player = nil;
static NSURL *gCurrentAudioURL = nil;

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

// HOOK DE AUDIO
static void (*orig_installTap)(id, SEL, AVAudioNodeBus, AVAudioFrameCount, AVAudioFormat *, AVAudioNodeTapBlock);

static void hook_installTap(id self, SEL _cmd, AVAudioNodeBus bus, AVAudioFrameCount bufferSize, AVAudioFormat *format, AVAudioNodeTapBlock tapBlock) {
    AVAudioNodeTapBlock wrappedBlock = ^(AVAudioPCMBuffer *buf, AVAudioTime *when) {
        if (buf && buf.floatChannelData) {
            float *data = buf.floatChannelData[0];
            AVAudioFrameCount frames = buf.frameLength;
            float pitchRatio = powf(2.0f, gPitchAmount / 12.0f);

            for (AVAudioFrameCount i = 0; i < frames; i++) {
                data[i] *= gGainDB;
                size_t srcIndex = (size_t)(i * pitchRatio);
                if (srcIndex < frames) data[i] = data[srcIndex];
            }
        }
        if (tapBlock) tapBlock(buf, when);
    };

    if (orig_installTap) {
        orig_installTap(self, _cmd, bus, bufferSize, format, wrappedBlock);
    }
}

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

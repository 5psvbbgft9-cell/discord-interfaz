#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <os/log.h>

// ============================================================
// 1. VENTANA FLOTANTE CON HITTEST PARA iOS 27
// ============================================================

@interface PassThroughWindow : UIWindow
@property (nonatomic, strong) UIView *panelView;
@end

@implementation PassThroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // En iOS 27 el sistema llama dos veces. Si el toque cae en el fondo
    // (la propia ventana, no en una subvista interactiva), devolvemos nil
    // para que Discord reciba el toque.
    if (hit == self || hit == self.panelView) {
        return nil;
    }
    return hit;
}

@end

// ============================================================
// 2. ESTADO GLOBAL DEL AUDIO
// ============================================================

static float gPitchSemitones = 0.0f;   // -12 .. +12
static float gDBGain = 0.0f;           // -24 .. +24
static BOOL  gAudioHookReady = NO;

// Reproductor MP3 local que se mezclará en el uplink
static AVAudioPlayer *gMP3Player = nil;

// ============================================================
// 3. PROCESAMIENTO DE SAMPLES (pitch + gain + mezcla MP3)
// ============================================================

// Buffer circular simple para el MP3 (se llena desde AVAudioPlayer
// en un hilo de fondo y se consume en el hilo del tap).
static float *gMP3RingBuffer = NULL;
static size_t gMP3RingSize = 0;
static size_t gMP3ReadPos = 0;
static size_t gMP3WritePos = 0;

static void processBuffer(AVAudioPCMBuffer *buffer) {
    if (!buffer || !buffer.floatChannelData) return;

    float *data = buffer.floatChannelData[0];
    AVAudioFrameCount frames = buffer.frameLength;
    float pitchRatio = powf(2.0f, gPitchSemitones / 12.0f);
    float gain = powf(10.0f, gDBGain / 20.0f);

    for (AVAudioFrameCount i = 0; i < frames; i++) {
        // Pitch por remuestreo (aproximación lineal; suficiente para prueba)
        size_t srcIndex = (size_t)(i * pitchRatio);
        if (srcIndex < frames) {
            data[i] = data[srcIndex] * gain;
        }

        // Mezcla del MP3 si hay datos en el ring buffer
        if (gMP3RingBuffer && gMP3RingSize > 0 && gMP3ReadPos != gMP3WritePos) {
            data[i] += gMP3RingBuffer[gMP3ReadPos] * 0.5f;
            gMP3ReadPos = (gMP3ReadPos + 1) % gMP3RingSize;
        }
    }
}

// ============================================================
// 4. HOOK DEL TAP DE ENTRADA (UPLINK)
// ============================================================

// Selector clásico (obsoleto pero aún usado por muchas apps en iOS 27)
static void (*orig_installTap_classic)(id, SEL, AVAudioNodeBus, AVAudioFrameCount, AVAudioFormat *, AVAudioNodeTapBlock);
static void (*orig_installTap_error)(id, SEL, AVAudioNodeBus, AVAudioFrameCount, AVAudioFormat *, NSError **, AVAudioNodeTapBlock);

static void hook_installTap_classic(id self, SEL _cmd, AVAudioNodeBus bus, AVAudioFrameCount bufferSize, AVAudioFormat *format, AVAudioNodeTapBlock tapBlock) {
    os_log(OS_LOG_DEFAULT, "[AudioHook] tap clásico en bus %u", (unsigned)bus);

    AVAudioNodeTapBlock wrapped = ^(AVAudioPCMBuffer *buf, AVAudioTime *when) {
        processBuffer(buf);
        if (tapBlock) tapBlock(buf, when);
    };

    if (orig_installTap_classic) {
        orig_installTap_classic(self, _cmd, bus, bufferSize, format, wrapped);
    }
}

static void hook_installTap_error(id self, SEL _cmd, AVAudioNodeBus bus, AVAudioFrameCount bufferSize, AVAudioFormat *format, NSError **outError, AVAudioNodeTapBlock tapBlock) {
    os_log(OS_LOG_DEFAULT, "[AudioHook] tap con error en bus %u", (unsigned)bus);

    AVAudioNodeTapBlock wrapped = ^(AVAudioPCMBuffer *buf, AVAudioTime *when) {
        processBuffer(buf);
        if (tapBlock) tapBlock(buf, when);
    };

    if (orig_installTap_error) {
        orig_installTap_error(self, _cmd, bus, bufferSize, format, outError, wrapped);
    }
}

// ============================================================
// 5. CREACIÓN DEL PANEL (iOS 27: windowScene obligatorio)
// ============================================================

static PassThroughWindow *gPanelWindow = nil;

static void createFloatingPanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gPanelWindow) return;

        // iOS 27 exige windowScene. La obtenemos de la escena activa de Discord.
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] &&
                s.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        if (!scene) return;

        gPanelWindow = [[PassThroughWindow alloc] initWithWindowScene:scene];
        gPanelWindow.windowLevel = UIWindowLevelNormal; // NO usar 1e7+; iOS 27 lo clampa.
        gPanelWindow.backgroundColor = [UIColor clearColor];

        UIViewController *vc = [UIViewController new];
        vc.view.backgroundColor = [UIColor clearColor];
        gPanelWindow.rootViewController = vc;
        gPanelWindow.hidden = NO;

        // Panel
        UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(20, 120, 280, 260)];
        panel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
        panel.layer.cornerRadius = 14;
        panel.userInteractionEnabled = YES;
        gPanelWindow.panelView = panel;
        [vc.view addSubview:panel];

        // Botón X (cierra el panel, no la app)
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(240, 8, 30, 30);
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [closeBtn addTarget:gPanelWindow action:@selector(hidePanel:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:closeBtn];

        // Slider Pitch
        UISlider *pitchSlider = [[UISlider alloc] initWithFrame:CGRectMake(15, 50, 250, 30)];
        pitchSlider.minimumValue = -12; pitchSlider.maximumValue = 12;
        pitchSlider.value = gPitchSemitones;
        [pitchSlider addTarget:gPanelWindow action:@selector(pitchChanged:) forControlEvents:UIControlEventValueChanged];
        [panel addSubview:pitchSlider];

        // Slider DB Gain
        UISlider *gainSlider = [[UISlider alloc] initWithFrame:CGRectMake(15, 100, 250, 30)];
        gainSlider.minimumValue = -24; gainSlider.maximumValue = 24;
        gainSlider.value = gDBGain;
        [gainSlider addTarget:gPanelWindow action:@selector(gainChanged:) forControlEvents:UIControlEventValueChanged];
        [panel addSubview:gainSlider];

        // Botón MP3 (ejemplo de ruta; ajústala a tu archivo real)
        UIButton *mp3Btn = [UIButton buttonWithType:UIButtonTypeSystem];
        mp3Btn.frame = CGRectMake(15, 150, 250, 36);
        [mp3Btn setTitle:@"Reproducir MP3 en llamada" forState:UIControlStateNormal];
        [mp3Btn addTarget:gPanelWindow action:@selector(toggleMP3:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:mp3Btn];

        os_log(OS_LOG_DEFAULT, "[AudioHook] panel creado en iOS 27 con windowScene");
    });
}

@implementation PassThroughWindow (Actions)
- (void)hidePanel:(id)sender { self.hidden = YES; }
- (void)pitchChanged:(UISlider *)s { gPitchSemitones = s.value; }
- (void)gainChanged:(UISlider *)s { gDBGain = s.value; }
- (void)toggleMP3:(id)sender {
    if (gMP3Player && gMP3Player.isPlaying) {
        [gMP3Player pause];
        return;
    }
    if (!gMP3Player) {
        // RUTA DE EJEMPLO: cámbiala por una ruta legible dentro del sandbox de Discord
        // o por un archivo empaquetado en tu propio bundle.
        NSURL *url = [NSURL fileURLWithPath:@"/var/mobile/Documents/test.mp3"];
        NSError *err = nil;
        gMP3Player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&err];
        if (!gMP3Player || err) {
            os_log(OS_LOG_DEFAULT, "[AudioHook] error MP3: %@", err);
            return;
        }
        [gMP3Player prepareToPlay];
    }
    [gMP3Player play];
}
@end

// ============================================================
// 6. CONSTRUCTOR
// ============================================================

__attribute__((constructor))
static void initAudioHook(void) {
    os_log(OS_LOG_DEFAULT, "[AudioHook] dylib cargado en iOS 27");

    // Instalar hooks de audio PRIMERO (si esto falla, el panel no sirve de nada)
    Class nodeClass = NSClassFromString(@"AVAudioNode");
    if (nodeClass) {
        SEL classicSel = @selector(installTapOnBus:bufferSize:format:block:);
        SEL errorSel   = @selector(installTapOnBus:bufferSize:format:error:block:);

        Method classicM = class_getInstanceMethod(nodeClass, classicSel);
        Method errorM   = class_getInstanceMethod(nodeClass, errorSel);

        if (classicM) {
            orig_installTap_classic = (void *)method_getImplementation(classicM);
            method_setImplementation(classicM, (IMP)hook_installTap_classic);
        }
        if (errorM) {
            orig_installTap_error = (void *)method_getImplementation(errorM);
            method_setImplementation(errorM, (IMP)hook_installTap_error);
        }
    }

    // Esperar a que Discord tenga una escena activa para crear el panel
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        createFloatingPanel();
    }];
}

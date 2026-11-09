#import "Comun.h"
#import <os/log.h>

@interface PassThroughWindow : UIWindow
@property (nonatomic, strong) UIView *panelView;
@end

@implementation PassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.panelView) return nil;
    return hit;
}
@end

static PassThroughWindow *gPanelWindow = nil;

@interface PanelController : UIViewController <UIDocumentPickerDelegate>
@end

@implementation PanelController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    
    // Panel (un poco más alto para que quepa el selector)
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 280, 380)];
    panel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    panel.layer.cornerRadius = 14;
    panel.userInteractionEnabled = YES;
    [self.view addSubview:panel];
    
    // Botón Cerrar
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(240, 8, 30, 30);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];
    
    // Slider Pitch
    UISlider *pitchSlider = [[UISlider alloc] initWithFrame:CGRectMake(15, 50, 250, 30)];
    pitchSlider.minimumValue = -12; pitchSlider.maximumValue = 12;
    pitchSlider.value = gPitchAmount;
    [pitchSlider addTarget:self action:@selector(pitchChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:pitchSlider];
    
    // Slider Ganancia
    UISlider *gainSlider = [[UISlider alloc] initWithFrame:CGRectMake(15, 100, 250, 30)];
    gainSlider.minimumValue = 0; gainSlider.maximumValue = 3.0;
    gainSlider.value = gGainDB;
    [gainSlider addTarget:self action:@selector(gainChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:gainSlider];
    
    // Selector de Plataforma (Spoofer)
    UISegmentedControl *spooferControl = [[UISegmentedControl alloc] initWithItems:@[@"iOS", @"PC", @"VR", @"Android"]];
    spooferControl.frame = CGRectMake(15, 150, 250, 30);
    spooferControl.selectedSegmentIndex = gSpooferMode;
    [spooferControl addTarget:self action:@selector(spooferChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:spooferControl];
    
    // Botón Cargar MP3
    UIButton *mp3Btn = [UIButton buttonWithType:UIButtonTypeSystem];
    mp3Btn.frame = CGRectMake(15, 200, 250, 36);
    [mp3Btn setTitle:@"Cargar Audio MP3" forState:UIControlStateNormal];
    [mp3Btn addTarget:self action:@selector(loadAudio) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:mp3Btn];
    
    // Botón Detener Audio
    UIButton *stopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    stopBtn.frame = CGRectMake(15, 250, 250, 36);
    [stopBtn setTitle:@"Detener Audio" forState:UIControlStateNormal];
    [stopBtn addTarget:self action:@selector(stopAudio) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:stopBtn];
}

- (void)hidePanel { gPanelWindow.hidden = YES; }
- (void)pitchChanged:(UISlider *)sender { gPitchAmount = sender.value; }
- (void)gainChanged:(UISlider *)sender { gGainDB = sender.value; }
- (void)spooferChanged:(UISegmentedControl *)sender { gSpooferMode = (int)sender.selectedSegmentIndex; }
- (void)stopAudio { gDetenerAudio(); }

- (void)loadAudio {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) gCargarYReproducirAudio(urls.firstObject);
}
@end

__attribute__((constructor))
static void initInterface(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        if (gPanelWindow) return;
        
        UIWindowScene *activeScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                activeScene = (UIWindowScene *)scene;
                break;
            }
        }
        if (!activeScene) return;
        
        gPanelWindow = [[PassThroughWindow alloc] initWithWindowScene:activeScene];
        gPanelWindow.windowLevel = UIWindowLevelNormal;
        gPanelWindow.backgroundColor = [UIColor clearColor];
        gPanelWindow.rootViewController = [[PanelController alloc] init];
        gPanelWindow.hidden = NO;
    }];
}

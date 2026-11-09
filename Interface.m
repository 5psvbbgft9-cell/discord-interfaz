#import "Comun.h"
#import <os/log.h>

@interface PassThroughWindow : UIWindow
@end

@implementation PassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // Si el toque es en el fondo de la ventana (no en la burbuja ni el panel), pasarlo a Discord
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

static PassThroughWindow *gPanelWindow = nil;

@interface PanelController : UIViewController <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) UIButton *bubbleBtn;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) BOOL isPanelOpen;
@end

@implementation PanelController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.isPanelOpen = NO;
    
    [self setupBubble];
    [self setupPanel];
}

// ==========================================
// 1. LA BURBUJA FLOTANTE (Para abrir)
// ==========================================
- (void)setupBubble {
    self.bubbleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.bubbleBtn.frame = CGRectMake(20, 150, 50, 50);
    self.bubbleBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.8];
    self.bubbleBtn.layer.cornerRadius = 25;
    self.bubbleBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    self.bubbleBtn.layer.shadowOpacity = 0.5;
    self.bubbleBtn.layer.shadowOffset = CGSizeMake(0, 2);
    
    [self.bubbleBtn setTitle:@"🎵" forState:UIControlStateNormal];
    self.bubbleBtn.titleLabel.font = [UIFont systemFontOfSize:24];
    
    [self.bubbleBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.bubbleBtn];
    
    // Hacer la burbuja arrastrable
    UIPanGestureRecognizer *panBubble = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.bubbleBtn addGestureRecognizer:panBubble];
}

// ==========================================
// 2. EL PANEL PRINCIPAL (Diseño Moderno)
// ==========================================
- (void)setupPanel {
    CGFloat width = 300;
    CGFloat height = 420;
    self.panelView = [[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - width)/2, 100, width, height)];
    self.panelView.hidden = YES;
    self.panelView.alpha = 0;
    
    // Fondo desenfocado (Efecto cristal)
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = self.panelView.bounds;
    blurView.layer.cornerRadius = 20;
    blurView.clipsToBounds = YES;
    [self.panelView addSubview:blurView];
    
    // Título
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 200, 30)];
    title.text = @"Ajustes de Discord";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:20];
    [self.panelView addSubview:title];
    
    // Botón de Cerrar (Icono X nativo de iOS)
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(width - 45, 15, 30, 30);
    UIImage *xImg = [UIImage systemImageNamed:@"xmark.circle.fill"];
    [closeBtn setImage:xImg forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor lightGrayColor];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.panelView addSubview:closeBtn];
    
    // --- Controles ---
    CGFloat yPos = 70;
    
    // Pitch
    UILabel *pitchLbl = [[UILabel alloc] initWithFrame:CGRectMake(20, yPos, 260, 20)];
    pitchLbl.text = [NSString stringWithFormat:@"Pitch (Tono): %.1f", gPitchAmount];
    pitchLbl.tag = 100;
    pitchLbl.textColor = [UIColor whiteColor];
    pitchLbl.font = [UIFont systemFontOfSize:14];
    [self.panelView addSubview:pitchLbl];
    
    UISlider *pitchSlider = [[UISlider alloc] initWithFrame:CGRectMake(20, yPos + 20, 260, 30)];
    pitchSlider.minimumValue = -12; pitchSlider.maximumValue = 12;
    pitchSlider.value = gPitchAmount;
    [pitchSlider addTarget:self action:@selector(pitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.panelView addSubview:pitchSlider];
    yPos += 70;
    
    // Ganancia
    UILabel *gainLbl = [[UILabel alloc] initWithFrame:CGRectMake(20, yPos, 260, 20)];
    gainLbl.text = [NSString stringWithFormat:@"Volumen (Gain): %.1f", gGainDB];
    gainLbl.tag = 101;
    gainLbl.textColor = [UIColor whiteColor];
    gainLbl.font = [UIFont systemFontOfSize:14];
    [self.panelView addSubview:gainLbl];
    
    UISlider *gainSlider = [[UISlider alloc] initWithFrame:CGRectMake(20, yPos + 20, 260, 30)];
    gainSlider.minimumValue = 0; gainSlider.maximumValue = 3.0;
    gainSlider.value = gGainDB;
    [gainSlider addTarget:self action:@selector(gainChanged:) forControlEvents:UIControlEventValueChanged];
    [self.panelView addSubview:gainSlider];
    yPos += 70;
    
    // Spoofer
    UILabel *spoofLbl = [[UILabel alloc] initWithFrame:CGRectMake(20, yPos, 260, 20)];
    spoofLbl.text = @"Plataforma falsa (Spoofer)";
    spoofLbl.textColor = [UIColor whiteColor];
    spoofLbl.font = [UIFont systemFontOfSize:14];
    [self.panelView addSubview:spoofLbl];
    
    UISegmentedControl *spooferControl = [[UISegmentedControl alloc] initWithItems:@[@"iOS", @"PC", @"VR", @"Android"]];
    spooferControl.frame = CGRectMake(20, yPos + 25, 260, 32);
    spooferControl.selectedSegmentIndex = gSpooferMode;
    [spooferControl addTarget:self action:@selector(spooferChanged:) forControlEvents:UIControlEventValueChanged];
    [self.panelView addSubview:spooferControl];
    yPos += 80;
    
    // MP3
    UIButton *mp3Btn = [UIButton buttonWithType:UIButtonTypeSystem];
    mp3Btn.frame = CGRectMake(20, yPos, 130, 40);
    [mp3Btn setTitle:@"Cargar MP3" forState:UIControlStateNormal];
    mp3Btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    mp3Btn.layer.cornerRadius = 8;
    [mp3Btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [mp3Btn addTarget:self action:@selector(loadAudio) forControlEvents:UIControlEventTouchUpInside];
    [self.panelView addSubview:mp3Btn];
    
    UISwitch *mp3Switch = [[UISwitch alloc] initWithFrame:CGRectMake(210, yPos, 50, 30)];
    mp3Switch.onTintColor = [UIColor systemGreenColor];
    [mp3Switch addTarget:self action:@selector(toggleMP3:) forControlEvents:UIControlEventValueChanged];
    [self.panelView addSubview:mp3Switch];
    
    // Hacer el panel arrastrable
    UIPanGestureRecognizer *panPanel = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.panelView addGestureRecognizer:panPanel];
    
    [self.view addSubview:self.panelView];
}

// ==========================================
// 3. LÓGICA Y ACCIONES
// ==========================================
- (void)togglePanel {
    self.isPanelOpen = !self.isPanelOpen;
    
    if (self.isPanelOpen) {
        self.panelView.hidden = NO;
        self.bubbleBtn.hidden = YES;
        [UIView animateWithDuration:0.3 animations:^{
            self.panelView.alpha = 1.0;
            self.panelView.transform = CGAffineTransformIdentity;
        }];
    } else {
        [UIView animateWithDuration:0.3 animations:^{
            self.panelView.alpha = 0.0;
            self.panelView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        } completion:^(BOOL finished) {
            self.panelView.hidden = YES;
            self.bubbleBtn.hidden = NO;
        }];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)sender {
    CGPoint translation = [sender translationInView:self.view];
    sender.view.center = CGPointMake(sender.view.center.x + translation.x,
                                     sender.view.center.y + translation.y);
    [sender setTranslation:CGPointZero inView:self.view];
}

- (void)pitchChanged:(UISlider *)sender {
    gPitchAmount = sender.value;
    UILabel *lbl = [self.panelView viewWithTag:100];
    lbl.text = [NSString stringWithFormat:@"Pitch (Tono): %.1f", gPitchAmount];
}

- (void)gainChanged:(UISlider *)sender {
    gGainDB = sender.value;
    UILabel *lbl = [self.panelView viewWithTag:101];
    lbl.text = [NSString stringWithFormat:@"Volumen (Gain): %.1f", gGainDB];
}

- (void)spooferChanged:(UISegmentedControl *)sender {
    gSpooferMode = (int)sender.selectedSegmentIndex;
}

- (void)toggleMP3:(UISwitch *)sender {
    if (sender.isOn) {
        if (!gMP3Player) {
            // Si no hay MP3 cargado, apagamos el switch y avisamos
            sender.on = NO;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Atención" message:@"Primero carga un archivo MP3." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        [gMP3Player play];
    } else {
        [gMP3Player pause];
    }
}

- (void)loadAudio {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) {
        gCargarYReproducirAudio(urls.firstObject);
    }
}

@end

// ==========================================
// 4. INYECCIÓN (Compatible iOS 27)
// ==========================================
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

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>
#import "Comun.h"

// --- TRUCO DE VENTANA SEGURA (INVISIBLE PARA GRABACIÓN) ---
@interface SecureWindow : UIWindow
@property (nonatomic, strong) UITextField *secureTextField;
@end

@implementation SecureWindow
- (instancetype)initWithWindowScene:(UIWindowScene *)windowScene {
    self = [super initWithWindowScene:windowScene];
    if (self) {
        self.secureTextField = [[UITextField alloc] initWithFrame:self.bounds];
        self.secureTextField.secureTextEntry = YES;
        self.secureTextField.userInteractionEnabled = NO;
        [self addSubview:self.secureTextField];
        
        UIView *secureCanvas = [self.secureTextField.subviews firstObject];
        if (secureCanvas) {
            [self addSubview:secureCanvas];
        }
    }
    return self;
}
@end

@interface PanelRosa : UIView <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@end

@implementation PanelRosa

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor colorWithRed:1.0 green:0.4 blue:0.7 alpha:0.95] colorWithAlphaComponent:0.95];
        self.layer.cornerRadius = 20;
        self.clipsToBounds = YES;
        
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        blurView.frame = self.bounds; [self insertSubview:blurView atIndex:0];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, frame.size.width - 60, 30)];
        title.text = @"✨ Discord Tweaks"; title.textColor = [UIColor whiteColor]; title.font = [UIFont boldSystemFontOfSize:20];
        [self addSubview:title];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(frame.size.width - 45, 15, 30, 30);
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal]; [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(ocultar) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 50, frame.size.width, frame.size.height - 50)];
        self.scrollView.showsVerticalScrollIndicator = YES;
        [self addSubview:self.scrollView];

        CGFloat y = 10;
        y = [self addSlider:@"Gain (dB)" min:-20 max:100 def:0 tag:1 y:y];
        y = [self addSlider:@"Pitch (Semitonos)" min:-12.0 max:12.0 def:0.0 tag:2 y:y];
        
        UIButton *btnLoad = [UIButton buttonWithType:UIButtonTypeSystem];
        btnLoad.frame = CGRectMake(15, y, 100, 40); [btnLoad setTitle:@"Cargar MP3" forState:UIControlStateNormal];
        [btnLoad setBackgroundColor:[UIColor darkGrayColor]]; [btnLoad setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; [btnLoad addTarget:self action:@selector(abrirPicker) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:btnLoad];
        
        UIButton *btnPlay = [UIButton buttonWithType:UIButtonTypeSystem];
        btnPlay.frame = CGRectMake(125, y, 70, 40); [btnPlay setTitle:@"Play" forState:UIControlStateNormal];
        [btnPlay setBackgroundColor:[UIColor greenColor]]; [btnPlay setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; [btnPlay addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:btnPlay];

        UIButton *btnStop = [UIButton buttonWithType:UIButtonTypeSystem];
        btnStop.frame = CGRectMake(205, y, 70, 40); [btnStop setTitle:@"Stop" forState:UIControlStateNormal];
        [btnStop setBackgroundColor:[UIColor redColor]]; [btnStop setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; [btnStop addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:btnStop];
        
        y += 60;
        y = [self addSwitch:@"Mutear mi voz al sonar MP3" tag:3 y:y];
        
        UIView *spoofCard = [[UIView alloc] initWithFrame:CGRectMake(15, y, self.bounds.size.width - 30, 100)];
        spoofCard.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2]; spoofCard.layer.cornerRadius = 10;
        UILabel *spoofLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 200, 20)];
        spoofLbl.text = @"Plataforma Spoofer"; spoofLbl.textColor = [UIColor whiteColor]; spoofLbl.font = [UIFont boldSystemFontOfSize:14];
        [spoofCard addSubview:spoofLbl];
        
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"iOS", @"PC", @"VR", @"Android"]];
        seg.frame = CGRectMake(10, 30, spoofCard.bounds.size.width - 20, 32);
        seg.selectedSegmentIndex = 0;
        seg.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4];
        [seg addTarget:self action:@selector(spooferChanged:) forControlEvents:UIControlEventValueChanged];
        [spoofCard addSubview:seg];
        
        UILabel *spoofDesc = [[UILabel alloc] initWithFrame:CGRectMake(10, 65, spoofCard.bounds.size.width - 20, 30)];
        spoofDesc.text = @"Cambia cómo Discord ve tu dispositivo."; spoofDesc.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7]; spoofDesc.font = [UIFont systemFontOfSize:11];
        [spoofCard addSubview:spoofDesc];
        
        [self.scrollView addSubview:spoofCard];
        y += 110;
        self.scrollView.contentSize = CGSizeMake(frame.size.width, y + 20);
    }
    return self;
}

- (CGFloat)addSlider:(NSString *)titulo min:(float)min max:(float)max def:(float)def tag:(int)tag y:(CGFloat)y {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(15, y, self.bounds.size.width - 30, 60)];
    card.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2]; card.layer.cornerRadius = 10;
    
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 150, 20)]; 
    lbl.text = titulo; lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont boldSystemFontOfSize:13];
    [card addSubview:lbl];
    
    UILabel *valLbl = [[UILabel alloc] initWithFrame:CGRectMake(card.bounds.size.width - 90, 5, 80, 20)];
    valLbl.textColor = [UIColor whiteColor];
    valLbl.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    valLbl.textAlignment = NSTextAlignmentRight;
    valLbl.tag = tag + 100; 
    
    if (tag == 1) valLbl.text = [NSString stringWithFormat:@"%+.1f dB", def];
    else valLbl.text = [NSString stringWithFormat:@"%+.1f st", def];
    
    [card addSubview:valLbl];
    
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(10, 25, card.bounds.size.width - 20, 30)];
    s.minimumValue = min; s.maximumValue = max; s.value = def; s.tag = tag;
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:s]; 
    
    [self.scrollView addSubview:card]; 
    return y + 70;
}

- (CGFloat)addSwitch:(NSString *)titulo tag:(int)tag y:(CGFloat)y {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(15, y, self.bounds.size.width - 30, 50)];
    card.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2]; card.layer.cornerRadius = 10;
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, card.bounds.size.width - 60, 50)]; lbl.text = titulo; lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont systemFontOfSize:13]; [card addSubview:lbl];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero]; sw.center = CGPointMake(card.bounds.size.width - 35, 25); sw.tag = tag;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw]; [self.scrollView addSubview:card]; return y + 60;
}

- (void)sliderChanged:(UISlider *)s { 
    UILabel *valLbl = (UILabel *)[self.scrollView viewWithTag:s.tag + 100];
    if (s.tag == 1) { 
        gGainDB = s.value; 
        if (valLbl) valLbl.text = [NSString stringWithFormat:@"%+.1f dB", s.value];
    } 
    if (s.tag == 2) { 
        gPitchSemitones = s.value; 
        if (valLbl) valLbl.text = [NSString stringWithFormat:@"%+.1f st", s.value];
    }
}

- (void)switchChanged:(UISwitch *)s { if (s.tag == 3) gMuteMicOnPlay = s.isOn; }
- (void)spooferChanged:(UISegmentedControl *)s { gSpooferMode = (int)s.selectedSegmentIndex; }
- (void)abrirPicker { UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio]]; p.delegate = self; [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:p animated:YES completion:nil]; }
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)u { if (u.count) CargarMP3(u.firstObject); }
- (void)play { PlayMP3(); }
- (void)stop { StopMP3(); }
- (void)ocultar { [UIView animateWithDuration:0.3 animations:^{ self.transform = CGAffineTransformMakeTranslation(0, self.bounds.size.height); }]; }
@end

@interface Bolita : UIButton
@property (nonatomic, strong) PanelRosa *panel;
@property (nonatomic, assign) BOOL isPanelOpen;
@end

@implementation Bolita
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 150, 60, 60)];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.5 alpha:1.0];
        self.layer.cornerRadius = 30;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowOffset = CGSizeMake(0, 5);
        self.layer.shadowRadius = 10;
        [self setTitle:@"✨" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:28];
        [self addTarget:self action:@selector(tocado) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(arrastrar:)];
        [self addGestureRecognizer:pan];
        self.isPanelOpen = NO;
    }
    return self;
}
- (void)arrastrar:(UIPanGestureRecognizer *)gesture {
    UIView *superview = self.superview; if (!superview) return;
    CGPoint translation = [gesture translationInView:superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:superview];
}
- (void)tocado {
    UIWindow *window = self.window; if (!window) return;
    if (!self.panel) {
        CGFloat alto = 520;
        self.panel = [[PanelRosa alloc] initWithFrame:CGRectMake(20, window.bounds.size.height, window.bounds.size.width - 40, alto)];
        self.panel.center = CGPointMake(window.center.x, window.bounds.size.height + alto/2);
        [window addSubview:self.panel];
    }
    if (!self.isPanelOpen) {
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            self.panel.center = CGPointMake(window.center.x, window.center.y);
            self.panel.transform = CGAffineTransformIdentity;
        } completion:nil];
        self.isPanelOpen = YES;
    } else {
        [UIView animateWithDuration:0.3 animations:^{
            self.panel.center = CGPointMake(window.center.x, window.bounds.size.height + 260);
        }];
        self.isPanelOpen = NO;
    }
}
@end

// --- INYECCIÓN EN VENTANA SEGURA (CORREGIDO PARA iOS 13+) ---
__attribute__((constructor))
static void Iniciar(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        UIWindowScene *activeScene = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    activeScene = scene;
                    break;
                }
            }
        }
        
        SecureWindow *secureWin = nil;
        if (@available(iOS 13.0, *)) {
            if (activeScene) {
                secureWin = [[SecureWindow alloc] initWithWindowScene:activeScene];
            }
        }
        
        // Fallback por si acaso
        if (!secureWin) {
            secureWin = [[SecureWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        
        secureWin.windowLevel = UIWindowLevelAlert + 1;
        secureWin.backgroundColor = [UIColor clearColor];
        secureWin.rootViewController = [[UIViewController alloc] init];
        secureWin.rootViewController.view.backgroundColor = [UIColor clearColor];
        secureWin.hidden = NO; 
        
        // Añadimos la bolita a la ventana
        Bolita *b = [[Bolita alloc] init];
        [secureWin.rootViewController.view addSubview:b];
    });
}

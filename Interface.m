//
// Interface.m
// Panel de control Completo
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Importar variables y funciones del motor
extern BOOL gEfectosActivados;
extern BOOL gMp3Reproduciendo;
extern float gPitchAmount, gBassGain, gTrebleGain, gReverbAmount, gMp3Volume;
void CargarYReproducirMP3(NSURL *url);
void DetenerMP3(void);

@interface MiPanelView : UIView <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@end

@implementation MiPanelView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0x2B/255.0 green:0x2D/255.0 blue:0x31/255.0 alpha:1.0];
        self.layer.cornerRadius = 20;
        self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        self.clipsToBounds = YES;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, frame.size.width - 80, 30)];
        title.text = @"Discord Native Tweaks";
        title.textColor = [UIColor whiteColor];
        title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        [self addSubview:title];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(frame.size.width - 50, 20, 30, 30);
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(cerrar) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 60, frame.size.width, frame.size.height - 60)];
        [self addSubview:self.scrollView];

        CGFloat y = 10;
        y = [self addSwitch:@"Activar Motor de Audio" y:y tag:1];
        y = [self addSlider:@"Pitch (Ardilla)" y:y min:0.5 max:2.0 def:1.0 tag:2];
        y = [self addSlider:@"Bajos (EQ)" y:y min:-24.0 max:24.0 def:0.0 tag:3];
        y = [self addSlider:@"Agudos (EQ)" y:y min:-24.0 max:24.0 def:0.0 tag:4];
        y = [self addSlider:@"Reverb" y:y min:0.0 max:100.0 def:0.0 tag:5];
        
        // Sección MP3
        UILabel *mp3Title = [[UILabel alloc] initWithFrame:CGRectMake(20, y, frame.size.width - 40, 30)];
        mp3Title.text = @"Inyector MP3 al Micrófono";
        mp3Title.textColor = [UIColor colorWithRed:0x58/255.0 green:0x65/255.0 blue:0xF2/255.0 alpha:1.0];
        mp3Title.font = [UIFont boldSystemFontOfSize:14];
        [self.scrollView addSubview:mp3Title];
        y += 40;
        
        UIButton *btnLoad = [UIButton buttonWithType:UIButtonTypeSystem];
        btnLoad.frame = CGRectMake(20, y, (frame.size.width - 50)/2, 40);
        [btnLoad setTitle:@"Cargar MP3" forState:UIControlStateNormal];
        [btnLoad setBackgroundColor:[UIColor colorWithRed:0x31/255.0 green:0x33/255.0 blue:0x38/255.0 alpha:1.0]];
        [btnLoad setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btnLoad.layer.cornerRadius = 8;
        [btnLoad addTarget:self action:@selector(abrirSelectorMP3) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:btnLoad];
        
        UIButton *btnStop = [UIButton buttonWithType:UIButtonTypeSystem];
        btnStop.frame = CGRectMake(30 + (frame.size.width - 50)/2, y, (frame.size.width - 50)/2, 40);
        [btnStop setTitle:@"Detener MP3" forState:UIControlStateNormal];
        [btnStop setBackgroundColor:[UIColor colorWithRed:0x31/255.0 green:0x33/255.0 blue:0x38/255.0 alpha:1.0]];
        [btnStop setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btnStop.layer.cornerRadius = 8;
        [btnStop addTarget:self action:@selector(detenerMP3) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:btnStop];
        
        y += 60;
        y = [self addSlider:@"Volumen MP3" y:y min:0.0 max:1.0 def:1.0 tag:6];

        self.scrollView.contentSize = CGSizeMake(frame.size.width, y + 50);
    }
    return self;
}

// Métodos de UI
- (CGFloat)addSwitch:(NSString *)titulo y:(CGFloat)y tag:(int)tag {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, y, self.bounds.size.width - 40, 50)];
    card.backgroundColor = [UIColor colorWithRed:0x31/255.0 green:0x33/255.0 blue:0x38/255.0 alpha:1.0];
    card.layer.cornerRadius = 10;
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, card.bounds.size.width - 80, 50)];
    lbl.text = titulo; lbl.textColor = [UIColor whiteColor]; [card addSubview:lbl];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.center = CGPointMake(card.bounds.size.width - 40, 25);
    sw.tag = tag;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw]; [self.scrollView addSubview:card];
    return y + 60;
}

- (CGFloat)addSlider:(NSString *)titulo y:(CGFloat)y min:(float)min max:(float)max def:(float)def tag:(int)tag {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, y, self.bounds.size.width - 40, 70)];
    card.backgroundColor = [UIColor colorWithRed:0x31/255.0 green:0x33/255.0 blue:0x38/255.0 alpha:1.0];
    card.layer.cornerRadius = 10;
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(15, 5, card.bounds.size.width - 30, 20)];
    lbl.text = titulo; lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont systemFontOfSize:14]; [card addSubview:lbl];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(15, 30, card.bounds.size.width - 30, 30)];
    slider.minimumValue = min; slider.maximumValue = max; slider.value = def; slider.tag = tag;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:slider]; [self.scrollView addSubview:card];
    return y + 80;
}

// Acciones
- (void)switchChanged:(UISwitch *)sender { gEfectosActivados = sender.isOn; }
- (void)sliderChanged:(UISlider *)sender {
    if (sender.tag == 2) gPitchAmount = sender.value;
    else if (sender.tag == 3) gBassGain = sender.value;
    else if (sender.tag == 4) gTrebleGain = sender.value;
    else if (sender.tag == 5) gReverbAmount = sender.value;
    else if (sender.tag == 6) gMp3Volume = sender.value;
}
- (void)abrirSelectorMP3 {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio]];
    picker.delegate = self;
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) CargarYReproducirMP3(urls.firstObject);
}
- (void)detenerMP3 { DetenerMP3(); }

- (void)cerrar {
    [UIView animateWithDuration:0.25 animations:^{
        self.transform = CGAffineTransformMakeTranslation(0, self.bounds.size.height);
    } completion:^(BOOL finished) { [self removeFromSuperview]; }];
}
@end

// --- BOTÓN FLOTANTE (Se mantiene igual que en tu código original) ---
@interface BotonFlotante : UIButton
@property (nonatomic, strong) MiPanelView *panel;
@end

@implementation BotonFlotante
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 150, 56, 56)];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0x58/255.0 green:0x65/255.0 blue:0xF2/255.0 alpha:1.0];
        self.layer.cornerRadius = 28;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.4;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        [self setTitle:@"✦" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:24];
        [self addTarget:self action:@selector(tocado) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(arrastrado:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)arrastrado:(UIPanGestureRecognizer *)gesture {
    UIView *superview = self.superview;
    if (!superview) return;
    CGPoint translation = [gesture translationInView:superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:superview];
}
- (void)tocado {
    UIWindow *window = self.window;
    if (!window) return;
    if (self.panel.superview) { [self.panel cerrar]; return; }
    CGFloat altoPanel = 420;
    self.panel = [[MiPanelView alloc] initWithFrame:CGRectMake(0, window.bounds.size.height, window.bounds.size.width, altoPanel)];
    [window addSubview:self.panel];
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.5 options:0 animations:^{
        self.panel.frame = CGRectMake(0, window.bounds.size.height - altoPanel, window.bounds.size.width, altoPanel);
    } completion:nil];
}
@end

// --- INYECCIÓN ---
static void AgregarBotonFlotante(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) {
                        if (w.isKeyWindow) { window = w; break; }
                    }
                }
            }
        }
        if (!window) window = [UIApplication sharedApplication].keyWindow;
        if (!window) return;
        for (UIView *v in window.subviews) {
            if ([v isKindOfClass:[BotonFlotante class]]) return;
        }
        BotonFlotante *boton = [[BotonFlotante alloc] init];
        [window addSubview:boton];
    });
}

__attribute__((constructor))
static void InicializarInterfaz(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AgregarBotonFlotante();
    });
}

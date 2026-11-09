//
// Interface.m
//

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <AVFoundation/AVFoundation.h>

// Importar variables de los otros archivos
extern float gGainDB;
extern float gPitchAmount;
extern BOOL gMuteMicOnPlay;
extern BOOL gSelfMonitor;
extern BOOL gIsMp3Playing;
extern int gSpooferMode;
void CargarYReproducirAudio(NSURL *url);
void DetenerAudio(void);

#pragma mark - Panel Rosa Transparente
@interface PanelRosa : UIView <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@end

@implementation PanelRosa

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Fondo Rosa Translúcido
        self.backgroundColor = [[UIColor colorWithRed:1.0 green:0.4 blue:0.7 alpha:0.85] colorWithAlphaComponent:0.85];
        self.layer.cornerRadius = 25;
        self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner | kCALayerMinXMaxYCorner;
        self.clipsToBounds = YES;
        
        // Efecto Blur (Vidrio esmerilado)
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        blurView.frame = self.bounds;
        blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self insertSubview:blurView atIndex:0];

        // Título
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, frame.size.width - 60, 30)];
        title.text = @"✨ Discord Tweaks";
        title.textColor = [UIColor whiteColor];
        title.font = [UIFont boldSystemFontOfSize:20];
        [self addSubview:title];

        // Botón Cerrar (solo oculta, no destruye)
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(frame.size.width - 45, 15, 30, 30);
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(ocultarPanel) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        // Scroll View
        self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 50, frame.size.width, frame.size.height - 50)];
        self.scrollView.showsVerticalScrollIndicator = NO;
        [self addSubview:self.scrollView];

        CGFloat y = 10;
        
        // 1. GAIN (100 dB)
        y = [self crearSlider:@"Gain (dB)" min:-20 max:100 def:0 tag:1 y:y];
        
        // 2. PITCH (Suave)
        y = [self crearSlider:@"Pitch (Tono)" min:0.5 max:2.0 def:1.0 tag:2 y:y];
        
        // 3. REPRODUCTOR
        y = [self crearSeccionReproductor:y];
        
        // 4. OPCIONES (Mute, Autoescucha)
        y = [self crearSwitch:@"Mutear mi voz al sonar MP3" tag:3 y:y];
        y = [self crearSwitch:@"Auto-Escucha (Self Monitor)" tag:4 y:y];
        
        // 5. SPOOFER
        y = [self crearSeccionSpoofer:y];
        
        self.scrollView.contentSize = CGSizeMake(frame.size.width, y + 40);
    }
    return self;
}

- (void)ocultarPanel {
    [UIView animateWithDuration:0.3 animations:^{
        self.transform = CGAffineTransformMakeTranslation(0, self.bounds.size.height);
    }];
}

// --- Constructores de UI ---
- (CGFloat)crearSlider:(NSString *)titulo min:(float)min max:(float)max def:(float)def tag:(int)tag y:(CGFloat)y {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(15, y, self.bounds.size.width - 30, 70)];
    card.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    card.layer.cornerRadius = 12;
    
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(15, 5, card.bounds.size.width - 30, 20)];
    lbl.text = titulo; lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont boldSystemFontOfSize:14];
    [card addSubview:lbl];
    
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(15, 30, card.bounds.size.width - 30, 30)];
    slider.minimumValue = min; slider.maximumValue = max; slider.value = def; slider.tag = tag;
    slider.minimumTrackTintColor = [UIColor whiteColor];
    slider.maximumTrackTintColor = [[UIColor blackColor] colorWithAlphaComponent:0.2];
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:slider];
    
    [self.scrollView addSubview:card];
    return y + 80;
}

- (CGFloat)crearSwitch:(NSString *)titulo tag:(int)tag y:(CGFloat)y {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(15, y, self.bounds.size.width - 30, 50)];
    card.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    card.layer.cornerRadius = 12;
    
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, card.bounds.size.width - 80, 50)];
    lbl.text = titulo; lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont systemFontOfSize:13];
    [card addSubview:lbl];
    
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.center = CGPointMake(card.bounds.size.width - 40, 25);
    sw.tag = tag;
    sw.onTintColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.5 alpha:1.0];
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw];
    
    [self.scrollView addSubview:card];
    return y + 60;
}

- (CGFloat)crearSeccionReproductor:(CGFloat)y {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(15, y, self.bounds.size.width - 30, 120)];
    card.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    card.layer.cornerRadius = 12;
    
    UIButton *btnLoad = [UIButton buttonWithType:UIButtonTypeSystem];
    btnLoad.frame = CGRectMake(10, 10, (card.bounds.size.width - 30)/2, 40);
    [btnLoad setTitle:@"Cargar Audio" forState:UIControlStateNormal];
    [btnLoad setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btnLoad.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
    btnLoad.layer.cornerRadius = 8;
    [btnLoad addTarget:self action:@selector(abrirSelector) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:btnLoad];
    
    UIButton *btnPlay = [UIButton buttonWithType:UIButtonTypeSystem];
    btnPlay.frame = CGRectMake(20 + (card.bounds.size.width - 30)/2, 10, (card.bounds.size.width - 30)/2, 40);
    [btnPlay setTitle:@"▶ Play" forState:UIControlStateNormal];
    [btnPlay setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btnPlay.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.5];
    btnPlay.layer.cornerRadius = 8;
    [btnPlay addTarget:self action:@selector(playAudio) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:btnPlay];
    
    UIButton *btnStop = [UIButton buttonWithType:UIButtonTypeSystem];
    btnStop.frame = CGRectMake(10, 60, card.bounds.size.width - 20, 40);
    [btnStop setTitle:@"⏹ Stop" forState:UIControlStateNormal];
    [btnStop setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btnStop.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.5];
    btnStop.layer.cornerRadius = 8;
    [btnStop addTarget:self action:@selector(stopAudio) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:btnStop];
    
    [self.scrollView addSubview:card];
    return y + 130;
}

- (CGFloat)crearSeccionSpoofer:(CGFloat)y {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(15, y, self.bounds.size.width - 30, 120)];
    card.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    card.layer.cornerRadius = 12;
    
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(15, 5, card.bounds.size.width - 30, 20)];
    lbl.text = @"Plataforma Spoofer"; lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont boldSystemFontOfSize:14];
    [card addSubview:lbl];
    
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Phone", @"PC", @"VR", @"Android"]];
    seg.frame = CGRectMake(10, 30, card.bounds.size.width - 20, 32);
    seg.selectedSegmentIndex = 0;
    seg.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3];
    [seg addTarget:self action:@selector(spooferChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:seg];
    
    UILabel *desc = [[UILabel alloc] initWithFrame:CGRectMake(15, 70, card.bounds.size.width - 30, 40)];
    desc.text = @"Selecciona la plataforma que Discord verá.";
    desc.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    desc.font = [UIFont systemFontOfSize:11];
    desc.numberOfLines = 2;
    [card addSubview:desc];
    
    [self.scrollView addSubview:card];
    return y + 130;
}

// --- Acciones ---
- (void)sliderChanged:(UISlider *)sender {
    if (sender.tag == 1) gGainDB = sender.value;
    if (sender.tag == 2) gPitchAmount = sender.value;
}
- (void)switchChanged:(UISwitch *)sender {
    if (sender.tag == 3) gMuteMicOnPlay = sender.isOn;
    if (sender.tag == 4) gSelfMonitor = sender.isOn;
}
- (void)spooferChanged:(UISegmentedControl *)sender {
    gSpooferMode = (int)sender.selectedSegmentIndex;
}
- (void)abrirSelector {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio]];
    picker.delegate = self;
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) CargarYReproducirAudio(urls.firstObject);
}
- (void)playAudio { 
    // Si ya está cargado, simplemente dale play de nuevo
    // (En este código simplificado, usar CargarYReproducirAudio lo vuelve a iniciar)
}
- (void)stopAudio { DetenerAudio(); }
@end

#pragma mark - Botón Flotante (Bolita)
@interface Bolita : UIButton
@property (nonatomic, strong) PanelRosa *panel;
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
        
        // Arrastrar bolita
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(arrastrar:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)arrastrar:(UIPanGestureRecognizer *)gesture {
    UIView *superview = self.superview;
    if (!superview) return;
    CGPoint translation = [gesture translationInView:superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:superview];
}

- (void)tocado {
    UIWindow *window = self.window;
    if (!window) return;
    
    if (!self.panel) {
        CGFloat alto = 500;
        self.panel = [[PanelRosa alloc] initWithFrame:CGRectMake(20, window.bounds.size.height, window.bounds.size.width - 40, alto)];
        self.panel.center = CGPointMake(window.center.x, window.bounds.size.height + alto/2);
        [window addSubview:self.panel];
        
        // Hacer el panel arrastrable
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(arrastrarPanel:)];
        [self.panel addGestureRecognizer:pan];
    }
    
    // Animación para abrir/cerrar
    if (self.panel.transform.ty == 0) {
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            self.panel.center = CGPointMake(window.center.x, window.center.y);
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.3 animations:^{
            self.panel.center = CGPointMake(window.center.x, window.bounds.size.height + 250);
        }];
    }
}

- (void)arrastrarPanel:(UIPanGestureRecognizer *)gesture {
    UIView *superview = self.panel.superview;
    if (!superview) return;
    CGPoint translation = [gesture translationInView:superview];
    self.panel.center = CGPointMake(self.panel.center.x + translation.x, self.panel.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:superview];
}
@end

#pragma mark - Inyección
__attribute__((constructor))
static void Iniciar(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) {
            if (@available(iOS 13.0, *)) {
                for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive) {
                        window = scene.windows.firstObject;
                        break;
                    }
                }
            }
        }
        if (window) {
            Bolita *b = [[Bolita alloc] init];
            [window addSubview:b];
        }
    });
}

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

extern float gGainDB, gPitchAmount;
extern BOOL gMuteMic;
void CargarMP3(NSURL *url);
void PlayMP3(void);
void StopMP3(void);

@interface PanelRosa : UIView <UIDocumentPickerDelegate>
@end

@implementation PanelRosa

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor colorWithRed:1.0 green:0.4 blue:0.7 alpha:0.85] colorWithAlphaComponent:0.85];
        self.layer.cornerRadius = 20;
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

        CGFloat y = 60;
        y = [self addSlider:@"Gain (dB)" min:-20 max:100 def:0 tag:1 y:y];
        y = [self addSlider:@"Pitch (Tono)" min:0.5 max:2.0 def:1.0 tag:2 y:y];
        
        // Botones MP3
        UIButton *btnLoad = [UIButton buttonWithType:UIButtonTypeSystem];
        btnLoad.frame = CGRectMake(20, y, 100, 40); [btnLoad setTitle:@"Cargar MP3" forState:UIControlStateNormal];
        [btnLoad setBackgroundColor:[UIColor darkGrayColor]]; [btnLoad setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [btnLoad addTarget:self action:@selector(abrirPicker) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btnLoad];
        
        UIButton *btnPlay = [UIButton buttonWithType:UIButtonTypeSystem];
        btnPlay.frame = CGRectMake(130, y, 70, 40); [btnPlay setTitle:@"Play" forState:UIControlStateNormal];
        [btnPlay setBackgroundColor:[UIColor greenColor]]; [btnPlay setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [btnPlay addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btnPlay];

        UIButton *btnStop = [UIButton buttonWithType:UIButtonTypeSystem];
        btnStop.frame = CGRectMake(210, y, 70, 40); [btnStop setTitle:@"Stop" forState:UIControlStateNormal];
        [btnStop setBackgroundColor:[UIColor redColor]]; [btnStop setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [btnStop addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btnStop];
        
        y += 60;
        y = [self addSwitch:@"Mutear mi voz al sonar MP3" tag:3 y:y];
    }
    return self;
}

- (CGFloat)addSlider:(NSString *)titulo min:(float)min max:(float)max def:(float)def tag:(int)tag y:(CGFloat)y {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, y, self.bounds.size.width - 40, 60)];
    card.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2]; card.layer.cornerRadius = 10;
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 200, 20)]; lbl.text = titulo; lbl.textColor = [UIColor whiteColor]; [card addSubview:lbl];
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(10, 25, card.bounds.size.width - 20, 30)];
    s.minimumValue = min; s.maximumValue = max; s.value = def; s.tag = tag;
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:s]; [self addSubview:card]; return y + 70;
}

- (CGFloat)addSwitch:(NSString *)titulo tag:(int)tag y:(CGFloat)y {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, y, self.bounds.size.width - 40, 50)];
    card.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2]; card.layer.cornerRadius = 10;
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, card.bounds.size.width - 60, 50)]; lbl.text = titulo; lbl.textColor = [UIColor whiteColor]; [card addSubview:lbl];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero]; sw.center = CGPointMake(card.bounds.size.width - 35, 25); sw.tag = tag;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw]; [self addSubview:card]; return y + 60;
}

- (void)sliderChanged:(UISlider *)s { if (s.tag == 1) gGainDB = s.value; if (s.tag == 2) gPitchAmount = s.value; }
- (void)switchChanged:(UISwitch *)s { if (s.tag == 3) gMuteMic = s.isOn; }
- (void)abrirPicker { UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio]]; p.delegate = self; [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:p animated:YES completion:nil]; }
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)u { if (u.count) CargarMP3(u.firstObject); }
- (void)play { PlayMP3(); }
- (void)stop { StopMP3(); }
- (void)ocultar { [UIView animateWithDuration:0.3 animations:^{ self.transform = CGAffineTransformMakeTranslation(0, self.bounds.size.height); }]; }
@end

// (El código de la bolita y la inyección se mantiene igual al anterior, pégalo aquí abajo)

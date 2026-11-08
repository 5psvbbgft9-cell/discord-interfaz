//
// Interface.m
// Dylib de interfaz flotante estilo Discord
//
// Se inyecta en Discord (vía resign con ESign). Al cargar, agrega
// un botón flotante arrastrable que abre un panel con toggles.
//
// Compilar con el workflow de GitHub Actions incluido (build.yml).
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - Colores (paleta Discord)

static UIColor *DColorBackground(void) {
    return [UIColor colorWithRed:0x2B/255.0 green:0x2D/255.0 blue:0x31/255.0 alpha:1.0];
}
static UIColor *DColorCard(void) {
    return [UIColor colorWithRed:0x31/255.0 green:0x33/255.0 blue:0x38/255.0 alpha:1.0];
}
static UIColor *DColorAccent(void) {
    return [UIColor colorWithRed:0x58/255.0 green:0x65/255.0 blue:0xF2/255.0 alpha:1.0];
}
static UIColor *DColorText(void) {
    return [UIColor whiteColor];
}
static UIColor *DColorSubtext(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.6];
}

#pragma mark - Panel

@interface MiPanelView : UIView
@end

@implementation MiPanelView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = DColorBackground();
        self.layer.cornerRadius = 20;
        self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        self.clipsToBounds = YES;

        // Barra superior (handle)
        UIView *handle = [[UIView alloc] initWithFrame:CGRectMake((frame.size.width - 40) / 2, 10, 40, 5)];
        handle.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
        handle.layer.cornerRadius = 2.5;
        [self addSubview:handle];

        // Título
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 28, frame.size.width - 80, 30)];
        title.text = @"Mi Panel";
        title.textColor = DColorText();
        title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
        [self addSubview:title];

        // Botón cerrar
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(frame.size.width - 52, 24, 36, 36);
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        [closeBtn setTitleColor:DColorSubtext() forState:UIControlStateNormal];
        closeBtn.backgroundColor = DColorCard();
        closeBtn.layer.cornerRadius = 18;
        [closeBtn addTarget:self action:@selector(cerrar) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        // Toggles de ejemplo (cámbialos por tus funciones reales)
        NSArray *opciones = @[@"Opción 1", @"Opción 2", @"Opción 3"];
        CGFloat y = 80;
        for (NSString *nombre in opciones) {
            [self agregarFilaConTitulo:nombre y:y ancho:frame.size.width];
            y += 60;
        }
    }
    return self;
}

- (void)agregarFilaConTitulo:(NSString *)nombre y:(CGFloat)y ancho:(CGFloat)ancho {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, y, ancho - 40, 48)];
    card.backgroundColor = DColorCard();
    card.layer.cornerRadius = 12;
    [self addSubview:card];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, ancho - 110, 48)];
    label.text = nombre;
    label.textColor = DColorText();
    label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [card addSubview:label];

    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    toggle.center = CGPointMake(card.bounds.size.width - 35, 24);
    toggle.onTintColor = DColorAccent();
    [card addSubview:toggle];
}

- (void)cerrar {
    [UIView animateWithDuration:0.25 animations:^{
        self.transform = CGAffineTransformMakeTranslation(0, self.bounds.size.height);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        self.transform = CGAffineTransformIdentity;
    }];
}

@end

#pragma mark - Botón flotante

@interface BotonFlotante : UIButton
@property (nonatomic, strong) MiPanelView *panel;
@end

@implementation BotonFlotante

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 150, 56, 56)];
    if (self) {
        self.backgroundColor = DColorAccent();
        self.layer.cornerRadius = 28;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.4;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowRadius = 8;

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

    if (gesture.state == UIGestureRecognizerStateEnded) {
        // Pegar al borde más cercano (izquierda o derecha)
        CGFloat targetX = (self.center.x < superview.bounds.size.width / 2) ? 36 : superview.bounds.size.width - 36;
        [UIView animateWithDuration:0.3 animations:^{
            self.center = CGPointMake(targetX, self.center.y);
        }];
    }
}

- (void)tocado {
    UIWindow *window = self.window;
    if (!window) return;

    if (self.panel.superview) {
        [self.panel cerrar];
        return;
    }

    CGFloat altoPanel = 320;
    self.panel = [[MiPanelView alloc] initWithFrame:CGRectMake(0, window.bounds.size.height, window.bounds.size.width, altoPanel)];
    [window addSubview:self.panel];

    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.5 options:0 animations:^{
        self.panel.frame = CGRectMake(0, window.bounds.size.height - altoPanel, window.bounds.size.width, altoPanel);
    } completion:nil];
}

@end

#pragma mark - Inyección al iniciar la app

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
        if (!window) {
            window = [UIApplication sharedApplication].keyWindow;
        }
        if (!window) return;

        // Evitar agregarlo dos veces
        for (UIView *v in window.subviews) {
            if ([v isKindOfClass:[BotonFlotante class]]) return;
        }

        BotonFlotante *boton = [[BotonFlotante alloc] init];
        [window addSubview:boton];
    });
}

__attribute__((constructor))
static void InicializarInterfaz(void) {
    // Espera un poco a que la app termine de cargar su UI inicial
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AgregarBotonFlotante();
    });
}

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

@implementation AVAudioSession (QualityFix)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        
        // Hookear la configuración de la categoría
        Method origSetCategory = class_getInstanceMethod(class, @selector(setCategory:mode:options:error:));
        Method swizSetCategory = class_getInstanceMethod(class, @selector(spoof_setCategory:mode:options:error:));
        method_exchangeImplementations(origSetCategory, swizSetCategory);
        
        // Hookear el modo directamente
        Method origSetMode = class_getInstanceMethod(class, @selector(setMode:error:));
        Method swizSetMode = class_getInstanceMethod(class, @selector(spoof_setMode:error:));
        method_exchangeImplementations(origSetMode, swizSetMode);
    });
}

- (BOOL)spoof_setCategory:(AVAudioSessionCategory)category mode:(AVAudioSessionMode)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    // Forzamos el modo Measurement (Audio Crudo de estudio) y quitamos el MixWithOthers
    AVAudioSessionMode cleanMode = AVAudioSessionModeMeasurement;
    AVAudioSessionCategoryOptions cleanOptions = options & ~AVAudioSessionCategoryOptionMixWithOthers;
    
    return [self spoof_setCategory:category mode:cleanMode options:cleanOptions error:outError];
}

- (BOOL)spoof_setMode:(AVAudioSessionMode)mode error:(NSError **)outError {
    // Si Discord intenta poner VoiceChat, lo cambiamos a Measurement
    if (mode == AVAudioSessionModeVoiceChat || mode == AVAudioSessionModeVideoChat) {
        return [self spoof_setMode:AVAudioSessionModeMeasurement error:outError];
    }
    return [self spoof_setMode:mode error:outError];
}

@end

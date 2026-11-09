#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

@implementation AVAudioSession (QualityFix)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        
        // Interceptar la categoría de audio
        Method origSetCategory = class_getInstanceMethod(class, @selector(setCategory:mode:options:error:));
        Method swizSetCategory = class_getInstanceMethod(class, @selector(spoof_setCategory:mode:options:error:));
        method_exchangeImplementations(origSetCategory, swizSetCategory);
        
        // Interceptar el modo de audio
        Method origSetMode = class_getInstanceMethod(class, @selector(setMode:error:));
        Method swizSetMode = class_getInstanceMethod(class, @selector(spoof_setMode:error:));
        method_exchangeImplementations(origSetMode, swizSetMode);
    });
}

- (BOOL)spoof_setCategory:(AVAudioSessionCategory)category mode:(AVAudioSessionMode)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    // Si Discord intenta usar el modo de Chat de voz
    if (mode == AVAudioSessionModeVoiceChat || mode == AVAudioSessionModeVideoChat) {
        // Usamos opciones seguras para no romper el enrutamiento (Bluetooth y Altavoz)
        AVAudioSessionCategoryOptions safeOptions = options | AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionDefaultToSpeaker;
        
        // Forzamos el modo Measurement (Voz Cruda/Limpia)
        return [self spoof_setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeMeasurement options:safeOptions error:outError];
    }
    
    // Si es otra cosa, lo dejamos pasar normal
    return [self spoof_setCategory:category mode:mode options:options error:outError];
}

- (BOOL)spoof_setMode:(AVAudioSessionMode)mode error:(NSError **)outError {
    // Si intentan forzar el modo VoiceChat por separado, lo cambiamos a Measurement
    if (mode == AVAudioSessionModeVoiceChat || mode == AVAudioSessionModeVideoChat) {
        return [self spoof_setMode:AVAudioSessionModeMeasurement error:outError];
    }
    return [self spoof_setMode:mode error:outError];
}

@end

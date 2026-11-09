#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

@implementation AVAudioSession (QualityFix)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        Method originalMethod = class_getInstanceMethod(class, @selector(setCategory:mode:options:error:));
        Method swizzledMethod = class_getInstanceMethod(class, @selector(spoof_setCategory:mode:options:error:));
        method_exchangeImplementations(originalMethod, swizzledMethod);
    });
}

- (BOOL)spoof_setCategory:(AVAudioSessionCategory)category mode:(AVAudioSessionMode)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    AVAudioSessionMode cleanMode = mode;
    // Forzar audio limpio en llamadas
    if (mode == AVAudioSessionModeVoiceChat || mode == AVAudioSessionModeVideoChat) {
        cleanMode = AVAudioSessionModeMeasurement; 
    }
    return [self spoof_setCategory:category mode:cleanMode options:options error:outError];
}

@end

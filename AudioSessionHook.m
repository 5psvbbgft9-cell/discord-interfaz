#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

@implementation AVAudioSession (QualityFix)
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        Method origSetCategory = class_getInstanceMethod(class, @selector(setCategory:mode:options:error:));
        Method swizSetCategory = class_getInstanceMethod(class, @selector(spoof_setCategory:mode:options:error:));
        method_exchangeImplementations(origSetCategory, swizSetCategory);
        
        Method origSetMode = class_getInstanceMethod(class, @selector(setMode:error:));
        Method swizSetMode = class_getInstanceMethod(class, @selector(spoof_setMode:error:));
        method_exchangeImplementations(origSetMode, swizSetMode);
        
        // Forzar modo limpio cada 1 segundo por si Discord lo cambia
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
                AVAudioSession *session = [AVAudioSession sharedInstance];
                if (session.mode != AVAudioSessionModeMeasurement) {
                    [session spoof_setMode:AVAudioSessionModeMeasurement error:nil];
                }
            }];
        });
    });
}

- (BOOL)spoof_setCategory:(AVAudioSessionCategory)category mode:(AVAudioSessionMode)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return [self spoof_setCategory:category mode:AVAudioSessionModeMeasurement options:options error:outError];
}

- (BOOL)spoof_setMode:(AVAudioSessionMode)mode error:(NSError **)outError {
    return [self spoof_setMode:AVAudioSessionModeMeasurement error:outError];
}
@end

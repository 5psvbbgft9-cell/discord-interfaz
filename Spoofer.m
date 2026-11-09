#import "Comun.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

int gSpooferMode = 0; // 0 = iPhone, 1 = PC, 2 = VR, 3 = Android

@implementation UIDevice (Spoofer)
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        
        // Hookear "model"
        SEL originalSelector = @selector(model);
        SEL swizzledSelector = @selector(spoof_model);
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        method_exchangeImplementations(originalMethod, swizzledMethod);
        
        // Hookear "systemName"
        SEL originalSys = @selector(systemName);
        SEL swizzledSys = @selector(spoof_systemName);
        Method originalSysM = class_getInstanceMethod(class, originalSys);
        Method swizzledSysM = class_getInstanceMethod(class, swizzledSys);
        method_exchangeImplementations(originalSysM, swizzledSysM);
    });
}

- (NSString *)spoof_model {
    if (gSpooferMode == 1) return @"PC";
    if (gSpooferMode == 2) return @"VR";
    if (gSpooferMode == 3) return @"Android";
    return [self spoof_model]; // iPhone
}

- (NSString *)spoof_systemName {
    if (gSpooferMode == 1) return @"Windows";
    if (gSpooferMode == 2) return @"Oculus";
    if (gSpooferMode == 3) return @"Android";
    return [self spoof_systemName];
}
@end

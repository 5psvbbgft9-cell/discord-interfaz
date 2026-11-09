#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "Comun.h"

@implementation UIDevice (Spoofer)
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        Method originalModel = class_getInstanceMethod(class, @selector(model));
        Method swizzledModel = class_getInstanceMethod(class, @selector(spoof_model));
        method_exchangeImplementations(originalModel, swizzledModel);
        
        Method originalSys = class_getInstanceMethod(class, @selector(systemName));
        Method swizzledSys = class_getInstanceMethod(class, @selector(spoof_systemName));
        method_exchangeImplementations(originalSys, swizzledSys);
    });
}
- (NSString *)spoof_model {
    if (gSpooferMode == 1) return @"PC";
    if (gSpooferMode == 2) return @"VR";
    if (gSpooferMode == 3) return @"Android";
    return [self spoof_model];
}
- (NSString *)spoof_systemName {
    if (gSpooferMode == 1) return @"Windows";
    if (gSpooferMode == 2) return @"Oculus";
    if (gSpooferMode == 3) return @"Android";
    return [self spoof_systemName];
}
@end

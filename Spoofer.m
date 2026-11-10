#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "Comun.h"

@implementation UIDevice (Spoofer)
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        method_exchangeImplementations(class_getInstanceMethod(class, @selector(model)), class_getInstanceMethod(class, @selector(spoof_model)));
        method_exchangeImplementations(class_getInstanceMethod(class, @selector(systemName)), class_getInstanceMethod(class, @selector(spoof_systemName)));
    });
}
- (NSString *)spoof_model {
    if (gSpooferMode == 1) return @"Desktop";
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

@implementation NSProcessInfo (Spoofer)
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        method_exchangeImplementations(class_getInstanceMethod(class, @selector(operatingSystemVersionString)), class_getInstanceMethod(class, @selector(spoof_operatingSystemVersionString)));
    });
}
- (NSString *)spoof_operatingSystemVersionString {
    if (gSpooferMode == 1) return @"Version 10.0.19045 (Build 19045)";
    if (gSpooferMode == 2) return @"Version 1.0 (Oculus)";
    if (gSpooferMode == 3) return @"Version 13 (Android)";
    return [self spoof_operatingSystemVersionString];
}
@end

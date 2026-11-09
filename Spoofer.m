#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <sys/utsname.h>
#import "Comun.h"

// 1. Interceptar uname() (Usado por React Native para leer el hardware)
static int (*orig_uname)(struct utsname *) = uname;
int hook_uname(struct utsname *buf) {
    int res = orig_uname(buf);
    if (res == 0 && buf) {
        if (gSpooferMode == 1) strcpy(buf->machine, "x86_64");      // PC
        else if (gSpooferMode == 2) strcpy(buf->machine, "Oculus Quest 2"); // VR
        else if (gSpooferMode == 3) strcpy(buf->machine, "SM-G998B");       // Android
    }
    return res;
}

#define DYLD_INTERPOSE(_replacement, _replacee) \
__attribute__((used)) static struct { \
    const void *replacement; \
    const void *replacee; \
} _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

DYLD_INTERPOSE(hook_uname, uname)

// 2. Interceptar UIDevice
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

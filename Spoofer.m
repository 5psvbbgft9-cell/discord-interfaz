#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import "Comun.h"

// 1. Interceptar sysctl (Mucho más seguro)
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t) = NULL;

static int my_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctlbyname) {
        orig_sysctlbyname = dlsym(RTLD_DEFAULT, "sysctlbyname");
    }
    
    int res = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    
    if (res == 0 && oldp && strcmp(name, "hw.machine") == 0) {
        const char *fakeMachine = NULL;
        if (gSpooferMode == 1) fakeMachine = "MacBookPro18,1"; // PC (MacOS)
        else if (gSpooferMode == 2) fakeMachine = "Oculus Quest"; // VR
        else if (gSpooferMode == 3) fakeMachine = "SM-G998B"; // Android
        
        if (fakeMachine) {
            size_t len = strlen(fakeMachine) + 1;
            // Solo copiamos si hay suficiente espacio para evitar crash
            if (oldlenp && *oldlenp >= len) {
                memcpy(oldp, fakeMachine, len);
                *oldlenp = len;
            }
        }
    }
    return res;
}

#define DYLD_INTERPOSE(_replacement, _replacee) \
__attribute__((used)) static struct { \
    const void *replacement; \
    const void *replacee; \
} _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

DYLD_INTERPOSE(my_sysctlbyname, sysctlbyname)

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
    if (gSpooferMode == 1) return @"MacOS";
    if (gSpooferMode == 2) return @"Oculus";
    if (gSpooferMode == 3) return @"Android";
    return [self spoof_systemName];
}
@end

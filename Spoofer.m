#import "Comun.h"
#import <os/log.h>
#import <objc/runtime.h>

int gSpooferMode = 0; // 0 = iPhone, 1 = PC, 2 = VR, 3 = Android

// Hook para interceptar los datos de conexión de Discord
// (Esto es un ejemplo conceptual, Discord usa su propia clase para el WebSocket)
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    // Si la petición es hacia el gateway de Discord
    if ([request.URL.absoluteString containsString:@"gateway.discord.gg"]) {
        os_log(OS_LOG_DEFAULT, "[Spoofer] Interceptada petición al Gateway de Discord");
        // Aquí se modificaría el body de la petición para cambiar la plataforma
    }
    return %orig;
}
%end

__attribute__((constructor))
static void initSpoofer(void) {
    os_log(OS_LOG_DEFAULT, "[Spoofer] Módulo cargado. Modo actual: %d", gSpooferMode);
}

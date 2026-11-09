#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// Declaración de variables globales (la palabra "extern" significa "existen en otro archivo")
extern float gGainDB;
extern float gPitchAmount;
extern BOOL gMuteMicOnPlay;
extern BOOL gSelfMonitor;

// Declaración de funciones de audio
void gCargarYReproducirAudio(NSURL *url);
void gDetenerAudio(void);

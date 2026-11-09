#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// Variables de Audio
extern float gGainDB;
extern float gPitchAmount;
extern BOOL gMuteMicOnPlay;
extern BOOL gSelfMonitor;

// Variables del Spoofer (0=iOS, 1=PC, 2=VR, 3=Android)
extern int gSpooferMode;

// Funciones de Audio
void gCargarYReproducirAudio(NSURL *url);
void gDetenerAudio(void);

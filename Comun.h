//
//  Comun.h
//
#import <Foundation/Foundation.h>

// Variables de Audio
extern float gGainDB;
extern float gPitchAmount;
extern BOOL gMuteMicOnPlay;
extern BOOL gSelfMonitor;
extern BOOL gIsMp3Playing;

// Variables del Spoofer
extern int gSpooferMode;

// Funciones del Reproductor
void CargarMP3(NSURL *url);
void PlayMP3(void);
void StopMP3(void);

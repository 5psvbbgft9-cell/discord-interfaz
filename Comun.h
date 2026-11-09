#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// Variables de Audio
extern float gGainDB;
extern float gPitchAmount;
extern BOOL gMuteMicOnPlay;
extern BOOL gSelfMonitor;

// Reproductor MP3 (Compartido entre Interface y AudioEngine)
extern AVAudioPlayer *gMP3Player;

// Variables del Spoofer
extern int gSpooferMode;

// Funciones de Audio
void gCargarYReproducirAudio(NSURL *url);
void gDetenerAudio(void);

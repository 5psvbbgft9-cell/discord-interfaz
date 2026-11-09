#import <Foundation/Foundation.h>

extern float gGainDB;
extern float gPitchAmount;
extern BOOL gMuteMicOnPlay;
extern BOOL gSelfMonitor;
extern BOOL gIsMp3Playing;
extern int gSpooferMode;

void CargarMP3(NSURL *url);
void PlayMP3(void);
void StopMP3(void);

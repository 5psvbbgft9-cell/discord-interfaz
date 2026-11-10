#import <Foundation/Foundation.h>

extern float gGainDB;
extern float gPitchSemitones;
extern BOOL gMuteMicOnPlay;
extern BOOL gIsMp3Playing;
extern BOOL gStreamMode;
extern int gSpooferMode;

void CargarMP3(NSURL *url);
void PlayMP3(void);
void StopMP3(void);

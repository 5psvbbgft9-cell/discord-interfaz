#import <Foundation/Foundation.h>

extern float gGainDB;
extern float gPitchSemitones; // Ahora usamos semitonos (-12 a +12)
extern BOOL gMuteMicOnPlay;
extern BOOL gIsMp3Playing;
extern int gSpooferMode;

void CargarMP3(NSURL *url);
void PlayMP3(void);
void StopMP3(void);

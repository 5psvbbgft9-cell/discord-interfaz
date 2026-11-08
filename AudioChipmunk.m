//
// AudioChipmunk.m
// Interposición de AudioUnitRender para aplicar efecto de voz "ardilla"
// al micrófono en tiempo real.
//
// IMPORTANTE: esto es experimental. No hay garantía de que Discord use
// RemoteIO directamente (podría usar su propio motor de audio vía
// WebRTC con otra ruta interna). Incluye logging para depurar eso
// primero antes de confiar en que el efecto se aplica.
//

#include <AudioToolbox/AudioToolbox.h>
#include <os/log.h>
#import <Foundation/Foundation.h>

#pragma mark - Log a archivo (legible desde la app Archivos del iPhone)

static void LogAArchivo(NSString *mensaje) {
    static dispatch_once_t onceToken;
    static NSString *rutaLog = nil;
    dispatch_once(&onceToken, ^{
        NSArray *rutas = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docs = rutas.firstObject;
        rutaLog = [docs stringByAppendingPathComponent:@"chipmunk_log.txt"];
        // Limpia el log anterior al iniciar
        [@"" writeToFile:rutaLog atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });

    NSString *linea = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], mensaje];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:rutaLog];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[linea dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

#pragma mark - Macro de interposición (dyld)

#define DYLD_INTERPOSE(_replacement, _replacee) \
__attribute__((used)) static struct { \
    const void *replacement; \
    const void *replacee; \
} _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

#pragma mark - Pitch shift simple (granular, time-domain)

// Buffer circular de trabajo para el pitch shifter.
// pitchFactor > 1.0 = más agudo (ardilla). Prueba entre 1.3 y 1.8.
static const float kPitchFactor = 1.5f;
#define RING_SIZE 8192

static float ringBuffer[RING_SIZE];
static int writeIndex = 0;
static float readIndex = 0.0f;

static void AplicarPitchShift(SInt16 *samples, UInt32 numFrames) {
    for (UInt32 i = 0; i < numFrames; i++) {
        // Escribir sample actual en el buffer circular
        ringBuffer[writeIndex] = (float)samples[i];
        writeIndex = (writeIndex + 1) % RING_SIZE;

        // Leer con interpolación lineal a una posición "adelantada"
        // según el factor de pitch (esto es lo que sube el tono)
        int idx0 = (int)readIndex;
        int idx1 = (idx0 + 1) % RING_SIZE;
        float frac = readIndex - idx0;
        float sample = ringBuffer[idx0 % RING_SIZE] * (1.0f - frac) + ringBuffer[idx1] * frac;

        samples[i] = (SInt16)sample;

        readIndex += kPitchFactor;
        if (readIndex >= RING_SIZE) readIndex -= RING_SIZE;

        // Evitar que la lectura se acerque demasiado a la escritura
        float distancia = writeIndex - readIndex;
        if (distancia < 0) distancia += RING_SIZE;
        if (distancia < 256) {
            readIndex -= 256; // salto para no "alcanzar" al escritor
            if (readIndex < 0) readIndex += RING_SIZE;
        }
    }
}

#pragma mark - Interposición de AudioUnitRender

static OSStatus (*orig_AudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *,
                                         const AudioTimeStamp *, UInt32, UInt32,
                                         AudioBufferList *) = AudioUnitRender;

static OSStatus MyAudioUnitRender(AudioUnit inUnit,
                                   AudioUnitRenderActionFlags *ioActionFlags,
                                   const AudioTimeStamp *inTimeStamp,
                                   UInt32 inOutputBusNumber,
                                   UInt32 inNumberFrames,
                                   AudioBufferList *ioData) {

    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp,
                                            inOutputBusNumber, inNumberFrames, ioData);

    // LOG de depuración: esto te dice si realmente se está llamando
    // y con qué bus (1 = input/mic en RemoteIO, normalmente).
    // Solo loguea 1 de cada 50 llamadas para no saturar el archivo.
    static int contador = 0;
    if (contador++ % 50 == 0) {
        LogAArchivo([NSString stringWithFormat:@"AudioUnitRender bus=%u frames=%u status=%d",
                     (unsigned)inOutputBusNumber, (unsigned)inNumberFrames, (int)status]);
    }

    if (status == noErr && inOutputBusNumber == 1 && ioData != NULL) {
        for (UInt32 i = 0; i < ioData->mNumberBuffers; i++) {
            SInt16 *samples = (SInt16 *)ioData->mBuffers[i].mData;
            UInt32 n = ioData->mBuffers[i].mDataByteSize / sizeof(SInt16);
            if (samples != NULL && n > 0) {
                AplicarPitchShift(samples, n);
            }
        }
    }

    return status;
}

DYLD_INTERPOSE(MyAudioUnitRender, AudioUnitRender)

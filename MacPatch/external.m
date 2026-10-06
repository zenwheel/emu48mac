//
//  external.m
//  emu48
//
//  Based on external.c
//
//  Created by Da-Woon Jung on 2009-08-22.
//  Copyright 2009 dwj. All rights reserved.
//

#import "external.h"
#import "EMU48.H"
#import "OPS.H"
#if TARGET_OS_IPHONE
#import <AudioToolbox/AudioToolbox.h>
#endif
#import "CalcBackend.h"

//| 38G  | 39G  | 40G  | 48SX | 48GX | 49G  | Name
//#F0E4F #80F0F #80F0F #706D2 #80850 #80F0F =SFLAG53_56

// memory address for flags -53 to -56
// CdB for HP: add apples beep management
#define SFLAG53_56	(  (cCurrentRomType=='6')								\
	                 ? 0xE0E4F												\
					 : (  (cCurrentRomType=='A')							\
					    ? 0xF0E4F											\
					    : (  (cCurrentRomType!='E' && cCurrentRomType!='X' && cCurrentRomType!='P' && cCurrentRomType!='2' && cCurrentRomType!='Q')	\
					       ? (  (cCurrentRomType=='S')						\
					          ? 0x706D2										\
						      : 0x80850										\
						     )												\
						   : 0x80F0F										\
					      )													\
					   )													\
					)


static __inline VOID BeepWave(DWORD dwFrequency,DWORD dwDuration)
{
    [[CalcBackend sharedBackend] playToneWithFrequency:dwFrequency duration:dwDuration];
}

static VOID Beeper(DWORD freq,DWORD dur)
{
#if !TARGET_OS_IPHONE
	if (1 == [[NSUserDefaults standardUserDefaults] integerForKey: @"WaveBeep"])
#endif
	{
		BeepWave(freq,dur);					// wave output over sound card
	}
#if !TARGET_OS_IPHONE
    else
    {
        NSBeep();
    }
#endif
}


VOID External(CHIPSET* w)					// Beep patch
{
	BYTE  fbeep;
	DWORD freq,dur;

	freq = Npack(w->D,5);					// frequency in Hz
	dur = Npack(w->C,5);					// duration in ms
	Nread(&fbeep,SFLAG53_56,1);				// fetch system flags -53 to -56

	w->carry = TRUE;						// setting of no beep
	if (!(fbeep & 0x8) && freq)				// bit -56 clear and frequency > 0 Hz
	{
		if (freq > 4400) freq = 4400;		// high limit of HP (SX)

		Beeper(freq,dur);					// beeping

		// estimate cpu cycles for beeping time (2MHz / 4MHz)
		w->cycles += dur * ((cCurrentRomType=='S') ? 2000 : 4000);           

		// original routine return with...
		w->P = 0;							// P=0
		w->intk = TRUE;						// INTON
		w->carry = FALSE;					// RTNCC
	}
	w->pc = rstkpop();
	return;
}

VOID RCKBp(CHIPSET* w)						// ROM Check Beep patch
{
	DWORD dw2F,dwCpuFreq;
	DWORD freq,dur;
	BYTE f,d;

	f = w->C[1];							// f = freq ctl
	d = w->C[0];							// d = duration ctl
	
	if (cCurrentRomType == 'S')				// Clarke chip with 48S ROM
	{	
		// CPU strobe frequency @ RATE 14 = 1.97MHz
		dwCpuFreq = ((14 + 1) * 524288) >> 2;

		dw2F = f * 126 + 262;				// F=f*63+131
	}
	else									// York chip with 48G and later ROM
	{
		// CPU strobe frequency @ RATE 27 = 3.67MHz
		// CPU strobe frequency @ RATE 29 = 3.93MHz
		dwCpuFreq = ((27 + 1) * 524288) >> 2;

		dw2F = f * 180 + 367;				// F=f*90+183.5
	}

	freq = dwCpuFreq / dw2F;
	dur = (dw2F * (256 - 16 * d)) * 1000 / 2 / dwCpuFreq;

	if (freq > 4400) freq = 4400;			// high limit of HP

	Beeper(freq,dur);						// beeping

	// estimate cpu cycles for beeping time (2MHz / 4MHz)
	w->cycles += dur * ((cCurrentRomType=='S') ? 2000 : 4000);           

	w->P = 0;								// P=0
	w->carry = FALSE;						// RTNCC
	w->pc = rstkpop();
	return;
}


#if TARGET_OS_IPHONE
void AudioInterruptListener(void *inClientData, UInt32 inInterruptionState)
{
    [[CalcBackend sharedBackend] interruptToneWithState: inInterruptionState];
}
#endif

@implementation CalcToneGenerator

- (id)init
{
    self = [super init];
    if (self)
    {
        audioEngine = [[AVAudioEngine alloc] init];
        audioPlayer = [[AVAudioPlayerNode alloc] init];
        audioFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:CALC_AUD_SAMPLE_RATE channels:1];
        if (nil == audioEngine || nil == audioPlayer || nil == audioFormat)
        {
            [self release];
            return nil;
        }
        [audioEngine attachNode: audioPlayer];
        [audioEngine connect:audioPlayer to:[audioEngine mainMixerNode] format:audioFormat];
#if TARGET_OS_IPHONE
        AudioSessionSetActive(true);
#endif
    }
    return self;
}

- (void)dealloc
{
#if TARGET_OS_IPHONE
    AudioSessionSetActive(false);
#endif
    [audioPlayer stop];
    [audioEngine stop];
    [audioPlayer release];
    [audioEngine release];
    [audioFormat release];
    [super dealloc];
}

- (void)playToneWithFrequency:(DWORD)freq duration:(DWORD)duration
{
    AVAudioFrameCount L;    // length of sample
    double F;               // frequency of sample
    float volume;
    float amplitude;
    float *samples;
    AVAudioFrameCount T;    // time

    L = (AVAudioFrameCount)(CALC_AUD_SAMPLE_RATE*(double)duration/1000);
    if (0 == L)
        return;

    // start the engine lazily so the audio hardware is only claimed once a beep is needed
    if (![audioEngine isRunning])
    {
        NSError *err = nil;
        if (![audioEngine startAndReturnError: &err])
            return;
    }

    AVAudioPCMBuffer *buffer = [[[AVAudioPCMBuffer alloc] initWithPCMFormat:audioFormat frameCapacity:L] autorelease];
    if (nil == buffer)
        return;
    [buffer setFrameLength: L];

    volume = [[NSUserDefaults standardUserDefaults] floatForKey: @"WaveVolume"];
    if (volume < 0.f) volume = 0.f;
    if (volume > 1.f) volume = 1.f;

    // generate square wave
    samples   = [buffer floatChannelData][0];
    amplitude = (float)CALC_AUD_MAX_AMPLITUDE/32768.f;
    F = 2.*freq/CALC_AUD_SAMPLE_RATE;
    for (T = 0; T < L; ++T)
        samples[T] = ((SInt16)(F*T) & 1)*amplitude;

    [audioPlayer setVolume: volume];
    // like alSourcePlay, a new tone replaces any tone still playing
    [audioPlayer scheduleBuffer:buffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
    if (![audioPlayer isPlaying])
        [audioPlayer play];
}
@end

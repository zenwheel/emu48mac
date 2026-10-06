//
//  CalcView.m
//  emu48
//
//  A container for the calc background, lcd, annunciators,
//  and button redrawing operations. This is the calc UI.
//
//  Created by Da Woon Jung on Wed Feb 18 2004.
//  Copyright (c) 2004 dwj. All rights reserved.
//
#import "CalcView.h"
#import "pch.h"
#import "EMU48.H"
#import "IO.H"
#import "CalcAppController.h"
#import "CalcBackend.h"
#import "stack.h"

#define SharedView      [[CalcBackend sharedBackend] calcView]

// display update 1/frequency (1/64) in seconds
#define DISPLAY_FREQ    0.033
//0.019

BOOL   bGrayscale = FALSE;
static BYTE byVblRef = 0;					// VBL stop reference

extern CHIPSET Chipset;

BYTE (*GetLineCounter)(VOID) = NULL;
VOID (*StartDisplay)(BYTE byInitial) = NULL;
VOID (*StopDisplay)(VOID) = NULL;

BYTE GetLineCounterGray(VOID);
VOID StartDisplayGray(BYTE byInitial);
VOID StopDisplayGray(VOID);
BYTE GetLineCounterBW(VOID);
VOID StartDisplayBW(BYTE byInitial);
VOID StopDisplayBW(VOID);


@interface CalcView(Private)
- (void)UpdateContrast:(BYTE)byContrast;
- (void)GetLineCounter:(NSMutableData *)aOutData;
- (void)scheduleBWUpdate;
- (BOOL)keyEvent:(NSEvent *)theEvent pressed:(BOOL)aPressed;
@end


@implementation CalcView

- (id)initWithFrame:(NSRect)aFrame
{
    self = [super initWithFrame: aFrame];
    if (self)
    {
        [self registerForDraggedTypes: [CalcStack copyableTypes]];
    }
    return self;
}

- (void)dealloc
{
    [bwLcdTimer release];
    [uLcdTimerId release];
    [mainBitmap release];
    [super dealloc];
}

+ (CalcImage *)CreateMainBitmap:(NSString *)filename
{
    if (nil==filename)
        return nil;

    NSData *imgData = [[NSData alloc] initWithContentsOfFile: filename];
    if (nil == imgData)
        return nil;
    // Using NSImage -initWithContentsOfFile: results in dpi scaling
    // We want to ignore dpi, so use an image rep instead
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData: imgData];
    CalcImage *img = nil;
    if (rep)
    {
        img = [[CalcImage alloc] initWithSize:NSMakeSize([rep pixelsWide], [rep pixelsHigh])];
    }
    if (img)
    {
        [img addRepresentation:rep];
        [img setSize:NSMakeSize([rep pixelsWide], [rep pixelsHigh])];
        [rep release];
    }

    [imgData release];
    return [img autorelease];
}

- (void)drawRect:(NSRect)aRect
{
    [mainBitmap drawAtPoint:mainBitmapOrigin fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0];

    CalcImage *annunciator = mainBitmap;
    int i;
    for (i = 0; i < sizeof(annunciatorStates); ++i)
    {
        if (NSIntersectsRect(aRect, annunciatorOff[i]))
        {
            NSRect annunSrcRect;
            if (annunciatorStates[i])
            {
                annunSrcRect = annunciatorOn[i];
            }
            else
            {
                annunSrcRect = annunciatorOff[i];
                annunSrcRect.origin.y += ([mainBitmap size].height - [self bounds].size.height);
            }
            [annunciator drawInRect:annunciatorOff[i] fromRect:annunSrcRect operation:NSCompositingOperationCopy fraction:1.0];
        }
    }

    NSRect displayButtonRect = drawingButtonRect;
    displayButtonRect.origin.y = [self bounds].size.height - displayButtonRect.origin.y - displayButtonRect.size.height;
    if (NSIntersectsRect(aRect, displayButtonRect))
    {
        CalcImage *button = mainBitmap;
        NSRect srcButtonRect = drawingButtonRect;
        NSRect srcButtonRectPressed = drawingButtonRectPressed;
        srcButtonRect.origin.y = [mainBitmap size].height - srcButtonRect.origin.y - srcButtonRect.size.height;
        srcButtonRectPressed.origin.y = [mainBitmap size].height - srcButtonRectPressed.origin.y - srcButtonRectPressed.size.height;

		switch (drawingButtonType)
		{
            case 0: // bitmap key
                if (drawingButtonPressed)
                {
                    [button drawInRect:displayButtonRect fromRect:srcButtonRectPressed operation:NSCompositingOperationCopy fraction:1.0];
                }
                break;
            case 1: // shift key to right down
                if (drawingButtonPressed)
                {
                    float x0 = displayButtonRect.origin.x;
                    float y0 = displayButtonRect.origin.y+displayButtonRect.size.height;
                    float x1 = x0+displayButtonRect.size.width-1.;
                    float y1 = displayButtonRect.origin.y+1.;
                    NSRect offsetRectSrc = NSOffsetRect(srcButtonRect, 2., 3.);
                    offsetRectSrc.size.width  -= 5.;
                    offsetRectSrc.size.height -= 5.;
                    NSRect offsetRectDst = NSOffsetRect(displayButtonRect, 3., 2.);
                    offsetRectDst.size.width  -= 5.;
                    offsetRectDst.size.height -= 5.;
                    [button drawInRect:offsetRectDst fromRect:offsetRectSrc operation:NSCompositingOperationCopy fraction:1.0];
                    [[NSColor blackColor] setStroke];
                    [NSBezierPath strokeLineFromPoint:NSMakePoint(x0, y0) toPoint:NSMakePoint(x1, y0)];
                    [NSBezierPath strokeLineFromPoint:NSMakePoint(x0, y0) toPoint:NSMakePoint(x0, y1)];
                    [[NSColor whiteColor] setStroke];
                    [NSBezierPath strokeLineFromPoint:NSMakePoint(x1, y0) toPoint:NSMakePoint(x1, y1)];
                    [NSBezierPath strokeLineFromPoint:NSMakePoint(x0, y1) toPoint:NSMakePoint(x1+1., y1)];
                }
                break;
            case 2: // do nothing
                break;
            case 3: // invert key color, even in display
                if (drawingButtonPressed)
                {
                    CGContextRef ctxt = [[NSGraphicsContext currentContext] CGContext];
                    CGContextSetBlendMode(ctxt, kCGBlendModeDifference);
                    CGContextSetGrayFillColor(ctxt, 1.0, 1.0);
                    CGContextFillRect(ctxt, *(CGRect *)&displayButtonRect);
                }
                break;
            case 4: // bitmap key, even in display
#if 0
                // TODO: Implement button draw type = 4
                if (drawingButtonPressed)
                {
                    // update background only
                    BitBlt(hWindowDC, x0, y0, pButton[nId].nCx, pButton[nId].nCy, hMainDC, x0, y0, SRCCOPY);
                }
                else
                {
                    RECT Rect;
                    Rect.left = x0 - nBackgroundX;
                    Rect.top  = y0 - nBackgroundY;
                    Rect.right  = Rect.left + pButton[nId].nCx;
                    Rect.bottom = Rect.top + pButton[nId].nCy;
                    InvalidateRect(hWnd, &Rect, FALSE);	// call WM_PAINT for background and display redraw
                }
#endif
                break;
            case 5: // transparent circle
                if (drawingButtonPressed)
                {
                    NSRect circleRect = displayButtonRect;
                    if (circleRect.size.height < circleRect.size.width)
                        circleRect.size.width = circleRect.size.height;
                    else
                        circleRect.size.height = circleRect.size.width;
                    circleRect.origin.x += (displayButtonRect.size.width - circleRect.size.width)*0.5;
                    circleRect.origin.y += (displayButtonRect.size.height - circleRect.size.height)*0.5;
                    NSColor *milkyWhite = [NSColor colorWithDeviceWhite:1.0 alpha:0.5];
                    [milkyWhite setFill];
                    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect: circleRect];
                    [circle fill];
                }
                break;
            default: // black key, default drawing on illegal types
                if (drawingButtonPressed)
                {
                    [[NSColor blackColor] setFill];
                    NSRectFill(displayButtonRect);
                }
		}
    }
}


- (void)setMainBitmap:(CalcImage *)aImage atOrigin:(CalcPoint)aOrigin
{
    [mainBitmap release];
    mainBitmap = [aImage retain];
    mainBitmapOrigin = aOrigin;
    mainBitmapOrigin.y = [self bounds].size.height - [mainBitmap size].height - mainBitmapOrigin.y;
}

- (CalcImage *)mainBitmap
{
    return mainBitmap;
//    return [self image];
}

- (void)setLCD:(NSView<CalcLCD> *)aLcd
      atOrigin:(CalcPoint)origin
{
    [lcd removeFromSuperviewWithoutNeedingDisplay];
    lcd = aLcd;
    [self addSubview: lcd]; // retains it
    origin.y = [self bounds].size.height - [lcd bounds].size.height - origin.y;
    [lcd setFrameOrigin:origin];
}

- (void)setLcdGrayscaleMode:(BOOL)isGrayscale
{
    if ((bGrayscale = isGrayscale))
    {
		GetLineCounter = GetLineCounterGray;
		StartDisplay   = StartDisplayGray;
		StopDisplay    = StopDisplayGray;
    }
    else
    {
		GetLineCounter = GetLineCounterBW;
		StartDisplay   = StartDisplayBW;
		StopDisplay    = StopDisplayBW;
    }
    [lcd SetGrayscaleMode: isGrayscale];
}

- (void) UpdateContrast:(BYTE) byContrast
{
    [lcd UpdateContrast: byContrast];
}

- (void)setAnnunciatorRect:(CalcRect)aRect atIndex:(int)nId isOn:(BOOL)isOn
{
    if (isOn)
    {
        aRect.origin.y = [mainBitmap size].height - aRect.origin.y - aRect.size.height;
        annunciatorOn[nId]  = aRect;
    }
    else
    {
        aRect.origin.y = [self bounds].size.height - aRect.origin.y - aRect.size.height;
        annunciatorOff[nId] = aRect;
    }
}

- (void) GetLineCounter:(NSMutableData *) aOutData
{
	LARGE_INTEGER lLC;
	BYTE          byTime;
    BYTE          result = 0;

	if (![uLcdTimerId isValid])					// display off
    {
        result = ((Chipset.IORam[LINECOUNT+1] & (LC5|LC4)) << 4) | Chipset.IORam[LINECOUNT];
    }
    else
    {
        QueryPerformanceCounter(&lLC);			// get elapsed time since display update
        
        // elapsed ticks so far
        byTime = (BYTE) (((lLC.QuadPart - lLcdRef.QuadPart) << 12) / lFreq.QuadPart);
        
        if (byTime > 0x3F) byTime = 0x3F;		// all counts made

        result = 0x3F - byTime;
    }
    [aOutData replaceBytesInRange:NSMakeRange(0, sizeof(result)) withBytes:&result];
}

- (void)update:(NSTimer *)timer
{
	EnterCriticalSection(&csLcdLock);
	{
        [self UpdateMainDisplay];
        [self UpdateMenuDisplay];
        [self RefreshDisp0];
    }
	LeaveCriticalSection(&csLcdLock);

	QueryPerformanceCounter(&lLcdRef);		// actual time
}

- (void)updateBW:(NSTimer *)timer
{
    [lcd setNeedsDisplay: YES];
    [bwLcdTimer release];
    bwLcdTimer = nil;
}

- (void)scheduleBWUpdate
{
    bwLcdTimer = [[NSTimer scheduledTimerWithTimeInterval:DISPLAY_FREQ target:self selector:@selector(updateBW:) userInfo:nil repeats:NO] retain];  // one-shot update
}

- (void)StartDisplay:(NSNumber *)aInitial
{
    BYTE byInitial = [aInitial unsignedCharValue];
	if ([uLcdTimerId isValid])						// LCD update timer running
		return;								// -> quit

	if (Chipset.IORam[BITOFFSET]&DON)		// display on?
	{
		QueryPerformanceCounter(&lLcdRef);	// actual time of top line

		// adjust startup counter to get the right VBL value
		_ASSERT(byInitial <= 0x3F);			// line counter value 0 - 63
		lLcdRef.QuadPart -= ((LONGLONG) (0x3F - byInitial) * lFreq.QuadPart) >> 12;

        [uLcdTimerId release];
        uLcdTimerId = [[NSTimer scheduledTimerWithTimeInterval:DISPLAY_FREQ target:self selector:@selector(update:) userInfo:nil repeats:YES] retain];
	}
}


- (void)StopDisplay
{
	BYTE a[2];
	ReadIO(a,LINECOUNT,2,TRUE);					// update VBL at display off time
    
	if (![uLcdTimerId isValid])					// timer stopped
		return;								// -> quit

    [uLcdTimerId invalidate];
    [uLcdTimerId release];
    uLcdTimerId = nil;

	EnterCriticalSection(&csLcdLock);		// update to last condition
	{
		[self UpdateMainDisplay];				// update display
		[self UpdateMenuDisplay];
        [self RefreshDisp0];
	}
	LeaveCriticalSection(&csLcdLock);
}


- (void)UpdateDisplayPointers
{
	EnterCriticalSection(&csLcdLock);
	{
#if defined DEBUG_DISPLAY
		{
			NSLog(@"%.5lx: Update Display Pointer", Chipset.pc);
		}
#endif

		// calculate display width
		Chipset.width = (34 + Chipset.loffset + (Chipset.boffset / 4) * 2) & 0xFFFFFFFE;
		Chipset.end1 = Chipset.start1 + MAINSCREENHEIGHT * Chipset.width;
		if (Chipset.end1 < Chipset.start1)
		{
			// calculate first address of main display
			Chipset.start12 = Chipset.end1 - Chipset.width;
			// calculate last address of main display
			Chipset.end1 = Chipset.start1 - Chipset.width;
		}
		else
		{
			Chipset.start12 = Chipset.start1;
		}
		Chipset.end2 = Chipset.start2 + MENUHEIGHT * 34;
	}
	LeaveCriticalSection(&csLcdLock);
}

- (void)UpdateMainDisplay
{
    [lcd performSelectorOnMainThread:@selector(UpdateMain) withObject:nil waitUntilDone:NO];
}

- (void)UpdateMenuDisplay
{
    [lcd performSelectorOnMainThread:@selector(UpdateMenu) withObject:nil waitUntilDone:NO];
}

- (void)RefreshDisp0
{
    [lcd performSelectorOnMainThread:@selector(RefreshDisp0) withObject:nil waitUntilDone:NO];
}

- (void)WriteToMain:(CalcLCDWriteArgument *)args
{
    [lcd WriteToMain: args];
    // Do our own display coalescing as incremental updates using
    // setNeedsDisplayInRect is proving to be too inefficient
    if (nil == bwLcdTimer)
        [self performSelectorOnMainThread:@selector(scheduleBWUpdate) withObject:nil waitUntilDone:YES];
}

- (void)WriteToMenu:(CalcLCDWriteArgument *)args
{
    [lcd WriteToMenu: args];
    if (nil == bwLcdTimer)
        [self performSelectorOnMainThread:@selector(scheduleBWUpdate) withObject:nil waitUntilDone:YES];
}

- (void)UpdateAnnunciators
{
    const BYTE annCtrl[] = { LA1, LA2, LA3, LA4, LA5, LA6 };
    CalcBackend *backend = [CalcBackend sharedBackend];
    BYTE c = (BYTE)(Chipset.IORam[ANNCTRL] | (Chipset.IORam[ANNCTRL+1]<<4));
	// switch annunciators off if timer stopped
	if ((c & AON) == 0 || (Chipset.IORam[TIMER2_CTRL] & RUN) == 0)
		c = 0;

    int i;
    BOOL annunciatorState;
    for (i = 0; i < sizeof(annCtrl); ++i)
    {
        annunciatorState = (0 != (c&annCtrl[i]));
        if (annunciatorStates[i] != annunciatorState)
        {
            annunciatorStates[i]  = annunciatorState;
            [self setNeedsDisplayInRect: annunciatorOff[i]];
        }
    }
}


- (void)mouseDown:(NSEvent *)theEvent
{
    NSPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    point.y = [self bounds].size.height - point.y;
    [[CalcBackend sharedBackend] mouseDownAt: point];
}

- (void)rightMouseDown:(NSEvent *)theEvent
{
    NSPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    point.y = [self bounds].size.height - point.y;
    [[CalcBackend sharedBackend] rightMouseDownAt: point];
}

- (void)mouseUp:(NSEvent *)theEvent
{
    NSPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    point.y = [self bounds].size.height - point.y;
    [[CalcBackend sharedBackend] mouseUpAt: point];
}

- (NSDragOperation)draggingEntered:(id < NSDraggingInfo >)sender
{
    NSDragOperation result = NSDragOperationNone;
    NSPasteboard *pb = [sender draggingPasteboard];
    if ([CalcStack bestTypeFromPasteboard: pb])
        result = NSDragOperationCopy;
    return result;
}

- (void)copy:(id)sender
{
    NSError *err = nil;
    CalcStack *stack = [[CalcStack alloc] initWithError: &err];
    if (stack)
        [stack copyToPasteboard: [NSPasteboard generalPasteboard]];
    else
        NSBeep();
}

- (void)paste:(id)sender
{
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    CalcStack *stack = [[[CalcStack alloc] init] autorelease];
    if (![stack pasteFromPasteboard: pb])
        NSBeep();
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)item
{
    if ([item action] == @selector(paste:))
    {
        return (nil != [CalcStack bestTypeFromPasteboard: [NSPasteboard generalPasteboard]]);
    }
    return YES;
}

- (BOOL)prepareForDragOperation:(id < NSDraggingInfo >)sender
{
    return YES;
}

- (BOOL)performDragOperation:(id < NSDraggingInfo >)sender
{
    NSPasteboard *pb = [sender draggingPasteboard];
    CalcStack *stack = [[[CalcStack alloc] init] autorelease];
    return [stack pasteFromPasteboard: pb];
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

// KML Scancodes are Windows virtual-key codes, which identify physical keys.
// Map Mac virtual key codes (kVK_* in HIToolbox/Events.h) to them; 0 = unmapped.
static const BYTE MacKeyCodeToVK[128] =
{
    /* 0x00 A S D F H G Z X */  'A', 'S', 'D', 'F', 'H', 'G', 'Z', 'X',
    /* 0x08 C V ISO B Q W E R */ 'C', 'V', 0,   'B', 'Q', 'W', 'E', 'R',
    /* 0x10 Y T 1 2 3 4 6 5 */  'Y', 'T', '1', '2', '3', '4', '6', '5',
    /* 0x18 = 9 7 - 8 0 ] O */  187, '9', '7', 189, '8', '0', 221, 'O',
    /* 0x20 U [ I P Ret L J ' */ 'U', 219, 'I', 'P', 13,  'L', 'J', 222,
    /* 0x28 K ; \ , / N M . */ 'K', 186, 220, 188, 191, 'N', 'M', 190,
    /* 0x30 Tab Spc ` Del - Esc - - */ 9, 32, 192, 8,   0,   27,  0,   0,
    /* 0x38 */                  0,   0,   0,   0,   0,   0,   0,   0,
    /* 0x40 - KP. - KP* - KP+ - Clear */ 0, 110, 0, 106, 0, 107, 0, 144,
    /* 0x48 - - - KP/ KPEnt - KP- - */ 0, 0,  0,   111, 13,  0,   109, 0,
    /* 0x50 - KP= KP0 KP1 KP2 KP3 KP4 KP5 */ 0, 187, 96, 97, 98, 99, 100, 101,
    /* 0x58 KP6 KP7 - KP8 KP9 - - - */ 102, 103, 0, 104, 105, 0, 0, 0,
    /* 0x60 F5 F6 F7 F3 F8 F9 - F11 */ 116, 117, 118, 114, 119, 120, 0, 122,
    /* 0x68 - - - - - F10 - F12 */ 0,   0,   0,   0,   0,   121, 0,   123,
    /* 0x70 - - Help Home PgUp FwdDel F4 End */ 0, 0, 45, 36, 33, 46, 115, 35,
    /* 0x78 F2 PgDn F1 Left Right Down Up - */ 113, 34, 112, 37, 39, 40, 38, 0,
};

// Virtual key sent for each Mac key while it is held, so the release matches
// the press even if modifiers change in between
static BYTE heldKeyVK[128];

- (BOOL)keyEvent:(NSEvent *)theEvent pressed:(BOOL)aPressed
{
    NSEventModifierFlags modifiers = [theEvent modifierFlags];
    unsigned short keyCode = [theEvent keyCode];
    if ((modifiers & NSEventModifierFlagCommand) || keyCode >= 128)
        return NO;

    CalcBackend *backend = [CalcBackend sharedBackend];
    BYTE key;
    if (aPressed)
    {
        key = MacKeyCodeToVK[keyCode];
        NSString *chars = [theEvent characters];
        unichar ch = ([chars length] > 0) ? [chars characterAtIndex: 0] : 0;
        BYTE alt = 0;
        switch (ch)
        {
            // Arithmetic operators go to the numeric keypad keys (the only place most
            // KMLs define them), however they were typed, e.g. shift-8 for *
            case '+': alt = 107; break;     // VK_ADD
            case '-': alt = 109; break;     // VK_SUBTRACT
            case '*': alt = 106; break;     // VK_MULTIPLY
            case '/': alt = 111; break;     // VK_DIVIDE
            default:
                // otherwise only fall back to the keypad for keys the KML doesn't define
                if (0 == key || ![backend hasKey: key])
                {
                    if (ch == '.') alt = 110;                                   // VK_DECIMAL
                    else if (ch >= '0' && ch <= '9') alt = 96 + (ch - '0');     // VK_NUMPAD0-9
                }
                break;
        }
        if (alt && [backend hasKey: alt])
            key = alt;
        if (0 == key)
            return NO;
        if ([theEvent isARepeat] && heldKeyVK[keyCode] == key)
            return YES;
        heldKeyVK[keyCode] = key;
    }
    else
    {
        key = heldKeyVK[keyCode];
        heldKeyVK[keyCode] = 0;
        if (0 == key)
            return NO;
    }
    [backend runKey:key pressed:aPressed];
    return YES;
}

- (void)keyDown:(NSEvent *)theEvent
{
    if (![self keyEvent:theEvent pressed:YES])
    {
        [super keyDown: theEvent];
    }
}

- (void)keyUp:(NSEvent *)theEvent
{
    if (![self keyEvent:theEvent pressed:NO])
    {
        [super keyUp: theEvent];
    }
}

- (void)flagsChanged:(NSEvent *)theEvent
{
    unsigned modifiers = [theEvent modifierFlags];
    if (modifiers & NSEventModifierFlagCommand)
    {
        [super flagsChanged: theEvent];
    }
    else
    {
        CalcBackend *backend = [CalcBackend sharedBackend];
        if (modifiers & NSEventModifierFlagOption)
            [backend runKey:17 pressed:YES];
        if (modifiers & NSEventModifierFlagControl)
            [backend runKey:16 pressed:YES];
        
        if (0 == (modifiers & NSEventModifierFlagOption))
            [backend runKey:17 pressed:NO];
        if (0 == (modifiers & NSEventModifierFlagControl))
            [backend runKey:16 pressed:NO];
    }
}

- (void)buttonDrawing
{
    CalcBackend *backend = [CalcBackend sharedBackend];
    drawingButtonPressed = [backend drawingButtonPressed];
    drawingButtonType    = [backend drawingButtonType];
    drawingButtonRect    = [backend drawingButtonRect];
    drawingButtonRectPressed = [backend drawingButtonRectPressed];

    switch (drawingButtonType)
    {
        case 2: // do nothing
			break;
        default:
        {
            NSRect displayRect = drawingButtonRect;
            displayRect.origin.y = [self bounds].size.height - displayRect.origin.y - displayRect.size.height;
            [self setNeedsDisplayInRect: displayRect];
        }
    }
}
@end


VOID UpdateContrast(BYTE byContrast)
{
    [SharedView UpdateContrast: byContrast];
}

VOID UpdateDisplayPointers(VOID)
{
    [SharedView UpdateDisplayPointers];
}

VOID UpdateMainDisplay(VOID)
{
    [SharedView UpdateMainDisplay];
}

VOID UpdateMenuDisplay(VOID)
{
    [SharedView UpdateMenuDisplay];
}

// CdB for HP: add header management
VOID RefreshDisp0()
{
    [SharedView RefreshDisp0];
}

VOID WriteToMainDisplay(LPBYTE a, DWORD d, UINT s)
{
    CalcLCDWriteArgument *args = [[CalcLCDWriteArgument alloc] initWithPointer:a offset:d count:s];
    [SharedView WriteToMain: args];
    [args release];
}

VOID WriteToMenuDisplay(LPBYTE a, DWORD d, UINT s)
{
    CalcLCDWriteArgument *args = [[CalcLCDWriteArgument alloc] initWithPointer:a offset:d count:s];
    [SharedView WriteToMenu: args];
    [args release];
}

VOID UpdateAnnunciators(VOID)
{
    [SharedView performSelectorOnMainThread:@selector(UpdateAnnunciators) withObject:nil waitUntilDone:YES];
}

BYTE GetLineCounterGray(VOID)
{
    BYTE result = 0;
    BYTE *resultPtr = nil;
    NSMutableData *resultData = [[NSMutableData alloc] initWithBytes:&result length:sizeof(result)];
    [SharedView performSelectorOnMainThread:@selector(GetLineCounter:) withObject:resultData waitUntilDone:YES];
    resultPtr = (BYTE *)[resultData bytes];
    if (resultPtr)
        result = *resultPtr;
    [resultData release];
    return result;
}

VOID StartDisplayGray(BYTE byInitial)
{
    [SharedView performSelectorOnMainThread:@selector(StartDisplay:) withObject:[NSNumber numberWithUnsignedChar:byInitial] waitUntilDone:YES];
}

VOID StopDisplayGray(VOID)
{
    [SharedView performSelectorOnMainThread:@selector(StopDisplay) withObject:nil waitUntilDone:YES];
}

//################
//#
//# functions for black and white implementation
//#
//################

// LCD line counter calculation in BW mode
static BYTE F4096Hz(VOID)					// get a 6 bit 4096Hz down counter value
{
	LARGE_INTEGER lLC;
    
	QueryPerformanceCounter(&lLC);			// get counter value
    
	// calculate 4096 Hz frequency down counter value
	return -(BYTE)(((lLC.QuadPart - lAppStart.QuadPart) << 12) / lFreq.QuadPart) & 0x3F;
}

BYTE GetLineCounterBW(VOID)			// get line counter value
{
	_ASSERT(byVblRef < 0x40);
#ifdef USE_VBL
    // TODO: Make vbl work without garbage
	return (0x40 + F4096Hz() - byVblRef) & 0x3F;
#else
    return 0;   // avoids garbage
#endif
}

VOID StartDisplayBW(BYTE byInitial)
{
	// get positive VBL difference between now and stop time
	byVblRef = (0x40 + F4096Hz() - byInitial) & 0x3F;
}

VOID StopDisplayBW(VOID)
{
	BYTE a[2];
	ReadIO(a,LINECOUNT,2,TRUE);				// update VBL at display off time
}

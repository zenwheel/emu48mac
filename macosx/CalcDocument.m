//
//  CalcDocument.m
//  emu48mac
//
//  Created by Da Woon Jung on Wed Feb 18 2004.
//  Copyright (c) 2004 dwj. All rights reserved.
//

#import "CalcDocument.h"
#import "CalcAppController.h"
#import "CalcPrefController.h"
#import "CalcBackend.h"
#import "CalcView.h"
#import "rawlcd.h"
#import <objc/message.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Document types are reported as UTIs (from LSItemContentTypes) on modern macOS;
// older systems used the CFBundleTypeName, so accept either.
#define CALC_STATE_TYPE     @"com.dw.emu48-state"
#define CALC_KML_TYPE       @"com.dw.emu48-kml"

static BOOL CalcIsStateType(NSString *aType)
{
    return [aType isEqualToString: CALC_STATE_TYPE] || [aType isEqualToString: @"Emu48 State"];
}

static BOOL CalcIsKmlType(NSString *aType)
{
    return [aType isEqualToString: CALC_KML_TYPE] || [aType isEqualToString: @"KML File"];
}


@implementation CalcDocument

- (IBAction)backupCalc:(id)sender
{
    [[CalcBackend sharedBackend] backup];
}

- (IBAction)changeKmlDummy:(id)sender
{
}

- (IBAction)openObject:(id)sender
{
    NSModalResponse result;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setResolvesAliases: YES];
    [panel setAllowsMultipleSelection: NO];
    result = [panel runModal];
    if (result == NSModalResponseOK)
    {
        NSError *err = nil;
        if (![[CalcBackend sharedBackend] readFromObject:[[panel URL] path] error:&err] && err)
            [self presentError: err];
    }
}

- (IBAction)restoreCalc:(id)sender
{
    [[CalcBackend sharedBackend] restore];
}

- (IBAction)saveObject:(id)sender
{
    NSModalResponse result;
    UTType *type = [UTType typeWithIdentifier: @"com.dw.emu48-stack"];
    NSSavePanel *panel = [NSSavePanel savePanel];
    if (type)
        [panel setAllowedContentTypes: [NSArray arrayWithObject: type]];
    [panel setCanSelectHiddenExtension: YES];
    result = [panel runModal];
    if (result == NSModalResponseOK)
    {
        NSError *err = nil;
        if (![[CalcBackend sharedBackend] saveObjectAs:[[panel URL] path] error:&err] && err)
            [self presentError: err];
    }
}


- (id)init
{
    self = [super init];
    if (self)
    {
        [self setHasUndoManager: NO];
    }
    return self;
}

- (void)dealloc
{
    CalcBackend *backend = [CalcBackend sharedBackend];
    [backend stop];
    [super dealloc];
}


- (NSString *)windowNibName
{
    return @"CalcWindow";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)controller
{
    [super windowControllerDidLoadNib: controller];
    // The emulator backend can't be rebuilt from window state; the ReloadFiles pref handles reopening
    [[controller window] setRestorable: NO];
    CalcBackend *backend = [CalcBackend sharedBackend];
    [backend setCalcView: calcView];
    [backend finishInitWithViewContainer:[controller window]
                                lcdClass:[CalcRawLCD class]];
    [backend performSelector:@selector(run) withObject:nil afterDelay:0.0];
    [self updateChangeCount: NSChangeDone];
}

// Decline window restoration (including state saved by earlier launches),
// since the calculator would be restored without its KML or state loaded
- (void)restoreDocumentWindowWithIdentifier:(NSUserInterfaceItemIdentifier)identifier state:(NSCoder *)state completionHandler:(void (^)(NSWindow *window, NSError *error))completionHandler
{
    completionHandler(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)aType error:(NSError **)outError
{
    BOOL result = NO;
    if (CalcIsStateType(aType))
    {
        [[NSFileManager defaultManager] changeCurrentDirectoryPath: [[NSBundle mainBundle] bundlePath]];
        result = [[CalcBackend sharedBackend] readFromState:[absoluteURL path] error:outError];
        if (result)
        {
            [[NSApp delegate] populateChangeKmlMenu];
        }
        else
        {
//            if (outError)
//                *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:-1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"State file could not be read because the associated calculator template file contains errors.",@""), NSLocalizedDescriptionKey, NSLocalizedString(@"The chosen calculator template file contains errors.",@""), NSLocalizedFailureReasonErrorKey, nil]];
        }
        return result;
    }
    else if (CalcIsKmlType(aType))
    {
        result = [[CalcBackend sharedBackend] makeUntitledCalcWithKml: [absoluteURL path] error:outError];
        if (result)
        {
            [[NSApp delegate] populateChangeKmlMenu];
        }
        else
        {
//            if (outError)
//                *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:-1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Calculator template file could not be read because it contained error(s).",@""), NSLocalizedDescriptionKey, NSLocalizedString(@"The chosen calculator template file contains errors.",@""), NSLocalizedFailureReasonErrorKey, nil]];
        }
        return result;
    }

    // Default action for other types
    return [super readFromURL:absoluteURL ofType:aType error:outError];
}

- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)aType error:(NSError **)outError
{
    BOOL result = NO;
    if (CalcIsStateType(aType))
    {
        [[NSFileManager defaultManager] changeCurrentDirectoryPath: [[NSBundle mainBundle] bundlePath]];
        result = [[CalcBackend sharedBackend] saveStateAs:[absoluteURL path] error:outError];
        return result;
    }
    
    return [super writeToURL:absoluteURL ofType:aType error:outError];
}

- (void)saveToURL:(NSURL *)absoluteURL ofType:(NSString *)aType forSaveOperation:(NSSaveOperationType)saveOperation completionHandler:(void (^)(NSError *errorOrNil))completionHandler
{
    [super saveToURL:absoluteURL ofType:aType forSaveOperation:saveOperation completionHandler:^(NSError *errorOrNil) {
        if (nil == errorOrNil)
            [self updateChangeCount: NSChangeDone];
        completionHandler(errorOrNil);
    }];
}

+ (NSURL *)defaultFileURL
{
    NSArray *systemPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if (systemPaths && [systemPaths count] > 0)
    {
        NSString *statePath = [[[systemPaths objectAtIndex: 0] stringByAppendingPathComponent: CALC_USER_PATH] stringByAppendingPathComponent: CALC_STATE_PATH];
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isFolder = NO;
        if (![fm fileExistsAtPath:statePath isDirectory:&isFolder])
        {
            NSArray *pathComponents = [statePath pathComponents];
            NSString *parentPath = @"";
            NSString *pathComp;
            NSEnumerator *pathEnum = [pathComponents objectEnumerator];
            while ((pathComp = [pathEnum nextObject]))
            {
                parentPath = [parentPath stringByAppendingPathComponent: pathComp];
                if (![fm fileExistsAtPath:parentPath isDirectory:&isFolder])
                    [fm createDirectoryAtPath:parentPath withIntermediateDirectories:NO attributes:nil error:NULL];
            }
        }
        else if (!isFolder)
        {
            return nil;
        }
        statePath = [statePath stringByAppendingPathComponent: CALC_DEFAULT_STATE];
        return [NSURL fileURLWithPath: statePath];
    }
    return nil;
}

// Support saving to a fixed file on exit
- (void)canCloseDocumentWithDelegate:(id)delegate
                 shouldCloseSelector:(SEL)shouldCloseSelector
                         contextInfo:(void *)contextInfo
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey: @"AutoSaveOnExit"])
    {
        void (^finish)(NSError *) = ^(NSError *err) {
            BOOL shouldClose = (nil == err);
            if (!shouldClose)
                [self presentError: err];

            if (delegate)
                ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(delegate, shouldCloseSelector, self, shouldClose, contextInfo);
        };
        NSURL *saveURL = [self fileURL];
        if (nil == saveURL)
        {
            saveURL = [[self class] defaultFileURL];
        }
        if (nil == saveURL)
        {
            finish([NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:nil]);
        }
        else
        {
            [self saveToURL:saveURL ofType:CALC_STATE_TYPE forSaveOperation:NSSaveOperation completionHandler:finish];
        }
    }
    else
    {
        [super canCloseDocumentWithDelegate:delegate shouldCloseSelector:shouldCloseSelector contextInfo:contextInfo];
    }
}
@end


@implementation CalcDocumentController

// Overriding newDocument: to implement new document from stationery
- (IBAction)newDocument:(id)sender
{
    NSString *path = nil;
    if ([sender respondsToSelector: @selector(representedObject)])
    {
        path = [sender representedObject];
    }
    if (path)
    {
        [self openDocumentWithContentsOfURL:[NSURL fileURLWithPath: path] display:YES completionHandler:^(NSDocument *doc, BOOL alreadyOpen, NSError *err) {
        if (nil == doc && err)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setObject:[[NSString stringWithFormat: NSLocalizedString(@"The document “%@” could not be opened.",@""), [path lastPathComponent]] stringByAppendingFormat: @" %@", [err localizedFailureReason]] forKey:NSLocalizedDescriptionKey];

            [userInfo setObject:[err localizedFailureReason]
                         forKey:NSLocalizedFailureReasonErrorKey];

            NSError *untitledDocError = [NSError errorWithDomain:[err domain] code:[err code] userInfo:userInfo];
            [self presentError: untitledDocError];
        }
        }];
    }
}

- (void)openDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument completionHandler:(void (^)(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error))completionHandler
{
    [super openDocumentWithContentsOfURL:absoluteURL display:displayDocument completionHandler:^(NSDocument *doc, BOOL documentWasAlreadyOpen, NSError *error) {
        if (doc)
        {
            NSString *type = [doc fileType];
            if (CalcIsKmlType(type))
            {
                [doc setFileURL: nil];
                [doc setFileModificationDate: nil];
            }
        }
        completionHandler(doc, documentWasAlreadyOpen, error);
    }];
}

- (void)noteNewRecentDocument:(NSDocument *)aDocument
{
    NSString *type = [aDocument fileType];
    if (CalcIsStateType(type))
    {
        [super noteNewRecentDocument: aDocument];
    }
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
    // TODO: Don't use hack for dimming recent items
    if ([anItem action] == @selector(newDocument:)  ||
        [anItem action] == @selector(openDocument:) ||
        [anItem action] == @selector(_openRecentDocument:))
    {
        return ([[self documents] count] < 1);
    }
    return [super validateUserInterfaceItem: anItem];
}
@end

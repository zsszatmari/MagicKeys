// Copyright (c) 2010 Spotify AB, (c) 2012 Treasure Box
#import "SPMediaKeyTap.h"
#import "NSObject+SPInvocationGrabbing.h" // https://gist.github.com/511181, in submodule
#import "HIDRemote.h"
#import "Launcher.h"

#define DEBUG_REMOTEVOLUME


@interface SPMediaKeyTap ()
-(BOOL)shouldInterceptMediaKeyEvents;
-(void)setShouldInterceptMediaKeyEvents:(BOOL)newSetting;
-(void)startWatchingAppSwitching;
-(void)stopWatchingAppSwitching;
-(void)eventTapThread;
@end
static SPMediaKeyTap *singleton = nil;

static pascal OSStatus appSwitched (EventHandlerCallRef nextHandler, EventRef evt, void* userData);
static pascal OSStatus appTerminated (EventHandlerCallRef nextHandler, EventRef evt, void* userData);
static CGEventRef tapEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);


// Inspired by http://gist.github.com/546311

@implementation SPMediaKeyTap

static NSString *kKeySerialNumber = @"SerialNumber";
static NSString *kKeyPrefersGlobal = @"PrefersGlobal";
static NSString *kKeyProcessSpecificTap = @"ProcessTap";
static NSString *kKeyProcessSpecificRunloopSource = @"ProcessSource";

#pragma mark -
#pragma mark Setup and teardown
-(id)initWithDelegate:(id)delegate;
{
	_delegate = delegate;
	[self startWatchingAppSwitching];
	singleton = self;
	_mediaKeyAppList = [NSMutableArray new];
    _tapThreadRL=nil;
    _eventPort=nil;
    _eventPortSource=nil;
	return self;
}
-(void)dealloc;
{
	[self stopWatchingMediaKeys];
	[self stopWatchingAppSwitching];
	[_mediaKeyAppList release];
	[super dealloc];
}

- (BOOL)appleRemoteEnabled
{
    return YES;
}

-(void)startWatchingAppSwitching;
{
	// Listen to "app switched" event, so that we don't intercept media keys if we
	// weren't the last "media key listening" app to be active
	EventTypeSpec eventType = { kEventClassApplication, kEventAppFrontSwitched };
    OSStatus err = InstallApplicationEventHandler(NewEventHandlerUPP(appSwitched), 1, &eventType, self, &_app_switching_ref);
	assert(err == noErr);
	
	eventType.eventKind = kEventAppTerminated;
    err = InstallApplicationEventHandler(NewEventHandlerUPP(appTerminated), 1, &eventType, self, &_app_terminating_ref);
	assert(err == noErr);
}
-(void)stopWatchingAppSwitching;
{
	if(!_app_switching_ref) return;
	RemoveEventHandler(_app_switching_ref);
	_app_switching_ref = NULL;
}

-(void)startWatchingMediaKeys;{
    // Prevent having multiple mediaKeys threads
    [self stopWatchingMediaKeys];
    
	[self setShouldInterceptMediaKeyEvents:YES];
	
	// Add an event tap to intercept the system defined media key events
	_eventPort = CGEventTapCreate(kCGSessionEventTap,
								  kCGHeadInsertEventTap,
								  kCGEventTapOptionDefault,
								  kCGEventMaskForAllEvents /*CGEventMaskBit(NX_SYSDEFINED)*/,
								  tapEventCallback,
								  self);
	assert(_eventPort != NULL);
	
    _eventPortSource = CFMachPortCreateRunLoopSource(kCFAllocatorSystemDefault, _eventPort, 0);
	assert(_eventPortSource != NULL);
	
	// Let's do this in a separate thread so that a slow app doesn't lag the event tap
	[NSThread detachNewThreadSelector:@selector(eventTapThread) toTarget:self withObject:nil];
    
    if (hidRemote == nil) {
        hidRemote = [HIDRemote sharedHIDRemote];
        [hidRemote setDelegate:self];
    }
    
    if (mikey == nil) {
        NSArray *mikeys = [DDHidAppleMikey allMikeys];
        if ([mikeys count] > 0) {
            mikey = [[mikeys objectAtIndex:0] retain];
            [mikey setDelegate:self];
            [mikey setListenInExclusiveMode:YES];
            @try {
                [mikey startListening];
            } @catch (id exception) {
                NSLog(@"access to mic failed");
            }
        }
    }
}

-(void)stopWatchingMediaKeys;
{
	// TODO<nevyn>: Shut down thread, remove event tap port and source
    
    if (mikey) {
        [mikey stopListening];
        [mikey release];
        mikey = nil;
    }
    
    if(_tapThreadRL){
        CFRunLoopStop(_tapThreadRL);
        _tapThreadRL=nil;
    }
    
    if(_eventPort){
        CFMachPortInvalidate(_eventPort);
        CFRelease(_eventPort);
        _eventPort=nil;
    }
    
    if(_eventPortSource){
        CFRelease(_eventPortSource);
        _eventPortSource=nil;
    }    
}

#pragma mark -
#pragma mark Accessors

+(BOOL)usesGlobalMediaKeyTap
{
#ifdef _DEBUG
	// breaking in gdb with a key tap inserted sometimes locks up all mouse and keyboard input forever, forcing reboot
	return YES;
#else
	// XXX(nevyn): MediaKey event tap doesn't work on 10.4, feel free to figure out why if you have the energy.
	return 
		![[NSUserDefaults standardUserDefaults] boolForKey:kIgnoreMediaKeysDefaultsKey]
		&& floor(NSAppKitVersionNumber) >= 949/*NSAppKitVersionNumber10_5*/;
#endif
}

+ (NSArray*)defaultMediaKeyUserBundleIdentifiers;
{
	return [NSArray arrayWithObjects:
		[[NSBundle mainBundle] bundleIdentifier], // your app
		@"com.spotify.client",
		@"com.apple.iTunes",
		@"com.apple.QuickTimePlayerX",
		@"com.apple.quicktimeplayer",
		@"com.apple.iWork.Keynote",
		@"com.apple.iPhoto",
		@"org.videolan.vlc",
		@"com.apple.Aperture",
		@"com.plexsquared.Plex",
		@"com.soundcloud.desktop",
		@"org.niltsh.MPlayerX",
		@"com.ilabs.PandorasHelper",
		@"com.mahasoftware.pandabar",
		@"com.bitcartel.pandorajam",
		@"org.clementine-player.clementine",
		@"fm.last.Last.fm",
		@"com.beatport.BeatportPro",
		@"com.Timenut.SongKey",
		@"com.macromedia.fireworks", // the tap messes up their mouse input
        @"com.treasurebox.gear",
        @"de.call-a-nerd.StreamCloud", //Added StreamCloud
		nil
	];
}


-(BOOL)shouldInterceptMediaKeyEvents;
{
	BOOL shouldIntercept = NO;
	@synchronized(self) {
		shouldIntercept = _shouldInterceptMediaKeyEvents;
	}
	return shouldIntercept;
}

-(void)pauseTapOnTapThread:(BOOL)yeahno;
{
	CGEventTapEnable(self->_eventPort, yeahno);
}

-(void)setShouldInterceptMediaKeyEvents:(BOOL)newSetting;
{
	BOOL oldSetting;
	@synchronized(self) {
		oldSetting = _shouldInterceptMediaKeyEvents;
		_shouldInterceptMediaKeyEvents = newSetting;
	}
    if (oldSetting != newSetting) {
        if(_tapThreadRL) {
            id grab = [self grab];
            [grab pauseTapOnTapThread:newSetting];
            NSTimer *timer = [NSTimer timerWithTimeInterval:0 invocation:[grab invocation] repeats:NO];
            CFRunLoopAddTimer(_tapThreadRL, (CFRunLoopTimerRef)timer, kCFRunLoopCommonModes);
        }
    }
}

#pragma mark 
#pragma mark -
#pragma mark Event tap callbacks

- (BOOL)isMediaEvent:(CGEventRef)event type:(CGEventType)type
{
    if(type == kCGEventTapDisabledByTimeout) {
		NSLog(@"Media key event tap was disabled by timeout");
		CGEventTapEnable(self->_eventPort, TRUE);
		return NO;
	} else if(type == kCGEventTapDisabledByUserInput) {
		// Was disabled manually by -[pauseTapOnTapThread]
		return NO;
	}
	NSEvent *nsEvent = nil;
	@try {
		nsEvent = [NSEvent eventWithCGEvent:event];
	}
	@catch (NSException * e) {
		NSLog(@"Strange CGEventType: %d: %@", type, e);
		assert(0);
		return NO;
	}
    
	if (type != NX_SYSDEFINED || [nsEvent subtype] != SPSystemDefinedEventMediaKeys) {
		return NO;
    }
    
	int keyCode = (([nsEvent data1] & 0xFFFF0000) >> 16);
    if (keyCode != NX_KEYTYPE_PLAY && keyCode != NX_KEYTYPE_FAST && keyCode != NX_KEYTYPE_REWIND && keyCode != NX_KEYTYPE_PREVIOUS && keyCode != NX_KEYTYPE_NEXT) {
        
        return NO;
    }
    
	if (![self shouldInterceptMediaKeyEvents])
		return NO;
    
    return YES;
}


// event will have been retained in the other thread
- (BOOL)handleMediaKeyEvent:(CGEventRef)cgEvent
{
#if DEBUG
    NSLog(@"media event: %@", [NSEvent eventWithCGEvent:cgEvent]);
#endif
    
    
    if (!mediaAppForeground && [Launcher launchIfNeeded]) {
        return YES;
    }
    
    if ([_mediaKeyAppList count] == 0) {
        return NO;
    }
    
    NSDictionary *entry = [_mediaKeyAppList objectAtIndex:0];
    // this could be mistaken if both App Store and out-of-App Store versions of G-Ear are installed on the machine...
    if ([[entry objectForKey:kKeyPrefersGlobal] boolValue]) {
        return NO;
    }
    
    ProcessSerialNumber targetSerial;
    [[entry objectForKey:kKeySerialNumber] getValue:&targetSerial];
    CGEventPostToPSN(&targetSerial, cgEvent);
    
    return YES;
}

- (BOOL)doesFirstPreferGlobal
{
    
    if ([_mediaKeyAppList count] == 0) {
        // yes, we mean the system is apple
        return YES;
    }
    
    NSDictionary *entry = [_mediaKeyAppList objectAtIndex:0];
    return [[entry objectForKey:kKeyPrefersGlobal] boolValue];
}

// Note: method called on background thread

static CGEventRef tapEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
#ifdef DEBUG
    //NSLog(@"event %d", type);
#endif
    SPMediaKeyTap *self = refcon;
    
    @autoreleasepool {
        
        if (![self isMediaEvent:event type:type]) {
            return event;
        }
        
        if ([self handleMediaKeyEvent:event]) {
            
            // handled
            return NULL;
        }
        
        // normal flow, for now (see you at tapEventCallbackForProcess)
        return event;

    }
}

static CGEventRef tapEventCallbackForProcess(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    SPMediaKeyTap *self = refcon;

    @autoreleasepool {
        if (![self isMediaEvent:event type:type]) {
            return event;
        }
        
        if ([self doesFirstPreferGlobal]) {
            return NULL;
        } else {
            return event;
        }
    }
}



-(void)eventTapThread;
{
	_tapThreadRL = CFRunLoopGetCurrent();
	CFRunLoopAddSource(_tapThreadRL, _eventPortSource, kCFRunLoopCommonModes);
	CFRunLoopRun();
}

#pragma mark Task switching callbacks

NSString *kMediaKeyUsingBundleIdentifiersDefaultsKey = @"SPApplicationsNeedingMediaKeys";
NSString *kIgnoreMediaKeysDefaultsKey = @"SPIgnoreMediaKeys";



-(void)mediaKeyAppListChanged;
{
    BOOL shouldGrabAppleRemote = ![self doesFirstPreferGlobal];
    BOOL isGrabbingAppleRemote = [hidRemote isStarted];
    if (shouldGrabAppleRemote != isGrabbingAppleRemote) {
        if (shouldGrabAppleRemote) {
            if ([[[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.treasurebox.magickeys"] objectForKey:@"AppleRemoteEnabled"] boolValue]) {
                [hidRemote startRemoteControl:kHIDRemoteModeExclusive];
            }
        } else {
            [hidRemote stopRemoteControl];
        }
    }
    
	if([_mediaKeyAppList count] == 0) return;
	
	/*NSLog(@"--");
	int i = 0;
	for (NSValue *psnv in _mediaKeyAppList) {
		ProcessSerialNumber psn; [psnv getValue:&psn];
		NSDictionary *processInfo = [(id)ProcessInformationCopyDictionary(
			&psn,
			kProcessDictionaryIncludeAllInformationMask
		) autorelease];
		NSString *bundleIdentifier = [processInfo objectForKey:(id)kCFBundleIdentifierKey];
		NSLog(@"%d: %@", i++, bundleIdentifier);
	}*/
	
	[self setShouldInterceptMediaKeyEvents:([_mediaKeyAppList count] > 0)];
}

- (void)removeSerialFromAppList:(NSValue *)psnv
{
    if (_mediaKeyAppList == nil) {
        return;
    }
    [_mediaKeyAppList filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        
        return ![[evaluatedObject objectForKey:kKeySerialNumber] isEqualTo:psnv];
    }]];
}

- (BOOL)isSandboxed:(NSString *)bundleIdentifier
{
    NSURL *appUrl;
    if (LSFindApplicationForInfo(kLSUnknownCreator,(CFStringRef)bundleIdentifier,NULL,NULL,(CFURLRef *)&appUrl) != 0) {
        return NO;
    }
    
    static SecRequirementRef sandboxRequirement = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SecRequirementCreateWithString(CFSTR("entitlement[\"com.apple.security.app-sandbox\"] exists"), kSecCSDefaultFlags, &sandboxRequirement);
    });
    
    SecStaticCodeRef staticCode = NULL;
    SecStaticCodeCreateWithPath((CFURLRef)appUrl, kSecCSDefaultFlags, &staticCode);
    
    BOOL sandboxed = NO;
    if (staticCode != NULL && sandboxRequirement != NULL) {
    
        OSStatus codeCheckResult = SecStaticCodeCheckValidityWithErrors(staticCode, kSecCSBasicValidateOnly, sandboxRequirement, NULL);
        sandboxed = (codeCheckResult == errSecSuccess);
    }
    
    [appUrl release];
    
    return sandboxed;
}

- (void)appIsNowFrontmost:(ProcessSerialNumber)psn
{
	NSValue *psnv = [NSValue valueWithBytes:&psn objCType:@encode(ProcessSerialNumber)];
	
	NSDictionary *processInfo = CFMakeCollectable(ProcessInformationCopyDictionary(
		&psn,
		kProcessDictionaryIncludeAllInformationMask
	));
    [processInfo autorelease];
	NSString *bundleIdentifier = [processInfo objectForKey:(NSString *)kCFBundleIdentifierKey];

	NSArray *whitelistIdentifiers = [[NSUserDefaults standardUserDefaults] arrayForKey:kMediaKeyUsingBundleIdentifiersDefaultsKey];
	if(![whitelistIdentifiers containsObject:bundleIdentifier]) {
        mediaAppForeground = NO;
        return;
    }
    mediaAppForeground = YES;
        
	[self removeSerialFromAppList:psnv];
    BOOL prefersGlobal = [bundleIdentifier hasPrefix:@"com.apple."];
    if (!prefersGlobal) {
        // non-sandboxed application (like VLC, for instance) do have their own method for grabbing events, we don't want to interfere with them
        prefersGlobal = ![self isSandboxed:bundleIdentifier];
    }
    
    NSMutableDictionary *appEntry = [NSMutableDictionary dictionaryWithDictionary:@{ kKeySerialNumber : psnv, kKeyPrefersGlobal : @(prefersGlobal)}];
	if (!prefersGlobal) {
        CFMachPortRef port = CGEventTapCreateForPSN(&psn, kCGHeadInsertEventTap,
                               kCGEventTapOptionDefault,
                               CGEventMaskBit(NX_SYSDEFINED),
                               tapEventCallbackForProcess,
                               self);
        if (port == NULL) {
            NSLog(@"error listening tapping to process %@", bundleIdentifier);
        } else {
            CFRunLoopSourceRef sourceForProcessTap = CFMachPortCreateRunLoopSource(kCFAllocatorSystemDefault, port, 0);
            if (sourceForProcessTap == NULL) {
                NSLog(@"error creating source for process %@", bundleIdentifier);
            } else {
                CFRunLoopAddSource(_tapThreadRL, sourceForProcessTap, kCFRunLoopCommonModes);
                [appEntry setObject:(id)port forKey:kKeyProcessSpecificTap];
                [appEntry setObject:(id)sourceForProcessTap forKey:kKeyProcessSpecificRunloopSource];
                CFRelease(sourceForProcessTap);
            }
            CFRelease(port);
        }
    }
    [_mediaKeyAppList insertObject:appEntry atIndex:0];
	[self mediaKeyAppListChanged];
}

-(void)appTerminated:(ProcessSerialNumber)psn;
{
	NSValue *psnv = [NSValue valueWithBytes:&psn objCType:@encode(ProcessSerialNumber)];
	[self removeSerialFromAppList:psnv];
	[self mediaKeyAppListChanged];
}

static pascal OSStatus appSwitched (EventHandlerCallRef nextHandler, EventRef evt, void* userData)
{
	SPMediaKeyTap *self = (id)userData;

    ProcessSerialNumber newSerial;
    GetFrontProcess(&newSerial);
	
	[self appIsNowFrontmost:newSerial];
		
    return CallNextEventHandler(nextHandler, evt);
}

static pascal OSStatus appTerminated (EventHandlerCallRef nextHandler, EventRef evt, void* userData)
{
	SPMediaKeyTap *self = (id)userData;
	
	ProcessSerialNumber deadPSN;

	GetEventParameter(
		evt, 
		kEventParamProcessID, 
		typeProcessSerialNumber, 
		NULL, 
		sizeof(deadPSN), 
		NULL, 
		&deadPSN
	);

	
	[self appTerminated:deadPSN];
    return CallNextEventHandler(nextHandler, evt);
}

#pragma mark -- Apple Remote



static io_connect_t get_event_driver(void)
{
    static  mach_port_t sEventDrvrRef = 0;
    mach_port_t masterPort, service, iter;
    kern_return_t    kr;
    
    if (!sEventDrvrRef)
    {
        // Get master device port
        kr = IOMasterPort( bootstrap_port, &masterPort );
        check( KERN_SUCCESS == kr);
        
        kr = IOServiceGetMatchingServices( masterPort, IOServiceMatching( kIOHIDSystemClass ), &iter );
        check( KERN_SUCCESS == kr);
        
        service = IOIteratorNext( iter );
        check( service );
        
        kr = IOServiceOpen( service, mach_task_self(),
                           kIOHIDParamConnectType, &sEventDrvrRef );
        check( KERN_SUCCESS == kr );
        
        IOObjectRelease( service );
        IOObjectRelease( iter );
    }
    return sEventDrvrRef;
}


static void HIDPostAuxKey( const UInt8 auxKeyCode, BOOL down )
{
    // pretend that the user just pressed the key
    
    NXEventData   event;
    kern_return_t kr;
    IOGPoint      loc = { 0, 0 };
    
    // Key press event
    UInt32      evtInfo = auxKeyCode << 16 | (down ? (NX_KEYDOWN << 8) : (NX_KEYUP << 8));
    bzero(&event, sizeof(NXEventData));
    event.compound.subType = NX_SUBTYPE_AUX_CONTROL_BUTTONS;
    event.compound.misc.L[0] = evtInfo;
    kr = IOHIDPostEvent( get_event_driver(), NX_SYSDEFINED, loc, &event, kNXEventDataVersion, 0, FALSE );
    check( KERN_SUCCESS == kr );    
}

- (void)hidRemote:(HIDRemote *)hidRemote
  eventWithButton:(HIDRemoteButtonCode)aButtonCode
        isPressed:(BOOL)aIsPressed
fromHardwareWithAttributes:(NSMutableDictionary *)attributes
{
    static BOOL hold;
    hold = (aButtonCode & kHIDRemoteButtonCodeHoldMask) != 0;
    static HIDRemoteButtonCode buttonCode;
    buttonCode = aButtonCode & kHIDRemoteButtonCodeCodeMask;
    static BOOL isPressed;
    isPressed = aIsPressed;
    int keyCode;
    void (^soundEventSend)() = nil;
    switch(buttonCode) {
        case kHIDRemoteButtonCodeCenter:
        case kHIDRemoteButtonCodePlay:
            keyCode = NX_KEYTYPE_PLAY;
            break;
        case kHIDRemoteButtonCodeLeft:
            keyCode = NX_KEYTYPE_REWIND;
            break;
        case kHIDRemoteButtonCodeRight:
            keyCode = NX_KEYTYPE_FAST;
            break;
        case kHIDRemoteButtonCodeUp:
#ifdef DEBUG_REMOTEVOLUME
            //NSLog(@"MagicKeys volume initiating up %d", isPressed);
#endif
            soundEventSend = ^{
#ifdef DEBUG_REMOTEVOLUME
                //NSLog(@"MagicKeys volume sending up %d", isPressed);
#endif
                HIDPostAuxKey(NX_KEYTYPE_SOUND_UP, isPressed);
            };
            break;
        case kHIDRemoteButtonCodeDown:
#ifdef DEBUG_REMOTEVOLUME
            //NSLog(@"MagicKeys volume initiating down %d", isPressed);
#endif
            soundEventSend = ^{
#ifdef DEBUG_REMOTEVOLUME
                //NSLog(@"MagicKeys volume sending down %d", isPressed);
#endif
                HIDPostAuxKey(NX_KEYTYPE_SOUND_DOWN, isPressed);
            };
            break;;
        default:
            // not interested
            return;
    }
    
    if (soundEventSend != nil) {
        if (hold) {
            
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                             0, 0, dispatch_get_current_queue());
            if (timer)
            {
                dispatch_source_set_timer(timer, dispatch_walltime(NULL, 0), 0.1f * NSEC_PER_SEC, 0.01f * NSEC_PER_SEC);
                dispatch_source_set_event_handler(timer, ^{
                    if (isPressed) {
                        // pressed still
                        soundEventSend();
                    } else {
                        dispatch_release(timer);
                    }
                });
                dispatch_resume(timer);
            }
        } else {
            soundEventSend();
        }
        return;
    }

    
    BOOL isRepeat = NO;
    if (hold) {
        isRepeat = YES;
    }
    
    [self simulateKeyPress:keyCode pressed:isPressed repeat:isRepeat];
}

- (void)simulateKeyPress:(int)keyCode pressed:(BOOL)isPressed repeat:(BOOL)isRepeat
{
    // some voodoo here
    NSInteger data = (keyCode << 16) | (isPressed ? (0xA << 8): 0) | (isRepeat ? 0x1 : 0);
    
    NSTimeInterval timestamp = [[NSProcessInfo processInfo] systemUptime];
    NSEvent *event = [NSEvent otherEventWithType:NSSystemDefined location:CGPointMake(0, 0) modifierFlags:0 timestamp:timestamp windowNumber:0 context:0 subtype:SPSystemDefinedEventMediaKeys data1:data data2:0];
    [self handleMediaKeyEvent:[event CGEvent]];
}

- (void) ddhidAppleMikey: (DDHidAppleMikey *) mikey
                   press: (unsigned) usageId
                upOrDown:(BOOL)down
{
    const int kVolumeDown = 141;
    const int kVolumeUp = 140;
    const int kPlayPause = 137;
    
    if (!down) {
        return;
    }
    switch (usageId) {
        case kVolumeDown:
            HIDPostAuxKey(NX_KEYTYPE_SOUND_DOWN, YES);
            HIDPostAuxKey(NX_KEYTYPE_SOUND_DOWN, NO);
            break;
        case kVolumeUp:
            HIDPostAuxKey(NX_KEYTYPE_SOUND_UP, YES);
            HIDPostAuxKey(NX_KEYTYPE_SOUND_UP, NO);
            break;
        case kPlayPause:
            // this is wrong becuase it also launches iTunes
            //HIDPostAuxKey(NX_KEYTYPE_PLAY, YES);
            //HIDPostAuxKey(NX_KEYTYPE_PLAY, NO);

            [self simulateKeyPress:NX_KEYTYPE_PLAY pressed:YES repeat:NO];
            [self simulateKeyPress:NX_KEYTYPE_PLAY pressed:NO repeat:NO];
            break;
    }
}

@end

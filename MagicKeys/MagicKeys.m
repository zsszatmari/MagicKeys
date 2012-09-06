//
//  MagicKeys.m
//  MagicKeys
//
//  Created by Zsolt Szatmari on 7/26/12.
//  Copyright (c) 2012 Treasure Box. All rights reserved.
//

#import <ServiceManagement/SMLoginItem.h>
#import "MagicKeys.h"

static NSString * const kBundle = @"com.treasurebox.magickeys";
static NSString * const kHelperPath = @"Contents/Library/LoginItems/MagicKeys-Agent.app";
static NSString * const kPreferenceKeyNotFirstRun = @"NotFirstRun";

static NSString * const kAppleRemoteKey = @"AppleRemoteEnabled";

@implementation MagicKeys

@synthesize checkForUpdatesButton;
@synthesize updateText;
@synthesize broughtToYouByTreasureBox;
@synthesize copyrightNotice;
@synthesize routingCheckbox;
@synthesize appleRemoteCheckbox;
@synthesize versionLabel;

- (void)mainViewDidLoad
{
    @try {
            
        [versionLabel setStringValue:[NSString stringWithFormat:@"v%@",[self localVersion]]];
        
        BOOL routingEnabled = [self routingEnabled];
        if (![[self defaultsObjectForKey:kPreferenceKeyNotFirstRun] boolValue]) {
            
            [self setDefaultsObject:@YES forKey:kPreferenceKeyNotFirstRun];
            [self setDefaultsObject:@YES forKey:kAppleRemoteKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            [self setRoutingEnabled:YES];
            routingEnabled = YES;
        } else if ([self defaultsObjectForKey:kAppleRemoteKey] == nil) {
            [self setAppleRemoteEnabled:YES];
        }
        
        
        [routingCheckbox setIntValue:routingEnabled];
        [appleRemoteCheckbox setEnabled:routingEnabled];
        
        NSString *treasureText = @"brought to you by Treasure Box";
        NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:treasureText];
        
        NSRange range = [treasureText rangeOfString:@"Treasure Box"];
        if (range.location != NSNotFound) {
            [attributedText setAttributes:@{NSLinkAttributeName: [NSURL URLWithString:@"http://www.treasurebox.hu"]} range:range];
        }
        [[broughtToYouByTreasureBox textStorage] setAttributedString:attributedText];
        [broughtToYouByTreasureBox setFont:[NSFont systemFontOfSize:13.0f]];
        
        NSAttributedString *copyright = [[NSAttributedString alloc] initWithString:@"Copyright notice" attributes:@{NSLinkAttributeName : [NSURL URLWithString:@"http://www.treasurebox.hu"]}];
        [[copyrightNotice textStorage] setAttributedString:copyright];
        [copyrightNotice setDelegate:self];
        
        [self checkForUpdatesPressed:nil];
        
    }
    @catch (NSException *exception) {
        NSLog(@"exception caught: %@, call stack: %@", exception, [exception callStackSymbols]);
    }
}

- (id)defaultsObjectForKey:(NSString *)key
{
    return [[[NSUserDefaults standardUserDefaults] persistentDomainForName:kBundle] objectForKey:key];
}

- (void)setDefaultsObject:(id)object forKey:(NSString *)key
{
    NSMutableDictionary *dictionary = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:kBundle] mutableCopy];
    [dictionary setObject:object forKey:key];
    [[NSUserDefaults standardUserDefaults] setPersistentDomain:dictionary forName:kBundle];
    [dictionary release];
}

- (BOOL)appleRemoteEnabled
{
    return [[self defaultsObjectForKey:kAppleRemoteKey] boolValue];
}

- (void)setAppleRemoteEnabled:(BOOL)value
{
    if (value != [self appleRemoteEnabled]) {
        [self setDefaultsObject:@(value) forKey:kAppleRemoteKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self restartAgentIfRunning];
    }
}

- (BOOL)textView:(NSTextView *)aTextView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex
{
    if (aTextView == copyrightNotice) {
        NSImage *icon = [[[NSImage alloc] initWithContentsOfURL:[[self magicBundle] URLForResource:@"MagicKeys" withExtension:@"png"]] autorelease];
        NSData *creditsData = [NSData dataWithContentsOfURL:[[self magicBundle] URLForResource:@"Credits" withExtension:@"rtf"]];
        NSAttributedString *credits = [[[NSAttributedString alloc] initWithRTF:creditsData documentAttributes:NULL] autorelease];
        
        NSDictionary *dictionary =
            @{@"ApplicationName":@"Magic Keys",
        @"ApplicationIcon":icon,
        @"Version":@"",
        @"ApplicationVersion":[self localVersion],
        @"Credits":credits};
        [[NSApplication sharedApplication] orderFrontStandardAboutPanelWithOptions:dictionary];
        return YES;
    }
        
    return NO;
}

- (IBAction)toggleRouting:(id)sender {
    [self setRoutingEnabled:[routingCheckbox intValue]];
    [appleRemoteCheckbox setEnabled:[routingCheckbox intValue]];
}

- (IBAction)toggleAppleRemote:(id)sender {
    [self setAppleRemoteEnabled:[appleRemoteCheckbox intValue]];
}

- (BOOL)routingEnabled
{
    BOOL ret = [self searchForAgentAndRemove:NO];
    if (ret) {
        [self startAgentIfNotRunning];
    }
    return ret;
}

- (void)setRoutingEnabled:(BOOL)aRoutingEnabled
{
    [self registerAgent:aRoutingEnabled];
}

- (BOOL)searchForAgentAndRemove:(BOOL)remove
{
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItems == NULL) {
        NSLog(@"can't retrieve login items list");
        return NO;
    }
    
    NSString *appPath = [self agentPath];
    
    UInt32 seedValue;
    //Retrieve the list of Login Items and cast them to
    // a NSArray so that it will be easier to iterate
    BOOL found = NO;
    
    CFArrayRef loginItemsArrayCf = LSSharedFileListCopySnapshot(loginItems, &seedValue);
    NSArray  *loginItemsArray = (NSArray *)loginItemsArrayCf;
    for(int i = 0; i< [loginItemsArray count]; i++){
        LSSharedFileListItemRef itemRef = (LSSharedFileListItemRef)[loginItemsArray objectAtIndex:i];
        //Resolve the item with URL
        CFURLRef url;
        if (LSSharedFileListItemResolve(itemRef, 0, &url, NULL) == noErr) {
            NSString * urlPath = [(NSURL*)CFBridgingRelease(url) path];
            if ([urlPath compare:appPath] == NSOrderedSame){
                found = YES;
                if (remove) {
                    LSSharedFileListItemRemove(loginItems,itemRef);
                }
            }
        }
    }
    CFRelease(loginItemsArrayCf);
    
    CFRelease(loginItems);
    return found;
}

- (NSBundle *)magicBundle
{
    return [NSBundle bundleWithIdentifier:kBundle];
}

- (NSString *)agentPath
{
    NSString *path = [[[self magicBundle] bundlePath] stringByAppendingPathComponent: kHelperPath];
    
    return path;
}

- (void)startAgent
{
    NSString *path = [self agentPath];
    NSURL *url = [NSURL fileURLWithPath:path];
    OSStatus err = LSOpenCFURLRef((CFURLRef)url, NULL);
    if (err != noErr) {
        NSLog(@"couldn't start agent: %d", (int)err);
    }
}

- (void)stopAgent
{
    NSString *path = [self agentPath];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle.bundleIdentifier]) {
        
        [app forceTerminate];
    }
}

- (void)restartAgentIfRunning
{
    NSString *path = [self agentPath];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle.bundleIdentifier]) {
        
        [app forceTerminate];
        [self startAgent];
        break;
    }
}

- (void)startAgentIfNotRunning
{
    NSString *path = [self agentPath];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    if ([[NSRunningApplication runningApplicationsWithBundleIdentifier:bundle.bundleIdentifier] count] == 0) {
        
        [self startAgent];
    }
}

- (void)registerAgent:(BOOL)enabled
{
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItems == NULL) {
        NSLog(@"can't retrieve login items list");
        return;
    }
    
    NSString *path = [self agentPath];
    NSURL *url = [NSURL fileURLWithPath:path];
    
    if (enabled) {
        //Insert an item to the list.
		LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems,
                                                                     kLSSharedFileListItemLast, ( CFStringRef)@"Magic Keys", NULL,
                                                                     (CFURLRef)url, NULL, NULL);
        if (item != NULL) {
            NSLog(@"successfully added item");
            CFRelease(item);
        } else {
            NSLog(@"can't insert item: %@", url);
        }
        
        [self startAgent];
        
    } else {
        
        [self searchForAgentAndRemove:YES];
        [self stopAgent];
    }
}

- (NSString *)localVersion
{
    return [[self magicBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
}

- (IBAction)checkForUpdatesPressed:(id)sender {
    
    [checkForUpdatesButton setEnabled:NO];
    [[[updateText textStorage] mutableString] setString:@"Checking for updates..."];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        NSError *err = nil;
        NSHTTPURLResponse *response;
        NSURLRequest *request = [[[NSURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://www.treasurebox.hu/magickeys/version.txt"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15.0f] autorelease];
        NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&err];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [checkForUpdatesButton setEnabled:YES];
            
            if (err != nil || [response statusCode] != 200) {
                
                [[[updateText textStorage] mutableString] setString:@"Check for updates failed"];
                NSLog(@"check for updates failed: %@, %ld", err, (long)[response statusCode]);
            } else {
                
                NSString *contents = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
                NSString *version = [[contents componentsSeparatedByString:@"\n"] objectAtIndex:0];
                NSString *localVersion = [self localVersion];
                
                if ([version isEqualToString:localVersion]) {
                    [[[updateText textStorage] mutableString] setString:@"Magic Keys is up to date"];
                } else {
                    NSString *text = @"There is a new version available, please get it for better functionality";
                    NSMutableAttributedString *attributedText = [[[NSMutableAttributedString alloc] initWithString:text] autorelease];
                    
                    NSRange range = [text rangeOfString:@"get it"];
                    if (range.location != NSNotFound) {
                        [attributedText setAttributes:@{NSLinkAttributeName: [NSURL URLWithString:@"http://www.treasurebox.hu/magickeys"]} range:range];
                    }
                    [[updateText textStorage] setAttributedString:attributedText];
                }
            }
        });
    });
}


@end

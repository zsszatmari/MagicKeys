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



@implementation MagicKeys

@synthesize checkForUpdatesButton;
@synthesize updateText;
@synthesize broughtToYouByTreasureBox;
@synthesize routingCheckbox;

- (void)mainViewDidLoad
{
    @try {
            
        BOOL routingEnabled = [self routingEnabled];
        if (![[[[NSUserDefaults standardUserDefaults] persistentDomainForName:kBundle] objectForKey:kPreferenceKeyNotFirstRun] boolValue]) {
            
            [self setRoutingEnabled:YES];
            [[NSUserDefaults standardUserDefaults] setPersistentDomain:@{ kPreferenceKeyNotFirstRun : @YES } forName:kBundle];
            routingEnabled = YES;
        }
        
        [routingCheckbox setIntValue:routingEnabled];
        
        
        NSString *treasureText = @"brought to you by Treasure Box";
        NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:treasureText];
        
        NSRange range = [treasureText rangeOfString:@"Treasure Box"];
        if (range.location != NSNotFound) {
            [attributedText setAttributes:@{NSLinkAttributeName: [NSURL URLWithString:@"http://www.treasurebox.hu"]} range:range];
        }
        [[broughtToYouByTreasureBox textStorage] setAttributedString:attributedText];
        [broughtToYouByTreasureBox setFont:[NSFont systemFontOfSize:13.0f]];

        [self checkForUpdatesPressed:nil];
        
    }
    @catch (NSException *exception) {
        NSLog(@"exception caught: %@, call stack: %@", exception, [exception callStackSymbols]);
    }
}

- (IBAction)toggleRouting:(id)sender {
    [self setRoutingEnabled:[routingCheckbox intValue]];
}

- (BOOL)routingEnabled
{
    return [self searchForAgentAndRemove:NO];
}

- (void)setRoutingEnabled:(BOOL)routingEnabled
{
    [self registerAgent:routingEnabled];
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
        
        OSStatus err = LSOpenCFURLRef((CFURLRef)url, NULL);
        if (err != noErr) {
            NSLog(@"couldn't start agent: %d", (int)err);
        }
        
        
    } else {
        
        [self searchForAgentAndRemove:YES];
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle.bundleIdentifier]) {
            
            [app forceTerminate];
        }
    }
}

- (IBAction)checkForUpdatesPressed:(id)sender {
    
    [checkForUpdatesButton setEnabled:NO];
    [[[updateText textStorage] mutableString] setString:@"Checking for updates..."];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        NSError *err;
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
                NSString *localVersion = [[self magicBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
                
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

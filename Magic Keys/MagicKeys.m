//
//  G_Keys.m
//  G-Keys
//
//  Created by Zsolt Szatmari on 7/1/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <ServiceManagement/SMLoginItem.h>
#import "MagicKeys.h"

static NSString * const kBundle = @"com.treasurebox.magickeys";
static NSString * const kRoutingKey = @"routingEnabled";

static NSString * const kHelper = @"MagicKeys-Agent";

@implementation MagicKeys

- (void)mainViewDidLoad
{
    [self registerAgent:[self routingEnabled]];
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
    NSArray  *loginItemsArray = (NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
    for(int i = 0; i< [loginItemsArray count]; i++){
        LSSharedFileListItemRef itemRef = (LSSharedFileListItemRef)[loginItemsArray
                                                                    objectAtIndex:i];
        //Resolve the item with URL
        CFURLRef url;
        if (LSSharedFileListItemResolve(itemRef, 0, &url, NULL) == noErr) {
            NSString * urlPath = [(NSURL*)url path];
            if ([urlPath compare:appPath] == NSOrderedSame){
                found = YES;
                if (remove) {
                    LSSharedFileListItemRemove(loginItems,itemRef);
                }
            }
        }
    }
    [loginItemsArray release];
    
    CFRelease(loginItems);
    return found;
}

- (NSString *)agentPath
{
    NSBundle *mainBundle = [NSBundle bundleWithIdentifier:kBundle];
    NSString *path = [[mainBundle bundlePath] stringByAppendingPathComponent: @"Contents/Library/MagicKeys/G-Keys-Agent.app"];
    
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
                                                                     kLSSharedFileListItemLast, ( CFStringRef)@"G-Keys", NULL,
                                                                     ( CFURLRef)url, NULL, NULL);
        if (item != NULL) {
            NSLog(@"successfully added item");
            CFRelease(item);
        } else {
            NSLog(@"can't insert item");
        }
        
        OSStatus err = LSOpenCFURLRef(( CFURLRef)url, NULL);
        if (err != noErr) {
            NSLog(@"couldn't start agent: %d", err);
        }
        
        
    } else {
        
        [self searchForAgentAndRemove:YES];
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle.bundleIdentifier]) {
            
            [app forceTerminate];
        }
    }
}

@end

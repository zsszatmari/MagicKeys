//
//  main.m
//  MagicKeys-Agent
//
//  Created by Zsolt Szatmari on 7/28/12.
//  Copyright (c) 2012 Treasure Box. All rights reserved.
//


#import <Cocoa/Cocoa.h>
#import "SPMediaKeyTap.h"

int main(int argc, char *argv[])
{
    @autoreleasepool {
        
        // Register defaults for the whitelist of apps that want to use media keys
        [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                 [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers], kMediaKeyUsingBundleIdentifiersDefaultsKey,
                                                                 nil]];
        
        
        SPMediaKeyTap *keyTap = [[SPMediaKeyTap alloc] initWithDelegate:nil];
        if([SPMediaKeyTap usesGlobalMediaKeyTap])
            [keyTap startWatchingMediaKeys];
        
        CFRunLoopRun();
        [keyTap release];
    }
    return 0;
}

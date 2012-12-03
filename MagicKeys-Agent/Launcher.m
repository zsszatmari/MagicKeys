//
//  Launcher.m
//  MagicKeys
//
//  Created by Zsolt Szatmári on 12/3/12.
//  Copyright (c) 2012 Treasure Box. All rights reserved.
//

#import "Launcher.h"

@implementation Launcher

- (NSURL *)applicationPath
{
    return [NSURL fileURLWithPath:@"/Applications/G-Ear.app"];
}

- (NSString *)applicationBundleId
{
    return [[NSBundle bundleWithURL:[self applicationPath]] bundleIdentifier];
}

- (BOOL)isRunning:(NSString *)bundleId
{
    ProcessSerialNumber psn = { kNoProcess, kNoProcess };
    while (GetNextProcess(&psn) == noErr) {
        CFDictionaryRef cfDict = ProcessInformationCopyDictionary(&psn,  kProcessDictionaryIncludeAllInformationMask);
        if (cfDict) {
            NSDictionary *dict = (NSDictionary *)cfDict;
            NSString *foundBundle = [dict objectForKey:(NSString *)kCFBundleIdentifierKey];
            BOOL found = NO;
            if ([foundBundle isEqualToString:bundleId]) {
                found = YES;
            }
            CFRelease(cfDict);
            if (found) {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)launchIfNeeded
{
    NSString *bundleId = [self applicationBundleId];
    if (bundleId == nil) {
        return NO;
    }
    if ([self isRunning:bundleId]) {
        return NO;
    }
    [[NSWorkspace sharedWorkspace] launchApplicationAtURL:[self applicationPath] options:NSWorkspaceLaunchAsync configuration:nil error:nil];
    return YES;
}


+ (BOOL)launchIfNeeded
{
    Launcher *launcher = [[[Launcher alloc] init] autorelease];
   // NSArray *urls;
   // _LSCopyAllApplicationURLs(&urls);

    return [launcher launchIfNeeded];
}

@end


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

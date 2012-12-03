//
//  Launcher.h
//  MagicKeys
//
//  Created by Zsolt Szatmári on 12/3/12.
//  Copyright (c) 2012 Treasure Box. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Launcher : NSObject

// returns YES if we handled the event
+ (BOOL)launchIfNeeded;

@end

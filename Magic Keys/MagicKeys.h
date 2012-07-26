//
//  G_Keys.h
//  G-Keys
//
//  Created by Zsolt Szatmari on 7/1/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <PreferencePanes/PreferencePanes.h>

@interface MagicKeys : NSPreferencePane

@property (readwrite) BOOL routingEnabled;

- (void)mainViewDidLoad;

@end

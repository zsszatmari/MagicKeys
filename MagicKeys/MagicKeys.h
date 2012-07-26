//
//  MagicKeys.h
//  MagicKeys
//
//  Created by Zsolt Szatmari on 7/26/12.
//  Copyright (c) 2012 Treasure Box. All rights reserved.
//

#import <PreferencePanes/PreferencePanes.h>

@interface MagicKeys : NSPreferencePane
@property (assign) IBOutlet NSButton *checkForUpdatesButton;
@property (assign) IBOutlet NSTextView *updateText;
@property (assign) IBOutlet NSTextView *broughtToYouByTreasureBox;


- (IBAction)checkForUpdatesPressed:(id)sender;
- (void)mainViewDidLoad;

@end

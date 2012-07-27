//
//  MagicKeys.h
//  MagicKeys
//
//  Created by Zsolt Szatmari on 7/26/12.
//  Copyright (c) 2012 Treasure Box. All rights reserved.
//

#import <PreferencePanes/PreferencePanes.h>

@interface MagicKeys : NSPreferencePane {
    NSButton *__strong checkForUpdatesButton;
    NSTextView *__strong updateText;
    NSTextView *__strong broughtToYouByTreasureBox;
}

@property (strong) IBOutlet NSButton *checkForUpdatesButton;
@property (strong) IBOutlet NSTextView *updateText;
@property (strong) IBOutlet NSTextView *broughtToYouByTreasureBox;


- (IBAction)checkForUpdatesPressed:(id)sender;
- (void)mainViewDidLoad;

@end

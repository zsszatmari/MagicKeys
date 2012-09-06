//
//  MagicKeys.h
//  MagicKeys
//
//  Created by Zsolt Szatmari on 7/26/12.
//  Copyright (c) 2012 Treasure Box. All rights reserved.
//

#import <PreferencePanes/PreferencePanes.h>

@interface MagicKeys : NSPreferencePane<NSTextViewDelegate> {
    // needed for 32-bit compile, which is needed if some old prefpane makes system preferences switch to compatibility mode
    NSButton *checkForUpdatesButton;
    NSTextView *updateText;
    NSTextView *broughtToYouByTreasureBox;
    NSButton *routingCheckbox;
}

@property (strong) IBOutlet NSButton *checkForUpdatesButton;
@property (strong) IBOutlet NSTextView *updateText;
@property (strong) IBOutlet NSTextView *broughtToYouByTreasureBox;
@property (assign) IBOutlet NSTextView *copyrightNotice;
@property (weak) IBOutlet NSButton *routingCheckbox;
@property (assign) IBOutlet NSButton *appleRemoteCheckbox;
@property (assign) IBOutlet NSTextField *versionLabel;


- (IBAction)checkForUpdatesPressed:(id)sender;
- (IBAction)toggleRouting:(id)sender;
- (IBAction)toggleAppleRemote:(id)sender;
- (void)mainViewDidLoad;

@end

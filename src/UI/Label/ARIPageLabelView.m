//
// Created by ren7995 on 2023-05-30 18:33:23
// Copyright (c) 2023 ren7995. All rights reserved.
//

#import "ARIPageLabelView.h"
#import "../../Manager/ARITweakManager.h"

@implementation ARIPageLabelView

- (NSString *)loadRawText {
    SBIconListView *superv = (SBIconListView *)self.superview;
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    NSString *text = [manager rawValueForKey:@"pageLabelText" forListView:superv];
    if(text) return text;
    return [NSString stringWithFormat:@"Page %d", (int)[manager indexOfListView:superv] + 1];
}

- (void)saveTextValue:(NSString *)text {
    [[ARITweakManager sharedInstance] setValue:text forKey:@"pageLabelText" forListView:(SBIconListView *)self.superview];
}

@end

//
// Created by ren7995 on 2021-04-25 15:48:29
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../../Shared/ARIPathUtils.h"
#import "../Manager/ARITweakManager.h"
#import "../Manager/ARIEditManager.h"
#import "../UI/Label/ARILabelView.h"
#include <dlfcn.h>

static __weak UIResponder *ARIActiveFirstResponder = nil;

@interface UIResponder (ARIACTiveFirstResponderLookup)
- (void)_atriaCaptureActiveFirstResponder:(id)sender;
@end

@implementation UIResponder (ARIACTiveFirstResponderLookup)
- (void)_atriaCaptureActiveFirstResponder:(id)sender {
    ARIActiveFirstResponder = self;
}
@end

static BOOL ARIPageLabelIsBeingEdited(void) {
    ARIActiveFirstResponder = nil;
    [[UIApplication sharedApplication] sendAction:@selector(_atriaCaptureActiveFirstResponder:)
                                               to:nil
                                             from:nil
                                         forEvent:nil];

    UIView *view = [ARIActiveFirstResponder isKindOfClass:[UIView class]] ? (UIView *)ARIActiveFirstResponder : nil;
    while(view) {
        if([view isKindOfClass:[ARILabelView class]]) return YES;
        view = view.superview;
    }
    return NO;
}

static void ARICloseEditor(void) {
    [[ARIEditManager sharedInstance] toggleEditView:NO withTargetLocation:nil];
}


%group LegacyIconControllerLifecycle

%hook SBIconController 

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    ARICloseEditor();
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    ARICloseEditor();
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id)coordinator {
    %orig;
    ARICloseEditor();
}

%end
%end


%group RootFolderControllerLifecycle

%hook SBRootFolderController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    ARICloseEditor();
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    ARICloseEditor();
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id)coordinator {
    %orig;
    ARICloseEditor();
}

%end
%end


%hook SBMainSwitcherWindow

- (void)setHidden:(BOOL)arg {
    %orig;
    ARICloseEditor();
}

%end


%hook SBIconScrollView

- (void)scrollRectToVisible:(CGRect)rect animated:(BOOL)animated {
    // Suppress the keyboard-driven jump only while Atria's page label is the
    // active editor. Other SpringBoard scrolling and accessibility requests
    // must retain the system behavior.
    if(ARIPageLabelIsBeingEdited()) return;
    %orig(rect, animated);
}

%end


%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;
    [[ARITweakManager sharedInstance] onSpringboardLaunched];
}

%end


%group TodayViewFixiPad
%hook SBTodayViewController

// These next two hooked methods fix label bugging on iPad with today view

- (void)viewWillAppear:(BOOL)arg1 {
    %orig;
    [[NSNotificationCenter defaultCenter]
            postNotificationName:ARIUpdateLabelVisibilityNotification
                          object:nil
                        userInfo:@{@"alpha" : @(0.0F), @"animationDuration" : @(0.3F)}];
}

- (void)viewDidDisappear:(BOOL)arg1 {
    %orig;
    [[NSNotificationCenter defaultCenter]
            postNotificationName:ARIUpdateLabelVisibilityNotification
                          object:nil
                        userInfo:@{@"alpha" : @(1.0F), @"animationDuration" : @(0.3F)}];
}

%end
%end

%group ZenithFix
%hook SBIconListModel

// Prevents a crash seeimingly caused by an interaction between Atria and Zenith.
// Zenith attempts to insert icons in a way that doesn't work with modified layout, leading to an exception.

- (id)insertIcons:(id)arg1 atIndex:(NSUInteger)arg2 options:(NSUInteger)arg3 {
    // Amazing..
	@try {
		return %orig;
	} @catch(NSException *exc) {
		return nil;
	}
}

// Fix for a crash with Zenith that occurs when its installed on its own (related to App Library).
// When -[SBHLibraryCategory updateCategoryWithIcons:] is invoked, it calls this method.

- (id)insertIcon:(id)arg1 atIndex:(NSUInteger)arg2 {
	@try {
		return %orig;
	} @catch(NSException *exc) {
		return nil;
	}
}

%end
%end

%ctor {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
	if([manager isEnabled]) {
		NSLog(@"[Atria]: Loading hooks from %s", __FILE__);
		%init();

        if(NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 17) {
            %init(RootFolderControllerLifecycle);
        } else {
            %init(LegacyIconControllerLifecycle);
        }

        if([manager isDeviceIPad]) {
            %init(TodayViewFixiPad);
        }

        // Zenith compatibility
        NSString *const zenithPath = ARIMobileSubstrateDylibPath(@"Zenith");
        if(zenithPath.length > 0) {
            dlopen([zenithPath UTF8String], RTLD_NOW);
            %init(ZenithFix);
        }
	}
}

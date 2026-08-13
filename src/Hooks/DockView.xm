//
// Created by ren7995 on 2021-04-25 12:49:45
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

@interface SBFloatingDockPlatterView : UIView
@property (nonatomic, strong) UIView *backgroundView;
@end

static __weak SBFloatingDockController *fdController;
static BOOL ARIHasNativeFloatingDockSupportSelector = NO;
static BOOL ARIHasNativeDockBackgroundAlphaSelector = NO;

typedef struct {
    NSUInteger size;
    const char *encoding;
} ARIDockABIType;

#define ARI_DOCK_ABI_TYPE(type) ((ARIDockABIType) { sizeof(type), @encode(type) })

static const char *ARIDockUnqualifiedTypeEncoding(const char *encoding) {
    while(encoding && *encoding && strchr("rnNoORV", *encoding)) encoding++;
    return encoding;
}

static BOOL ARIDockTypeMatches(const char *actualEncoding,
                               ARIDockABIType expected) {
    const char *actual = ARIDockUnqualifiedTypeEncoding(actualEncoding);
    const char *wanted = ARIDockUnqualifiedTypeEncoding(expected.encoding);
    if(!actual || !wanted || !*actual || !*wanted || *actual != *wanted)
        return NO;
    if(*wanted == 'v') return expected.size == 0;
	// These Dock gates currently accept only plain Objective-C object
	// parameters. Do not treat Class (#), blocks (@?), or another future
	// object-family encoding as interchangeable merely because pointer sizes
	// happen to match.
	if(*wanted == '@') {
		BOOL actualIsObject = actual[1] == '\0' || actual[1] == '"';
		if(wanted[1] != '\0' || !actualIsObject) return NO;
	}

    NSUInteger actualSize = 0;
    NSGetSizeAndAlignment(actual, &actualSize, NULL);
    return actualSize == expected.size;
}

static BOOL ARIDockMethodMatchesABI(Class cls, SEL selector, BOOL classMethod,
                                    ARIDockABIType expectedReturnType,
                                    const ARIDockABIType *explicitArguments,
                                    NSUInteger explicitArgumentCount) {
    if(!cls || !selector) return NO;
    Method method = classMethod
        ? class_getClassMethod(cls, selector)
        : class_getInstanceMethod(cls, selector);
    if(!method || method_getNumberOfArguments(method) != explicitArgumentCount + 2)
        return NO;

    char *returnType = method_copyReturnType(method);
    BOOL matches = ARIDockTypeMatches(returnType, expectedReturnType);
    free(returnType);
    if(!matches) return NO;

    for(NSUInteger index = 0; index < explicitArgumentCount; index++) {
        char *argumentType = method_copyArgumentType(method, (unsigned int)index + 2);
        matches = ARIDockTypeMatches(argumentType, explicitArguments[index]);
        free(argumentType);
        if(!matches) return NO;
    }
    return YES;
}

static id ARIDockSafeValueForKey(id object, NSString *key) {
    if(!object || !key.length) return nil;
    @try {
        return [object valueForKey:key];
    } @catch(__unused NSException *exception) {
        return nil;
    }
}

static id ARICaptureFloatingDockController(id controller) {
    if([controller isKindOfClass:objc_getClass("SBFloatingDockController")]) {
        fdController = controller;
    }
    return controller;
}

%hook SBDockView

%new
- (void)_atriaUpdateDockForSettingsChanged {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    CGFloat alpha = [manager floatValueForKey:@"dock_bg"];
    if(ARIHasNativeDockBackgroundAlphaSelector) {
        [self setBackgroundAlpha:alpha];
        return;
    }
    UIView *backgroundView = ARIDockSafeValueForKey(self, @"backgroundView");
    if([backgroundView isKindOfClass:[UIView class]]) backgroundView.layer.opacity = alpha;
}

// UIKit lifecycle ABI; retained in the common hook group.
- (void)traitCollectionDidChange:(UITraitCollection *)old {
    %orig(old);
    // Re-apply on the next main-loop turn, after the system has rebuilt its
    // material. Keep this on Atria's void helper instead of assuming the
    // private scalar setter still exists on a future SpringBoard.
    __weak SBDockView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf _atriaUpdateDockForSettingsChanged];
    });
}

%end


%group ARIDockHeightHook
%hook SBDockView

- (CGFloat)dockHeight {
    if([[ARITweakManager sharedInstance] boolValueForKey:@"disableDock"])
        return 0;
    return %orig;
}

%end
%end


%group ARIDockBackgroundAlphaHook
%hook SBDockView

// Override background alpha
- (void)setBackgroundAlpha:(CGFloat)alpha {
    if([[ARITweakManager sharedInstance] boolValueForKey:@"disableDock"]) {
        %orig(0);
        return;
    }
    %orig([[ARITweakManager sharedInstance] floatValueForKey:@"dock_bg"]);
}

%end
%end


%hook SBFloatingDockController

%new
+ (SBFloatingDockController *)_atriaSharedInstance {
    return fdController;
}

%end


%group ARIFloatingDockGestureHook
%hook SBFloatingDockController

- (BOOL)isGesturePossible {
    if([[ARITweakManager sharedInstance] boolValueForKey:@"disableFloatingDockGestures"]) return NO;
    return %orig;
}

%end
%end


%group ARIFloatingDockSupportHook
%hook SBFloatingDockController

+ (BOOL)isFloatingDockSupported {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    if([manager boolValueForKey:@"forceFloatingDock"] && ![manager boolValueForKey:@"disableDock"]) {
        return YES;
    }
    return ARIHasNativeFloatingDockSupportSelector ? %orig : NO;
}

%end
%end


%group FloatingDockControllerLegacyInitializer
%hook SBFloatingDockController

- (id)initWithIconController:(id)iconController {
    return ARICaptureFloatingDockController(%orig(iconController));
}

%end
%end


%group FloatingDockControllerSceneIconInitializer
%hook SBFloatingDockController

- (id)initWithWindowScene:(id)windowScene iconController:(id)iconController {
    return ARICaptureFloatingDockController(%orig(windowScene, iconController));
}

%end
%end


%group FloatingDockControllerSceneContextInitializer
%hook SBFloatingDockController

// iOS 26+
- (id)initWithWindowScene:(id)windowScene homeScreenContextProvider:(id)provider {
    return ARICaptureFloatingDockController(%orig(windowScene, provider));
}

%end
%end


%group ARIFloatingDockDefaultsHooks
%hook SBFloatingDockDefaults

- (BOOL)recentsEnabled {
    return [[ARITweakManager sharedInstance] boolValueForKey:@"floatingDockRecents"];
}

- (BOOL)appLibraryEnabled {
    return [[ARITweakManager sharedInstance] boolValueForKey:@"floatingDockAppLibrary"];
}

%end
%end

%group FloatingDockSuggestionsLegacyInitializer
%hook SBFloatingDockSuggestionsModel

// iOS 13-15
- (id)initWithMaximumNumberOfSuggestions:(NSUInteger)arg1
                          iconController:(id)arg2
                       recentsController:(id)arg3
                        recentsDataStore:(id)arg4
                         recentsDefaults:(id)arg5
                    floatingDockDefaults:(id)arg6
                    appSuggestionManager:(id)arg7
                         analyticsClient:(id)arg8
                   applicationController:(id)arg9 {
    NSUInteger maxRecents = [[ARITweakManager sharedInstance] intValueForKey:@"maxFloatingDockRecents"];
    return %orig(maxRecents, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9);
}

%end
%end


%group FloatingDockSuggestionsSceneInitializer
%hook SBFloatingDockSuggestionsModel

// iOS 16
- (id)initWithMaximumNumberOfSuggestions:(NSUInteger)arg1
                          iconController:(id)arg2 
                       recentsController:(id)arg3 
                        recentsDataStore:(id)arg4 
                         recentsDefaults:(id)arg5 
                    floatingDockDefaults:(id)arg6 
                    appSuggestionManager:(id)arg7 
                   applicationController:(id)arg8 {
    NSUInteger maxRecents = [[ARITweakManager sharedInstance] intValueForKey:@"maxFloatingDockRecents"];
    return %orig(maxRecents, arg2, arg3, arg4, arg5, arg6, arg7, arg8);
}

%end
%end


%group FloatingDockSuggestionsContextInitializer
%hook SBFloatingDockSuggestionsModel

// iOS 26+
- (id)initWithMaximumNumberOfSuggestions:(NSUInteger)arg1
               homeScreenContextProvider:(id)arg2
                        recentsController:(id)arg3
                         recentsDataStore:(id)arg4
                          recentsDefaults:(id)arg5
                     floatingDockDefaults:(id)arg6
                     appSuggestionManager:(id)arg7
                    applicationController:(id)arg8 {
    NSUInteger maxRecents = [[ARITweakManager sharedInstance] intValueForKey:@"maxFloatingDockRecents"];
    return %orig(maxRecents, arg2, arg3, arg4, arg5, arg6, arg7, arg8);
}

%end
%end


%hook SBFloatingDockView

%new
- (void)_atriaUpdateDockForSettingsChanged {
    UIView *backgroundView = ARIDockSafeValueForKey(self, @"backgroundView");
    if(![backgroundView isKindOfClass:[UIView class]]) {
        id mainPlatterView = ARIDockSafeValueForKey(self, @"mainPlatterView");
        backgroundView = ARIDockSafeValueForKey(mainPlatterView, @"backgroundView");
    }
    if([backgroundView isKindOfClass:[UIView class]]) {
        backgroundView.layer.opacity = [[ARITweakManager sharedInstance] floatValueForKey:@"dock_bg"];
    }
}

- (void)didMoveToSuperview {
    %orig;
    [self _atriaUpdateDockForSettingsChanged];
}

- (void)traitCollectionDidChange:(UITraitCollection *)old {
    %orig(old);
    [self performSelector:@selector(_atriaUpdateDockForSettingsChanged) withObject:nil afterDelay:0.0];
}

%end


%group FloatingDockPlatterBackgroundHook
%hook SBFloatingDockPlatterView

- (void)setBackgroundView:(UIView *)arg1 {
    arg1.layer.opacity = [[ARITweakManager sharedInstance] floatValueForKey:@"dock_bg"];
    %orig(arg1);
}

%end
%end


%ctor {
	if([[ARITweakManager sharedInstance] isEnabled]) {
		NSLog(@"[Atria]: Loading hooks from %s", __FILE__);
			Class floatingDockControllerClass = objc_getClass("SBFloatingDockController");
			Class floatingDockSuggestionsClass = objc_getClass("SBFloatingDockSuggestionsModel");
			Class floatingDockPlatterClass = objc_getClass("SBFloatingDockPlatterView");
			Class dockViewClass = objc_getClass("SBDockView");
				const ARIDockABIType oneObjectArgument[] = {
					ARI_DOCK_ABI_TYPE(id)
				};
				const ARIDockABIType twoObjectArguments[] = {
					ARI_DOCK_ABI_TYPE(id), ARI_DOCK_ABI_TYPE(id)
				};
				const ARIDockABIType oneCGFloatArgument[] = {
					ARI_DOCK_ABI_TYPE(CGFloat)
				};
				ARIHasNativeFloatingDockSupportSelector =
					ARIDockMethodMatchesABI(
						floatingDockControllerClass, @selector(isFloatingDockSupported), YES,
						ARI_DOCK_ABI_TYPE(BOOL), NULL, 0);
				ARIHasNativeDockBackgroundAlphaSelector =
					ARIDockMethodMatchesABI(
						dockViewClass, @selector(setBackgroundAlpha:), NO,
						(ARIDockABIType) { 0, @encode(void) }, oneCGFloatArgument, 1);
				%init();

				if(ARIDockMethodMatchesABI(
						dockViewClass, @selector(dockHeight), NO,
						ARI_DOCK_ABI_TYPE(CGFloat), NULL, 0)) {
					%init(ARIDockHeightHook);
				}
				if(ARIHasNativeDockBackgroundAlphaSelector) {
					%init(ARIDockBackgroundAlphaHook);
				}
				if(ARIDockMethodMatchesABI(
						floatingDockControllerClass, @selector(isGesturePossible), NO,
						ARI_DOCK_ABI_TYPE(BOOL), NULL, 0)) {
					%init(ARIFloatingDockGestureHook);
				}
				if(ARIHasNativeFloatingDockSupportSelector) {
					%init(ARIFloatingDockSupportHook);
				}
				Class floatingDockDefaultsClass = objc_getClass("SBFloatingDockDefaults");
				if(ARIDockMethodMatchesABI(
						floatingDockDefaultsClass, @selector(recentsEnabled), NO,
						ARI_DOCK_ABI_TYPE(BOOL), NULL, 0) &&
				   ARIDockMethodMatchesABI(
						floatingDockDefaultsClass, @selector(appLibraryEnabled), NO,
						ARI_DOCK_ABI_TYPE(BOOL), NULL, 0)) {
					%init(ARIFloatingDockDefaultsHooks);
				}

				if(ARIDockMethodMatchesABI(
						floatingDockControllerClass, @selector(initWithIconController:), NO,
						ARI_DOCK_ABI_TYPE(id), oneObjectArgument, 1)) {
					%init(FloatingDockControllerLegacyInitializer);
				}
				if(ARIDockMethodMatchesABI(
						floatingDockControllerClass, @selector(initWithWindowScene:iconController:), NO,
						ARI_DOCK_ABI_TYPE(id), twoObjectArguments, 2)) {
					%init(FloatingDockControllerSceneIconInitializer);
				}
				if(ARIDockMethodMatchesABI(
						floatingDockControllerClass, @selector(initWithWindowScene:homeScreenContextProvider:), NO,
						ARI_DOCK_ABI_TYPE(id), twoObjectArguments, 2)) {
					%init(FloatingDockControllerSceneContextInitializer);
				}

				SEL legacySuggestionsSelector = @selector(initWithMaximumNumberOfSuggestions:iconController:recentsController:recentsDataStore:recentsDefaults:floatingDockDefaults:appSuggestionManager:analyticsClient:applicationController:);
				SEL sceneSuggestionsSelector = @selector(initWithMaximumNumberOfSuggestions:iconController:recentsController:recentsDataStore:recentsDefaults:floatingDockDefaults:appSuggestionManager:applicationController:);
				SEL contextSuggestionsSelector = @selector(initWithMaximumNumberOfSuggestions:homeScreenContextProvider:recentsController:recentsDataStore:recentsDefaults:floatingDockDefaults:appSuggestionManager:applicationController:);
				const ARIDockABIType legacySuggestionArguments[] = {
					ARI_DOCK_ABI_TYPE(NSUInteger), ARI_DOCK_ABI_TYPE(id),
					ARI_DOCK_ABI_TYPE(id), ARI_DOCK_ABI_TYPE(id),
					ARI_DOCK_ABI_TYPE(id), ARI_DOCK_ABI_TYPE(id),
					ARI_DOCK_ABI_TYPE(id), ARI_DOCK_ABI_TYPE(id),
					ARI_DOCK_ABI_TYPE(id)
				};
				const ARIDockABIType modernSuggestionArguments[] = {
					ARI_DOCK_ABI_TYPE(NSUInteger), ARI_DOCK_ABI_TYPE(id),
					ARI_DOCK_ABI_TYPE(id), ARI_DOCK_ABI_TYPE(id),
					ARI_DOCK_ABI_TYPE(id), ARI_DOCK_ABI_TYPE(id),
					ARI_DOCK_ABI_TYPE(id), ARI_DOCK_ABI_TYPE(id)
				};
				if(ARIDockMethodMatchesABI(
						floatingDockSuggestionsClass, legacySuggestionsSelector, NO,
						ARI_DOCK_ABI_TYPE(id), legacySuggestionArguments, 9)) {
					%init(FloatingDockSuggestionsLegacyInitializer);
				}
				if(ARIDockMethodMatchesABI(
						floatingDockSuggestionsClass, sceneSuggestionsSelector, NO,
						ARI_DOCK_ABI_TYPE(id), modernSuggestionArguments, 8)) {
					%init(FloatingDockSuggestionsSceneInitializer);
				}
				if(ARIDockMethodMatchesABI(
						floatingDockSuggestionsClass, contextSuggestionsSelector, NO,
						ARI_DOCK_ABI_TYPE(id), modernSuggestionArguments, 8)) {
					%init(FloatingDockSuggestionsContextInitializer);
				}
				if(ARIDockMethodMatchesABI(
						floatingDockPlatterClass, @selector(setBackgroundView:), NO,
						(ARIDockABIType) { 0, @encode(void) }, oneObjectArgument, 1)) {
					%init(FloatingDockPlatterBackgroundHook);
				}
		}
}

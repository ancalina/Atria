//
// Created by ren7995 on 2021-04-25 12:49:50
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"

#include <objc/runtime.h>

@interface SBHLibraryViewController : UIViewController
- (id)listLayoutProvider;
- (void)setListLayoutProvider:(id)provider;
@end

static void *ARIAppLibraryProviderAssociationKey = &ARIAppLibraryProviderAssociationKey;

static void ARIMarkAppLibraryLayoutProvider(id provider) {
    if(provider) {
        objc_setAssociatedObject(provider,
                                 ARIAppLibraryProviderAssociationKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

BOOL ARIIsAppLibraryLayoutProvider(id provider) {
    return [objc_getAssociatedObject(provider, ARIAppLibraryProviderAssociationKey) boolValue];
}

%hook SBIconController

// Option to disable AppLibrary
- (BOOL)isAppLibrarySupported {
	static const BOOL enabled = [[ARITweakManager sharedInstance] boolValueForKey:@"enableAppLibrary"];
	return enabled;
}

%end

%hook SBRootFolderControllerConfiguration

- (UIInterfaceOrientationMask)ignoresOverscrollOnFirstPageOrientations {
	static const BOOL disableTodayGesture = [[ARITweakManager sharedInstance] boolValueForKey:@"disableTodayGesture"];
	return disableTodayGesture ? 0 : %orig;
}

- (UIInterfaceOrientationMask)ignoresOverscrollOnLastPageOrientations {
	static const BOOL disableGesture = ![[ARITweakManager sharedInstance] boolValueForKey:@"enableAppLibrary"] || [[ARITweakManager sharedInstance] boolValueForKey:@"disableAppLibraryGesture"];
	return disableGesture ? 0 : UIInterfaceOrientationMaskAll;
}

%end

%group AppLibraryFix

%hook SBHLibraryViewController

- (id)listLayoutProvider {
	id originalProvider = %orig;
	ARIMarkAppLibraryLayoutProvider(originalProvider);
	return originalProvider;
}

- (void)viewDidLoad {
	%orig;
	// iOS 17 exposes a readonly provider. Force one getter read after the view
	// has loaded so code paths that subsequently use the ivar directly retain
	// SpringBoard's configured object while MainLayout can identify it.
	if([self respondsToSelector:@selector(listLayoutProvider)]) {
		ARIMarkAppLibraryLayoutProvider([self listLayoutProvider]);
	}
}

%end

%end

%group AppLibrarySetterFix

%hook SBHLibraryViewController

- (void)setListLayoutProvider:(id)list {
	ARIMarkAppLibraryLayoutProvider(list);
	%orig(list);
}

%end

%end

%ctor {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	if([manager isEnabled]) {
		NSLog(@"[Atria]: Loading hooks from %s", __FILE__);
		%init();

		if([manager boolValueForKey:@"layoutEnabled"]) {
				Class libraryViewControllerClass = objc_getClass("SBHLibraryViewController");
					if(libraryViewControllerClass &&
					   class_getInstanceMethod(libraryViewControllerClass, @selector(listLayoutProvider))) {
					%init(AppLibraryFix);
					if(class_getInstanceMethod(libraryViewControllerClass, @selector(setListLayoutProvider:))) {
						%init(AppLibrarySetterFix);
					}
				}
		}
	}
}

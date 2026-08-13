//
// Created by ren7995 on 2021-04-27 18:35:28
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"

static NSString *const ARIIconStateOSVersionKey = @"_saveStateOSVersion";
static NSString *const ARIIconStateSchemaVersionKey = @"_saveStateSchemaVersion";
static NSString *const ARIIconStateSchemaVersion = @"2";

static NSString *ARICurrentOSVersion(void) {
    return [NSProcessInfo processInfo].operatingSystemVersionString ?: @"";
}

static void ARICacheIconState(ARITweakManager *manager, id state) {
    if(![state isKindOfClass:[NSDictionary class]]) return;
    [manager setValue:state forKey:@"_saveState"];
    [manager setValue:ARICurrentOSVersion() forKey:ARIIconStateOSVersionKey];
    [manager setValue:ARIIconStateSchemaVersion forKey:ARIIconStateSchemaVersionKey];
}

static void ARIClearCachedIconState(ARITweakManager *manager) {
    [manager resetValueForKey:@"_saveState"];
    [manager resetValueForKey:ARIIconStateOSVersionKey];
    [manager resetValueForKey:ARIIconStateSchemaVersionKey];
}

%hook SBDefaultIconModelStore

- (id)loadCurrentIconState:(NSError **)error {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    id lastKnownState = [manager rawValueForKey:@"_saveState"];
    NSString *savedOSVersion = [manager rawValueForKey:ARIIconStateOSVersionKey];
    NSString *savedSchemaVersion = [manager rawValueForKey:ARIIconStateSchemaVersionKey];
    if([lastKnownState isKindOfClass:[NSDictionary class]] &&
       [savedOSVersion isKindOfClass:[NSString class]] &&
       [savedOSVersion isEqualToString:ARICurrentOSVersion()] &&
       [savedSchemaVersion isKindOfClass:[NSString class]] &&
       [savedSchemaVersion isEqualToString:ARIIconStateSchemaVersion]) {
        if(error) *error = nil;
        return lastKnownState;
    }

    ARIClearCachedIconState(manager);
    id orig = %orig;
    if([orig isKindOfClass:[NSDictionary class]]) {
        ARICacheIconState(manager, orig);
    }
    return orig;
}

- (BOOL)saveCurrentIconState:(id)state error:(NSError **)error {
    BOOL saved = %orig;
    if(saved) ARICacheIconState([ARITweakManager sharedInstance], state);
    return saved;
}

%end

%ctor {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    if([manager isEnabled]) {
        // A user might want to disable this if they have a tweak like Velox Reloaded 2 which also saves icon state
        if([manager boolValueForKey:@"saveIconState"]) {
            NSLog(@"[Atria]: Loading hooks from %s", __FILE__);
		    %init();
        } else {
            // Clear the existing saved icon state so that the user's layout doesn't revert when re-enabling the option
            ARIClearCachedIconState([ARITweakManager sharedInstance]);
        }
	}
}

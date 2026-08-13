//
// Created by ren7995 on 2021-04-17 13:45:45
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "ARIRootListController.h"
#import "../../Shared/ARIPreferenceMigration.h"
#import "../../Shared/ARIEditorValuePolicy.h"
#include <math.h>

@interface ARIRootListController ()
@property (nonatomic, copy) NSString *pendingDockResetRequestID;
@property (nonatomic, strong) UIAlertController *dockResetProgressAlert;
@end

static NSString *ARIDockResetRequestKey(NSString *requestID) {
    return requestID.length > 0 ?
        [ARIDockResetRequestKeyPrefix stringByAppendingString:requestID] : nil;
}

static NSString *ARIDockResetCompletionKey(NSString *requestID) {
    return requestID.length > 0 ?
        [ARIDockResetCompletionKeyPrefix stringByAppendingString:requestID] : nil;
}

static NSString *ARIBasePreferenceKey(NSString *key) {
    if(![key isKindOfClass:[NSString class]]) return nil;

    NSString *prefix = nil;
    NSString *baseKey = nil;
    if(ARIParsePagePreferenceKey(key, &prefix, &baseKey) && baseKey.length > 0) return baseKey;
    return key;
}

static BOOL ARIIsUserFacingPreferenceKey(NSString *key) {
    if(![key isKindOfClass:[NSString class]]) return NO;
    if(![key hasPrefix:@"_"] || [key isEqualToString:@"_perPageListViews"])
        return YES;
    NSString *pagePrefix = nil;
    NSString *baseKey = nil;
    return ARIParsePagePreferenceKey(key, &pagePrefix, &baseKey) && baseKey.length > 0;
}

static NSSet<NSString *> *ARIDeniedTransferKeys(void) {
    static NSSet<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"saveState", @"_saveState", @"_saveStateOSVersion", @"_saveStateSchemaVersion",
            @"_settingsMigrationVersion", @"_atriaDidSplashGuide", @"_atriaDidSplashGuide_v2",
            ARIDockResetRequestIDKey, @"_dockResetRequests", @"_dockResetCompletions",
            ARIDockResetCompletedIDKey,
            ARIDockResetResultKey, ARIDockResetMovedCountKey,
            ARIDockResetDeadlineKey
        ]];
    });
    return keys;
}

static BOOL ARINormalizeImportedPreferenceValue(NSString *key,
                                                id value,
                                                id *normalizedValue,
                                                NSString **reason) {
    if(![key isKindOfClass:[NSString class]] || key.length == 0 || key.length > 128 || [key hasPrefix:@"_"]) {
        if(reason) *reason = @"설정 키가 올바르지 않습니다.";
        return NO;
    }

    static NSCharacterSet *invalidKeyCharacters;
    static NSSet<NSString *> *booleanKeys;
    static NSSet<NSString *> *stringKeys;
    static NSDictionary<NSString *, NSArray<NSNumber *> *> *numericRanges;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        invalidKeyCharacters = [[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"] invertedSet];
        booleanKeys = [NSSet setWithArray:@[
            @"enabled", @"layoutEnabled", @"enableAppLibrary", @"saveIconState",
            @"dynamicWidgetSizing", @"disableDock", @"scaleInsideFolders",
            @"disableTodayGesture", @"disableAppLibraryGesture", @"forceFloatingDock",
            @"disableFloatingDockGestures", @"floatingDockAppLibrary", @"floatingDockRecents",
            @"hideBadges", @"hidePageDots", @"hideFolderIconBG", @"hideLabels",
            @"hideLabelsAppLibrary", @"hideLabelsFolders", @"dropShadow", @"showBackground",
            @"blurTintEnabled", @"showTooltips", @"useStepperControls",
            @"hide3DTouchActions", @"disableTapGesture",
            @"showWelcome", @"showWeatherIcon", @"showPageLabels", @"pageLabelShadow",
            @"labelScriptEnabled"
        ]];
        NSMutableSet<NSString *> *allStringKeys = [NSMutableSet setWithArray:@[
            @"labelText", @"pageLabelText", @"labelTextColor", @"blurTintColor",
            @"labelScriptSource", @"customGreetingTokensSource", @"labelFontMode",
            @"labelCustomFontPath", @"labelCustomFontName"
        ]];
        for(NSUInteger token = 1; token <= 3; token++) {
            NSString *prefix = [NSString stringWithFormat:@"customGreetingToken%lu", (unsigned long)token];
            for(NSString *suffix in @[@"Name", @"MorningText", @"AfternoonText", @"EveningText"])
                [allStringKeys addObject:[prefix stringByAppendingString:suffix]];
        }
        stringKeys = [allStringKeys copy];

        numericRanges = @{
            // Runtime historically accepted 0...20 even though the current UI
            // offers 1...3. Keep older exports transferable without weakening
            // the tweak's own validated boundary.
            @"maxFloatingDockRecents": @[@0.0, @20.0],
            @"editorOpenFrom": @[@0.0, @1.0],
            @"customGreetingMorningStartHour": @[@0.0, @23.0],
            @"customGreetingAfternoonStartHour": @[@0.0, @23.0],
            @"customGreetingEveningStartHour": @[@0.0, @23.0]
        };
    });

    if([key rangeOfCharacterFromSet:invalidKeyCharacters].location != NSNotFound) {
        if(reason) *reason = @"설정 키에 허용되지 않은 문자가 있습니다.";
        return NO;
    }

    NSString *baseKey = ARIBasePreferenceKey(key);
    if([booleanKeys containsObject:baseKey]) {
        if(![value isKindOfClass:[NSNumber class]]) {
            if(reason) *reason = @"스위치 설정은 숫자 또는 불리언이어야 합니다.";
            return NO;
        }
        double number = [(NSNumber *)value doubleValue];
        if(!isfinite(number) || (number != 0.0 && number != 1.0)) {
            if(reason) *reason = @"스위치 설정은 0 또는 1이어야 합니다.";
            return NO;
        }
        if(normalizedValue) *normalizedValue = @(number != 0.0);
        return YES;
    }

    if([stringKeys containsObject:baseKey]) {
        if(![value isKindOfClass:[NSString class]] || [(NSString *)value length] > 512 * 1024) {
            if(reason) *reason = @"문자열 설정이 올바르지 않거나 너무 큽니다.";
            return NO;
        }

        NSString *string = value;
        if([baseKey isEqualToString:@"labelTextColor"] || [baseKey isEqualToString:@"blurTintColor"]) {
            // Older builds could persist an empty tint value; map that legacy default
            // to a strict transferable color rather than exporting malformed data.
            if(string.length == 0) string = @"#FFFFFF";
            NSRegularExpression *expression = [NSRegularExpression
                regularExpressionWithPattern:@"^#[0-9A-Fa-f]{6}$"
                                      options:0
                                        error:nil];
            if([expression numberOfMatchesInString:string options:0 range:NSMakeRange(0, string.length)] != 1) {
                if(reason) *reason = @"색상은 #RRGGBB 형식이어야 합니다.";
                return NO;
            }
            string = [string uppercaseString];
        } else if([baseKey isEqualToString:@"labelFontMode"]) {
            if(string.length == 0) string = @"bundle";
            if(![@[@"system", @"bundle", @"imported", @"named"] containsObject:string]) {
                if(reason) *reason = @"글꼴 모드 값이 올바르지 않습니다.";
                return NO;
            }
        } else if([baseKey isEqualToString:@"labelCustomFontPath"]) {
            if(string.length > 4096 || (string.length > 0 && ![string hasPrefix:@"/"])) {
                if(reason) *reason = @"사용자 글꼴 경로가 올바르지 않습니다.";
                return NO;
            }
        } else if([baseKey isEqualToString:@"labelCustomFontName"] && string.length > 512) {
            if(reason) *reason = @"글꼴 이름이 너무 깁니다.";
            return NO;
        }
        if(normalizedValue) *normalizedValue = string;
        return YES;
    }

    if(![value isKindOfClass:[NSNumber class]]) {
        if(reason) *reason = @"알 수 없는 설정은 안전한 숫자 형식만 가져올 수 있습니다.";
        return NO;
    }

    double number = [(NSNumber *)value doubleValue];
    if(!isfinite(number) || fabs(number) > 1000000.0) {
        if(reason) *reason = @"숫자 설정이 유효 범위를 벗어났습니다.";
        return NO;
    }

    NSArray<NSNumber *> *range = numericRanges[baseKey];
    double editorLower = 0.0;
    double editorUpper = 0.0;
    BOOL editorIntegral = NO;
    if(ARIEditorValuePolicyForKey(baseKey,
                                  &editorLower,
                                  &editorUpper,
                                  &editorIntegral)) {
        if(editorIntegral) number = round(number);
        if(number < editorLower || number > editorUpper) {
            if(reason) *reason = @"숫자 설정이 안전 범위를 벗어났습니다.";
            return NO;
        }
        if(normalizedValue) {
            *normalizedValue = editorIntegral
                ? @((NSInteger)llround(number))
                : @(number);
        }
        return YES;
    }
    if(range) {
        number = round(number);
        if(number < range[0].doubleValue || number > range[1].doubleValue) {
            if(reason) *reason = @"숫자 설정이 현재 지원 범위를 벗어났습니다.";
            return NO;
        }
    }
    if(normalizedValue) *normalizedValue = range ? @((NSInteger)llround(number)) : @(number);
    return YES;
}

static BOOL ARINormalizePageMarkerValue(id value,
                                        NSMutableOrderedSet<NSString *> *markers,
                                        NSString **reason) {
    if(!value) return YES;
    if(![value isKindOfClass:[NSArray class]]) {
        if(reason) *reason = @"페이지 설정 목록은 배열이어야 합니다.";
        return NO;
    }

    for(id item in (NSArray *)value) {
        NSString *normalizedPrefix = ARINormalizedPagePrefix(item);
        if(!normalizedPrefix || normalizedPrefix.length > 32) {
            if(reason) *reason = @"페이지 설정 목록에 잘못된 페이지 표식이 있습니다.";
            return NO;
        }
        [markers addObject:normalizedPrefix];
    }
    return YES;
}

static NSDictionary *ARINormalizedTransferSettings(NSDictionary *source,
                                                   NSString **invalidKey,
                                                   NSString **reason) {
    NSMutableArray<NSString *> *sourceKeys = [NSMutableArray arrayWithCapacity:source.count];
    for(id key in source) {
        if(![key isKindOfClass:[NSString class]]) {
            if(invalidKey) *invalidKey = @"<non-string key>";
            if(reason) *reason = @"설정 키는 문자열이어야 합니다.";
            return nil;
        }
        [sourceKeys addObject:key];
    }
    [sourceKeys sortUsingSelector:@selector(compare:)];

    NSMutableOrderedSet<NSString *> *pageMarkers = [NSMutableOrderedSet orderedSet];
    NSString *markerReason = nil;
    if(!ARINormalizePageMarkerValue(source[@"_perPageListViews"], pageMarkers, &markerReason)) {
        if(invalidKey) *invalidKey = @"_perPageListViews";
        if(reason) *reason = markerReason;
        return nil;
    }

    NSMutableDictionary *normalizedSettings = [NSMutableDictionary dictionaryWithCapacity:source.count + 1];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *pageKeysByPrefix = [NSMutableDictionary new];
    // Canonical spellings are processed first so a legacy alias can never
    // overwrite the user's explicitly supplied destination key.
    for(NSUInteger pass = 0; pass < 2; pass++) {
        for(NSString *sourceKey in sourceKeys) {
            if([sourceKey isEqualToString:@"_perPageListViews"] ||
               [ARIDeniedTransferKeys() containsObject:sourceKey]) continue;

            NSString *legacyPagePrefix = nil;
            NSString *legacyBaseKey = nil;
            BOOL isPageKey = ARIParsePagePreferenceKey(sourceKey, &legacyPagePrefix, &legacyBaseKey) &&
                             legacyBaseKey.length > 0;
            // Unknown underscore-prefixed data is internal. The only exception is
            // the historical _N_key per-page format recognized above.
            if([sourceKey hasPrefix:@"_"] && !isPageKey) continue;

            NSString *normalizedKey = ARINormalizedPreferenceKey(sourceKey);
            BOOL isCanonical = [normalizedKey isEqualToString:sourceKey];
            if((pass == 0) != isCanonical) continue;
            if(normalizedSettings[normalizedKey]) continue;

            id normalizedValue = nil;
            NSString *valueReason = nil;
            if(!ARINormalizeImportedPreferenceValue(normalizedKey,
                                                    source[sourceKey],
                                                    &normalizedValue,
                                                    &valueReason)) {
                if(invalidKey) *invalidKey = sourceKey;
                if(reason) *reason = valueReason;
                return nil;
            }
            normalizedSettings[normalizedKey] = normalizedValue;

            NSString *pagePrefix = nil;
            NSString *baseKey = nil;
            if(ARIParsePagePreferenceKey(normalizedKey, &pagePrefix, &baseKey) &&
               ([baseKey isEqualToString:@"hs_rows"] || [baseKey isEqualToString:@"hs_columns"])) {
                NSMutableSet<NSString *> *pageKeys = pageKeysByPrefix[pagePrefix];
                if(!pageKeys) {
                    pageKeys = [NSMutableSet new];
                    pageKeysByPrefix[pagePrefix] = pageKeys;
                }
                [pageKeys addObject:baseKey];
            }
        }
    }

    // Match runtime migration: a complete frozen page layout always contains
    // both grid dimensions. A lone editor value (and PageN_pageLabelText in
    // particular) is not enough to reactivate an orphaned per-page override.
    [pageKeysByPrefix enumerateKeysAndObjectsUsingBlock:^(NSString *prefix,
                                                          NSSet<NSString *> *pageKeys,
                                                          BOOL *stop) {
        (void)stop;
        if([pageKeys containsObject:@"hs_rows"] && [pageKeys containsObject:@"hs_columns"])
            [pageMarkers addObject:prefix];
    }];

    NSArray<NSString *> *sortedMarkers = [[pageMarkers array] sortedArrayUsingSelector:@selector(compare:)];
    normalizedSettings[@"_perPageListViews"] = sortedMarkers;
    return normalizedSettings;
}

@implementation ARIRootListController

- (NSArray *)specifiers {
    if(!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        [self atriaResolveIconPathsForSpecifiers:_specifiers];
    }

    return _specifiers;
}

- (void)resetPrefs:(id)sender {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Reset Preferences"
                         message:@"Are you sure you want to reset preferences? Your device will respring."
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"No"
                  style:UIAlertActionStyleCancel
                handler:nil];
    UIAlertAction *yes = [UIAlertAction
        actionWithTitle:@"Yes"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    NSUserDefaults *prefs = [[NSUserDefaults alloc]
                        initWithSuiteName:ARIPreferenceDomain];
                    [prefs synchronize];
                    NSDictionary *existingDomain = [[NSUserDefaults standardUserDefaults]
                        persistentDomainForName:ARIPreferenceDomain] ?: @{};
                    // Remove user-facing keys individually. A Dock reset can be
                    // owned by another PreferenceLoader process, so replacing
                    // the whole domain would race its per-request transport key.
                    for(NSString *key in existingDomain) {
                        if(ARIIsUserFacingPreferenceKey(key))
                            [prefs removeObjectForKey:key];
                    }
                    [prefs synchronize];
                    [self respringWithAnimation];
                }];

    [alert addAction:defaultAction];
    [alert addAction:yes];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSaveState:(id)sender {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Reset Save State"
                         message:@"Are you sure you want to reset save state? Your device will respring."
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"No"
                  style:UIAlertActionStyleCancel
                handler:nil];
    UIAlertAction *yes = [UIAlertAction
        actionWithTitle:@"Yes"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
                    [prefs removeObjectForKey:@"_saveState"];
                    [prefs removeObjectForKey:@"_saveStateOSVersion"];
                    [prefs removeObjectForKey:@"_saveStateSchemaVersion"];
                    [prefs synchronize];
                    [self respringWithAnimation];
                }];

    [alert addAction:defaultAction];
    [alert addAction:yes];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)finishDockResetRequest:(NSString *)requestID
                        result:(NSString *)result
                    movedCount:(NSUInteger)movedCount {
    if(![self.pendingDockResetRequestID isEqualToString:requestID]) return;
    self.pendingDockResetRequestID = nil;

    UIAlertController *progressAlert = self.dockResetProgressAlert;
    self.dockResetProgressAlert = nil;
    void (^showResult)(void) = ^{
        NSString *title = @"Dock 배열 초기화 실패";
        NSString *message = @"SpringBoard가 작업을 완료하지 못했습니다. Dock 상태를 확인한 뒤 다시 시도해 주세요.";
        if([result isEqualToString:@"success"]) {
            title = @"Dock 배열 초기화 완료";
            message = [NSString stringWithFormat:
                @"Dock의 앱과 폴더 %lu개를 홈 화면으로 이동했습니다.",
                (unsigned long)movedCount];
        } else if([result isEqualToString:@"alreadyEmpty"]) {
            title = @"Dock이 이미 비어 있음";
            message = @"변경할 Dock 항목이 없습니다.";
        } else if([result isEqualToString:@"busy"]) {
            message = @"홈 화면 편집 또는 아이콘 이동이 끝난 뒤 다시 시도해 주세요. 배열은 변경되지 않았습니다.";
        } else if([result isEqualToString:@"unavailable"]) {
            message = @"SpringBoard의 Dock이 아직 준비되지 않았습니다. 홈 화면이 표시된 뒤 다시 시도해 주세요.";
        } else if([result isEqualToString:@"unsupported"]) {
            message = @"이 iOS 버전에서는 안전한 Dock 이동 API를 확인할 수 없어 배열을 변경하지 않았습니다.";
        } else if([result isEqualToString:@"saveFailed"]) {
            message = @"변경 내용을 저장하지 못했습니다. Dock 상태를 확인한 뒤 다시 시도해 주세요.";
        } else if([result isEqualToString:@"rollbackFailed"]) {
            message = @"변경 검증과 원상 복구를 완료하지 못했습니다. Dock 상태를 확인하고 SpringBoard를 다시 시작해 주세요.";
        } else if([result isEqualToString:@"expired"]) {
            message = @"요청 시간이 지나 배열을 변경하지 않았습니다. 홈 화면이 표시된 뒤 다시 시도해 주세요.";
        } else if([result isEqualToString:@"superseded"]) {
            message = @"다른 Dock 초기화 요청이 시작되어 이 요청은 배열을 변경하지 않았습니다. 최신 요청 결과를 확인해 주세요.";
        } else if([result isEqualToString:@"noResponse"]) {
            message = @"SpringBoard의 최종 응답을 받지 못했습니다. Dock 상태를 확인한 뒤 다시 시도해 주세요.";
        }
        [self displayAlert:title message:message];
    };
    if(progressAlert.presentingViewController) {
        [progressAlert dismissViewControllerAnimated:YES completion:showResult];
    } else {
        showResult();
    }
}

- (void)pollDockResetRequest:(NSString *)requestID attempt:(NSUInteger)attempt {
    if(![self.pendingDockResetRequestID isEqualToString:requestID]) return;

    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    [prefs synchronize];
    NSDictionary *completion = [prefs dictionaryForKey:ARIDockResetCompletionKey(requestID)];
    NSString *completedID = [completion[ARIDockResetCompletionRequestIDField]
        isKindOfClass:[NSString class]] ? completion[ARIDockResetCompletionRequestIDField] : nil;
    if([completedID isEqualToString:requestID]) {
        NSString *result = [completion[ARIDockResetCompletionResultField]
            isKindOfClass:[NSString class]] ?
            completion[ARIDockResetCompletionResultField] : @"validationFailed";
        NSNumber *movedValue = [completion[ARIDockResetCompletionMovedCountField]
            isKindOfClass:[NSNumber class]] ?
            completion[ARIDockResetCompletionMovedCountField] : @0;
        NSUInteger movedCount = movedValue.unsignedIntegerValue;
        [self finishDockResetRequest:requestID result:result movedCount:movedCount];
        return;
    }

    // A short-lived earlier build stored correlated terminal records in one
    // map. Prefer its exact UUID entry over the scalar compatibility slot,
    // promote it, and retire this request without modifying the shared map.
    NSDictionary *legacyCompletions = [prefs dictionaryForKey:@"_dockResetCompletions"];
    NSDictionary *legacyCompletion = [legacyCompletions[requestID]
        isKindOfClass:[NSDictionary class]] ? legacyCompletions[requestID] : nil;
    NSString *legacyMapCompletedID = [legacyCompletion[ARIDockResetCompletionRequestIDField]
        isKindOfClass:[NSString class]] ?
        legacyCompletion[ARIDockResetCompletionRequestIDField] : nil;
    if([legacyMapCompletedID isEqualToString:requestID]) {
        NSString *result = [legacyCompletion[ARIDockResetCompletionResultField]
            isKindOfClass:[NSString class]] ?
            legacyCompletion[ARIDockResetCompletionResultField] : @"validationFailed";
        NSNumber *movedValue = [legacyCompletion[ARIDockResetCompletionMovedCountField]
            isKindOfClass:[NSNumber class]] ?
            legacyCompletion[ARIDockResetCompletionMovedCountField] : @0;
        NSMutableDictionary *promotedCompletion = [legacyCompletion mutableCopy];
        NSDictionary *request = [prefs dictionaryForKey:ARIDockResetRequestKey(requestID)];
        NSNumber *requestTimestamp = [request[ARIDockResetRequestTimestampField]
            isKindOfClass:[NSNumber class]] ? request[ARIDockResetRequestTimestampField] : nil;
        if(requestTimestamp && !promotedCompletion[ARIDockResetCompletionRequestTimestampField])
            promotedCompletion[ARIDockResetCompletionRequestTimestampField] = requestTimestamp;
        NSString *legacyCompletedID = [prefs stringForKey:ARIDockResetCompletedIDKey];
        BOOL hasCurrentProvenance =
            [legacyCompletion[ARIDockResetCompletionLegacyScalarField]
                isKindOfClass:[NSNumber class]];
        if([legacyCompletedID isEqualToString:requestID] && !hasCurrentProvenance)
            promotedCompletion[ARIDockResetCompletionLegacyScalarField] = @YES;
        [prefs setObject:promotedCompletion forKey:ARIDockResetCompletionKey(requestID)];
        [prefs removeObjectForKey:ARIDockResetRequestKey(requestID)];
        [prefs synchronize];
        [self finishDockResetRequest:requestID
                              result:result
                          movedCount:movedValue.unsignedIntegerValue];
        return;
    }

    // During an in-place package update, Preferences can be newer than the
    // SpringBoard process. Accept the old process's correlated scalar response
    // only when its completion ID exactly matches this request.
    NSString *legacyCompletedID = [prefs stringForKey:ARIDockResetCompletedIDKey];
    if([legacyCompletedID isEqualToString:requestID]) {
        NSString *result = [prefs stringForKey:ARIDockResetResultKey] ?: @"validationFailed";
        NSUInteger movedCount = (NSUInteger)[prefs integerForKey:ARIDockResetMovedCountKey];
        // Retire the durable request before returning a legacy response. This
        // prevents a newly upgraded SpringBoard from replaying work that an old
        // SpringBoard process already completed.
        NSDictionary *request = [prefs dictionaryForKey:ARIDockResetRequestKey(requestID)];
        NSNumber *requestTimestamp = [request[ARIDockResetRequestTimestampField]
            isKindOfClass:[NSNumber class]] ? request[ARIDockResetRequestTimestampField] : @0;
        NSDictionary *legacyScalarCompletion = @{
            ARIDockResetCompletionRequestIDField: requestID,
            ARIDockResetCompletionResultField: result,
            ARIDockResetCompletionMovedCountField: @(movedCount),
            ARIDockResetCompletionRequestTimestampField: requestTimestamp,
            ARIDockResetCompletionLegacyScalarField: @YES,
            ARIDockResetCompletionTimestampField: @(NSDate.date.timeIntervalSince1970)
        };
        [prefs setObject:legacyScalarCompletion forKey:ARIDockResetCompletionKey(requestID)];
        [prefs removeObjectForKey:ARIDockResetRequestKey(requestID)];
        [prefs synchronize];
        [self finishDockResetRequest:requestID result:result movedCount:movedCount];
        return;
    }

    if(attempt >= 48) {
        // SpringBoard owns terminal results. A local timeout must not claim the
        // layout was unchanged while an in-process operation is completing.
        [self finishDockResetRequest:requestID result:@"noResponse" movedCount:0];
        return;
    }

    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [weakSelf pollDockResetRequest:requestID attempt:attempt + 1];
    });
}

- (void)beginDockResetRequest {
    if(self.pendingDockResetRequestID.length > 0) return;

    NSString *requestID = NSUUID.UUID.UUIDString;
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    NSTimeInterval timestamp = NSDate.date.timeIntervalSince1970;
    NSTimeInterval deadline = timestamp + 8.0;
    [prefs setObject:@{
        ARIDockResetRequestTimestampField: @(timestamp),
        ARIDockResetRequestDeadlineField: @(deadline)
    } forKey:ARIDockResetRequestKey(requestID)];

    // Keep the old single-slot request populated so a Preferences bundle can
    // still talk to SpringBoard during an in-place mixed-version update.
    [prefs setObject:requestID forKey:ARIDockResetRequestIDKey];
    [prefs setDouble:deadline forKey:ARIDockResetDeadlineKey];
    [prefs synchronize];
    self.pendingDockResetRequestID = requestID;

    UIAlertController *progress = [UIAlertController
        alertControllerWithTitle:@"Dock 배열 초기화 중…"
                         message:@"SpringBoard에서 아이콘과 폴더를 안전하게 이동하고 있습니다."
                  preferredStyle:UIAlertControllerStyleAlert];
    self.dockResetProgressAlert = progress;
    [self presentViewController:progress animated:YES completion:^{
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge CFStringRef)ARIDockResetRequestNotification,
            NULL,
            NULL,
            true
        );
        [self pollDockResetRequest:requestID attempt:0];
    }];
}

- (void)resetDockArrangement:(id)sender {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Dock 배열 초기화"
                         message:@"Dock의 모든 앱과 폴더를 홈 화면의 빈 공간으로 이동하고 Dock을 비웁니다. 나머지 홈 화면 배열과 Atria 설정은 유지됩니다. 계속할까요?"
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"취소"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    __weak __typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"초기화"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(__unused UIAlertAction *action) {
        [alert dismissViewControllerAnimated:YES completion:^{
            [weakSelf beginDockResetRequest];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportSettingsString {
    // Sync defaults
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    [defaults synchronize];

    // Export the live defaults domain instead of depending on the backing plist file.
    NSDictionary *domainDictionary = [[NSUserDefaults standardUserDefaults] persistentDomainForName:ARIPreferenceDomain];
    NSString *invalidKey = nil;
    NSString *reason = nil;
    NSDictionary *dict = ARINormalizedTransferSettings(domainDictionary ?: @{}, &invalidKey, &reason);
    if(!dict) {
        [self displayAlert:@"Failed to export"
                   message:[NSString stringWithFormat:@"Invalid setting `%@`.\n\n%@",
                            invalidKey ?: @"<unknown>", reason ?: @"Unknown validation error."]];
        return;
    }

    // Easier to make it json imho
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict
                                                       options:0
                                                         error:&error];
    if(error) {
        [self displayAlert:@"Failed to export" message:[NSString stringWithFormat:@"Error: %@", error.localizedDescription]];
        return;
    }

    NSString *encoded = [jsonData base64EncodedStringWithOptions:0];
    [UIPasteboard generalPasteboard].string = encoded;
    [self displayAlert:@"Success" message:@"Settings exported and copied to clipboard"];
}

- (void)importSettingsString {
    NSString *pasteboardString = [UIPasteboard generalPasteboard].string;
    if(!pasteboardString) {
        [self displayAlert:@"Failed to import" message:@"No string was found in your clipboard."];
        return;
    }
    if([pasteboardString lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 2 * 1024 * 1024) {
        [self displayAlert:@"Failed to import" message:@"The settings string is too large."];
        return;
    }

    NSData *decodeData = [[NSData alloc] initWithBase64EncodedString:pasteboardString options:0];
    if(!decodeData) {
        [self displayAlert:@"Failed to import" message:@"Failed to decode. Perhaps the settings string in your clipboard is invalid?"];
        return;
    }

    NSError *error = nil;
    id decodedObject = [NSJSONSerialization JSONObjectWithData:decodeData options:kNilOptions error:&error];

    if(![decodedObject isKindOfClass:[NSDictionary class]]) {
        [self displayAlert:@"Failed to import" message:[NSString stringWithFormat:@"Perhaps the settings string in your clipboard is invalid?\n\nError: %@", error.localizedDescription]];
        return;
    }

    NSDictionary *settingsDictionary = decodedObject;
    NSString *invalidKey = nil;
    NSString *reason = nil;
    NSDictionary *normalizedSettings = ARINormalizedTransferSettings(settingsDictionary, &invalidKey, &reason);
    if(!normalizedSettings) {
        [self displayAlert:@"Failed to import"
                   message:[NSString stringWithFormat:@"Invalid setting `%@`.\n\n%@",
                            invalidKey ?: @"<unknown>", reason ?: @"Unknown validation error."]];
        return;
    }

    NSMutableDictionary *validatedSettings = [normalizedSettings mutableCopy];
    NSUInteger importedSettingCount = validatedSettings.count;

    // Imported data may not supply internal state. Leave every underscore-
    // prefixed destination key untouched while changing public preferences.
    NSDictionary *existingDomain = [[NSUserDefaults standardUserDefaults]
        persistentDomainForName:ARIPreferenceDomain] ?: @{};
    // Validation above is transactional. Commit public keys individually so a
    // concurrent Dock reset's underscore-prefixed transport keys can never be
    // lost to a whole-domain replacement.
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    for(NSString *key in existingDomain) {
        if(ARIIsUserFacingPreferenceKey(key) && !validatedSettings[key])
            [defaults removeObjectForKey:key];
    }
    for(NSString *key in validatedSettings)
        [defaults setObject:validatedSettings[key] forKey:key];
    [defaults synchronize];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Success"
                         message:[NSString stringWithFormat:@"Settings imported safely. You may now respring to apply completely.\n\nSettings imported: %lu", (unsigned long)importedSettingCount]
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"Respring"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    [self respringWithAnimation];
                }];
    [alert addAction:defaultAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)displayAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"OK"
                  style:UIAlertActionStyleCancel
                handler:nil];

    [alert addAction:defaultAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

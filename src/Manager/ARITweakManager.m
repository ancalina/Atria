//
// Created by ren7995 on 2021-04-25 12:49:07
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "ARITweakManager.h"
#import "ARIEditManager.h"

#import "../Hooks/Shared.h"
#import "../../Shared/ARIPathUtils.h"
#import "../../Shared/ARIPreferenceMigration.h"

#import <objc/runtime.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>

// ARITweakManager is created from Logos constructors while SpringBoard is
// still running its dyld initializers. Asking UIKit for userInterfaceIdiom at
// that point can recursively start SpringBoard's application initialization
// and deadlock in FrontBoard/BoardServices (observed on iOS 15 RootHide).
// The hardware family identifier is available without starting UIKit. Match
// the stable family prefix rather than maintaining a list of device models.
static BOOL ARIHostIsIPadWithoutStartingUIKit(void) {
    const char *modelIdentifier = getenv("SIMULATOR_MODEL_IDENTIFIER");
    struct utsname systemInfo = {};
    if(!modelIdentifier || !*modelIdentifier) {
        if(uname(&systemInfo) != 0) return NO;
        modelIdentifier = systemInfo.machine;
    }
    return modelIdentifier && strncmp(modelIdentifier, "iPad", 4) == 0;
}

static UIView *ARIFindSubviewOfClass(UIView *view, Class targetClass) {
    if(!view || !targetClass) return nil;
    if([view isKindOfClass:targetClass]) return view;
    for(UIView *subview in view.subviews) {
        UIView *match = ARIFindSubviewOfClass(subview, targetClass);
        if(match) return match;
    }
    return nil;
}

static id ARISafeValueForKey(id object, NSString *key) {
    if(!object || ![key isKindOfClass:[NSString class]] || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch(__unused NSException *exception) {
        return nil;
    }
}

// Read an already-populated object backing ivar without invoking a private
// getter. In particular, -[SBRootFolder(WithDock) dock] is lazy on iOS 15 and
// creates a Dock model when _dock is nil; calling it from maxNumberOfIcons can
// therefore re-enter icon-model construction. Unknown layouts fail closed.
static id ARIExistingObjectIvar(id object, const char *name) {
    if(!object || !name) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *encoding = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if(!encoding || encoding[0] != '@') return nil;
    return object_getIvar(object, ivar);
}

static id ARIIconControllerSharedInstance(void) {
    Class controllerClass = objc_getClass("SBIconController");
    return [controllerClass respondsToSelector:@selector(sharedInstance)]
        ? [controllerClass sharedInstance]
        : nil;
}

static SBFloatingDockController *ARIFloatingDockControllerSharedInstance(void) {
    Class controllerClass = objc_getClass("SBFloatingDockController");
    SBFloatingDockController *controller =
        [controllerClass respondsToSelector:@selector(_atriaSharedInstance)]
        ? [controllerClass _atriaSharedInstance]
        : nil;
    if(controller) return controller;

    // The initializer capture is the cross-version path, but iOS 13-15 also
    // exposes the controller from SBIconController.  Use that relationship as
    // a fallback so a harmless constructor-order change cannot leave the live
    // user Dock model unidentified.
    id iconController = ARIIconControllerSharedInstance();
    return [iconController respondsToSelector:@selector(floatingDockController)]
        ? [iconController floatingDockController]
        : nil;
}

static SBIconListView *ARIUserDockListView(SBRootFolderView *rootFolderView) {
    Class listViewClass = objc_getClass("SBIconListView");
    if(!listViewClass) return nil;

    SBIconListView *listView = nil;
    if(![ARITweakManager isUsingFloatingDock]) {
        listView = (SBIconListView *)ARISafeValueForKey(rootFolderView, @"_dockListView");
    } else {
        SBFloatingDockController *controller = ARIFloatingDockControllerSharedInstance();
        if([controller respondsToSelector:@selector(userIconListView)]) {
            listView = [controller userIconListView];
        }
        if(!listView) {
            SBFloatingDockViewController *viewController =
                [controller respondsToSelector:@selector(floatingDockViewController)]
                    ? [controller floatingDockViewController]
                    : (SBFloatingDockViewController *)ARISafeValueForKey(controller, @"_viewController");
            SBFloatingDockView *dockView =
                [viewController respondsToSelector:@selector(dockView)]
                    ? [viewController dockView]
                    : (SBFloatingDockView *)ARISafeValueForKey(viewController, @"_dockView");
            listView = (SBIconListView *)ARISafeValueForKey(dockView, @"_userIconListView");
        }
    }
    return [listView isKindOfClass:listViewClass] ? listView : nil;
}

static void ARILayoutIconListView(SBIconListView *listView) {
    Class listViewClass = objc_getClass("SBIconListView");
    if(!listViewClass || ![listView isKindOfClass:listViewClass]) return;
    if([listView respondsToSelector:@selector(set_atriaNeedsLayout:)]) {
        listView._atriaNeedsLayout = YES;
    }
    if([listView respondsToSelector:@selector(layoutIconsNow)]) {
        [listView layoutIconsNow];
        return;
    }
    [listView setNeedsLayout];
    [listView layoutIfNeeded];
}

@implementation ARITweakManager {
    BOOL _enabled;
    NSUserDefaults *_preferences;
    NSMutableOrderedSet<NSString *> *_orderedSettingKeys;
    NSMutableDictionary<NSString *, ARIOption *> *_optionsRegistry;
    NSMapTable *_listViewModelMap;
    BOOL _deviceIPad;
    BOOL _shyLabelsInstalled;
    __weak SBIconListView *_persistentUserDockListView;
}

@synthesize enabled = _enabled;
@synthesize preferences = _preferences;
@synthesize deviceIPad = _deviceIPad;
@synthesize shyLabelsInstalled = _shyLabelsInstalled;
@synthesize listViewModelMap = _listViewModelMap;

// Shared instance and init methods

- (instancetype)init {
    self = [super init];
    if(self) {
        // This object is first requested before UIApplication initializes, so
        // detect the host device without starting UIKit.
        _deviceIPad = ARIHostIsIPadWithoutStartingUIKit();
        // ShyLabels compatibility
        _shyLabelsInstalled = ARIMobileSubstrateDylibPath(@"ShyLabels") != nil;
        // NSUserDefaults to get what values the user set
        _preferences = [[NSUserDefaults alloc] initWithSuiteName:@"me.lau.AtriaPrefs"];
        id enabledValue = [_preferences objectForKey:@"enabled"];
        _enabled = [enabledValue isKindOfClass:[NSNumber class]] ? [enabledValue boolValue] : YES;
        _listViewModelMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory valueOptions:NSPointerFunctionsWeakMemory];

        // Create settings
        _orderedSettingKeys = [[NSMutableOrderedSet alloc] initWithCapacity:50];
        _optionsRegistry = [[NSMutableDictionary alloc] init];

        [self _registerOption:@"showWelcome"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"showWeatherIcon"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"showTooltips"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"useStepperControls"
                  translation:nil
                 defaultValue:@(NO)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"labelText"
                  translation:nil
                 defaultValue:@"%인삿말_한%."
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"labelScriptEnabled"
                  translation:nil
                 defaultValue:@(NO)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"labelScriptSource"
                  translation:nil
                 defaultValue:@""
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"customGreetingMorningStartHour"
                  translation:nil
                 defaultValue:@(4)
                   lowerLimit:0
                   upperLimit:23];
        [self _registerOption:@"customGreetingAfternoonStartHour"
                  translation:nil
                 defaultValue:@(12)
                   lowerLimit:0
                   upperLimit:23];
        [self _registerOption:@"customGreetingEveningStartHour"
                  translation:nil
                 defaultValue:@(18)
                   lowerLimit:0
                   upperLimit:23];
        [self _registerOption:@"customGreetingTokensSource"
                  translation:nil
                 defaultValue:@""
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"labelTextColor"
                  translation:nil
                 defaultValue:@"#FFFFFF"
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"blurTintColor"
                  translation:nil
                 defaultValue:@"#FFFFFF"
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"layoutEnabled"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"enableAppLibrary"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"saveIconState"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"hideLabelsAppLibrary"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"hideLabels"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"hideLabelsFolders"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"scaleInsideFolders"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"dynamicWidgetSizing"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"floatingDockAppLibrary"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"floatingDockRecents"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"maxFloatingDockRecents"
                  translation:nil
                 defaultValue:@(3)
                   lowerLimit:0
                   upperLimit:20];

        // Homescreen
        [self _registerOption:@"hs_rows"
                  translation:@"행"
                 defaultValue:@(6)
                   lowerLimit:2.0F
                   upperLimit:20.0F];
        [self _registerOption:@"hs_columns"
                  translation:@"열"
                 defaultValue:@(4)
                   lowerLimit:2.0F
                   upperLimit:20.0F];
        [self _registerOption:@"hs_iconScale"
                  translation:@"아이콘 크기"
                 defaultValue:@(1.0)
                   lowerLimit:0.01F
                   upperLimit:2.0F];
        [self _registerOption:@"hs_widgetIconScale"
                  translation:@"위젯 크기"
                 defaultValue:@(1.0)
                   lowerLimit:0.01F
                   upperLimit:3.0F];
        [self _registerOption:@"hs_spacing_x"
                  translation:@"아이콘 간격 X"
                 defaultValue:@(0)
                   lowerLimit:-100.0F
                   upperLimit:100.0F];
        [self _registerOption:@"hs_spacing_y"
                  translation:@"아이콘 간격 Y"
                 defaultValue:@(0)
                   lowerLimit:-100.0F
                   upperLimit:100.0F];
        [self _registerOption:@"hs_inset_top"
                  translation:@"상단 여백"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_inset_left"
                  translation:@"왼쪽 여백"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_inset_bottom"
                  translation:@"아래 여백"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_inset_right"
                  translation:@"오른쪽 여백"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_offset_top"
                  translation:@"페이지 상단 오프셋"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_offset_left"
                  translation:@"페이지 왼쪽 오프셋"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_widgetXOffset"
                  translation:@"위젯 X 오프셋"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_widgetYOffset"
                  translation:@"위젯 Y 오프셋"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];

        // Do not query floating-dock support while SpringBoard is still running
        // dyld initializers. Start with the regular Dock default and update the
        // option after SpringBoard has finished launching, as upstream Atria did.
        [self _registerOption:@"dock_columns"
                  translation:@"열"
                 defaultValue:@(4)
                   lowerLimit:2.0F
                   upperLimit:20.0F];
        [self _registerOption:@"dock_rows"
                  translation:@"행"
                 defaultValue:@(1)
                   lowerLimit:1.0F
                   upperLimit:5.0F];
        [self _registerOption:@"dock_iconScale"
                  translation:@"아이콘 크기"
                 defaultValue:@(1)
                   lowerLimit:0.01F
                   upperLimit:2.0F];
        [self _registerOption:@"dock_bg"
                  translation:@"배경 투명도"
                 defaultValue:@(1)
                   lowerLimit:0.0F
                   upperLimit:1.0F];
        [self _registerOption:@"dock_spacing_x"
                  translation:@"아이콘 간격 X"
                 defaultValue:@(0)
                   lowerLimit:-100.0F
                   upperLimit:100.0F];
        [self _registerOption:@"dock_spacing_y"
                  translation:@"아이콘 간격 Y"
                 defaultValue:@(0)
                   lowerLimit:-100.0F
                   upperLimit:100.0F];
        [self _registerOption:@"dock_inset_top"
                  translation:@"상단 여백"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"dock_inset_left"
                  translation:@"왼쪽 여백"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"dock_inset_bottom"
                  translation:@"아레 여백"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"dock_inset_right"
                  translation:@"오른쪽 여백"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];

        // Page labels
        [self _registerOption:@"label_textSize"
                  translation:@"글자 크기"
                 defaultValue:@(27)
                   lowerLimit:1.0F
                   upperLimit:60.0F];
        [self _registerOption:@"label_inset_left"
                  translation:@"측면 여백"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"label_inset_top"
                  translation:@"세로 여백"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];

        // Blur background
        [self _registerOption:@"blur_alpha"
                  translation:@"배경 투명도"
                 defaultValue:@(1)
                   lowerLimit:0.0F
                   upperLimit:1.0F];
        [self _registerOption:@"blur_corner_radius"
                  translation:@"모서리 반경"
                 defaultValue:@(14)
                   lowerLimit:0.0F
                   upperLimit:100.0F];
        [self _registerOption:@"blur_intensity"
                  translation:@"틴트 강도"
                 defaultValue:@(0.5F)
                   lowerLimit:0.0F
                   upperLimit:1.0F];

        [self _registerOption:@"blur_inset_top"
                  translation:@"상단 위치"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"blur_inset_left"
                  translation:@"왼쪽 위치"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"blur_inset_bottom"
                  translation:@"하단 위치"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"blur_inset_right"
                  translation:@"오른쪽 위치"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];

        // Page dots
        [self _registerOption:@"pagedot_offsetX"
                  translation:@"X 오프셋"
                 defaultValue:@(0)
                   lowerLimit:-150.0F
                   upperLimit:150.0F];
        [self _registerOption:@"pagedot_offsetY"
                  translation:@"Y 오프셋"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];

        // Migrate after the registry exists so legacy per-page keys can be
        // distinguished from unrelated PageN metadata.
        [self _migrateSettings];
    }
    return self;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t token;
    static ARITweakManager *manager;
    dispatch_once(&token, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (void)_migrateSettings {
    NSInteger migrationVersion = [[_preferences objectForKey:@"_settingsMigrationVersion"] integerValue];
    if(migrationVersion >= 2) return;

    BOOL migrationSucceeded = YES;
    if(migrationVersion < 1) {
        migrationSucceeded = [self _migrateSettingFromKey:@"saveState" toKey:@"_saveState"];
    }

    NSMutableOrderedSet<NSString *> *perPagePrefixes = [NSMutableOrderedSet new];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *pageKeysByPrefix = [NSMutableDictionary new];
    id storedPerPage = [_preferences objectForKey:@"_perPageListViews"];
    if([storedPerPage isKindOfClass:[NSArray class]]) {
        for(id value in (NSArray *)storedPerPage) {
            NSString *prefix = ARINormalizedPagePrefix(value);
            if(prefix) [perPagePrefixes addObject:prefix];
        }
    }

    NSDictionary *domain = [[NSUserDefaults standardUserDefaults]
        persistentDomainForName:@"me.lau.AtriaPrefs"] ?: [_preferences dictionaryRepresentation];
    for(id candidateKey in domain.allKeys) {
        if(![candidateKey isKindOfClass:[NSString class]]) continue;
        NSString *key = candidateKey;
        NSString *normalizedKey = ARINormalizedPreferenceKey(key);
        if(![normalizedKey isKindOfClass:[NSString class]] || normalizedKey.length == 0) continue;

        if(![normalizedKey isEqualToString:key]) {
            id oldValue = [_preferences objectForKey:key];
            if(oldValue && ![_preferences objectForKey:normalizedKey]) {
                id migratedValue = [self _validatedPreferenceValue:oldValue forKey:normalizedKey] ?: oldValue;
                [_preferences setObject:migratedValue forKey:normalizedKey];
                if(![[_preferences objectForKey:normalizedKey] isEqual:migratedValue]) {
                    migrationSucceeded = NO;
                    continue;
                }
            }
            if(!oldValue || [_preferences objectForKey:normalizedKey]) {
                [_preferences removeObjectForKey:key];
            }
        }

        NSString *prefix = nil;
        NSString *baseKey = nil;
        if(ARIParsePagePreferenceKey(normalizedKey, &prefix, &baseKey) && baseKey.length > 0) {
            ARIOption *option = _optionsRegistry[baseKey];
            if(option.accessibleWithEditor) {
                NSMutableSet<NSString *> *pageKeys = pageKeysByPrefix[prefix];
                if(!pageKeys) {
                    pageKeys = [NSMutableSet new];
                    pageKeysByPrefix[prefix] = pageKeys;
                }
                [pageKeys addObject:baseKey];
            }
        }
    }

    // createCustomForListView: freezes the complete editor state, including
    // both home-grid dimensions. Reconstruct a marker only from that coherent
    // signature; a lone stale PageN key must not silently re-enable overrides.
    [pageKeysByPrefix enumerateKeysAndObjectsUsingBlock:^(NSString *prefix,
                                                          NSSet<NSString *> *pageKeys,
                                                          BOOL *stop) {
        (void)stop;
        if([pageKeys containsObject:@"hs_rows"] && [pageKeys containsObject:@"hs_columns"]) {
            [perPagePrefixes addObject:prefix];
        }
    }];

    if(migrationSucceeded) {
        [self setValue:perPagePrefixes.array forKey:@"_perPageListViews"];
        [self setValue:@(2) forKey:@"_settingsMigrationVersion"];
    }
}

- (BOOL)_migrateSettingFromKey:(NSString *)oldKey toKey:(NSString *)newKey {
    id oldValue = [_preferences objectForKey:oldKey];
    if(oldValue && ![_preferences objectForKey:newKey]) {
        [_preferences setObject:oldValue forKey:newKey];
        if(![[_preferences objectForKey:newKey] isEqual:oldValue]) return NO;
    }
    [_preferences removeObjectForKey:oldKey];
    return YES;
}

- (void)_registerOption:(NSString *)key
            translation:(NSString *)translation
           defaultValue:(id)defaultValue
             lowerLimit:(float)lower
             upperLimit:(float)upper {
    ARIOption *option = [[ARIOption alloc] initWithKey:key
                                           translation:translation
                                          defaultValue:defaultValue
                                            lowerLimit:lower
                                            upperLimit:upper];
    if(option.accessibleWithEditor)
        [_orderedSettingKeys addObject:option.settingKey];
    [_optionsRegistry setObject:option forKey:option.settingKey];
}

// Runtime manager methods

- (void)updateLayoutForEditing:(BOOL)animated {
    NSString *editingLocation = [ARIEditManager sharedInstance].editingLocation;
    if(!editingLocation) return;

    if([editingLocation isEqualToString:@"pagedot"]) {
        // The metrics pointee changes across iOS releases. Reapply the absolute
        // offset from the last system-produced frame instead of fabricating a
        // private structure or invoking SpringBoard's method with NULL.
        [[self rootFolderView] _atriaApplyPageControlOffset];
        return;
    }

    BOOL updateRoot = [editingLocation isEqualToString:@"hs"] || [editingLocation isEqualToString:@"label"] || [editingLocation isEqualToString:@"blur"];
    [self updateLayoutForRoot:updateRoot forDock:[editingLocation isEqualToString:@"dock"] animated:animated];
}

// Updates all layout

- (void)updateLayoutForRoot:(BOOL)forRoot forDock:(BOOL)forDock animated:(BOOL)animated {
    SBRootFolderView *rootFolderView = [self rootFolderView];

    void (^updateVisibleIcons)(BOOL finished) = ^void(BOOL finished) {
        if(!forRoot) return;
        SBIconListView *current = [self currentListView];
        // Update visible columns and rows for current list view. Otherwise, SB doesn't
        // update this until we start scrolling
        if([current respondsToSelector:@selector(setVisibleColumnRange:)])
            [current setVisibleColumnRange:NSMakeRange(0, [self intValueForKey:@"hs_columns" forListView:current])];
        if([current respondsToSelector:@selector(setVisibleRowRange:)])
            [current setVisibleRowRange:NSMakeRange(0, [self intValueForKey:@"hs_rows" forListView:current])];
    };

    void (^applyLayout)() = ^void() {
        if(!rootFolderView) return;
        if(forDock) {
            // Layout dock icons and set alpha
            if(![[self class] isUsingFloatingDock]) {
                SBIconListView *listView = (SBIconListView *)ARISafeValueForKey(rootFolderView, @"_dockListView");
                SBDockView *dockView = [rootFolderView respondsToSelector:@selector(dockView)] ? [rootFolderView dockView] : nil;
                if([dockView respondsToSelector:@selector(_atriaUpdateDockForSettingsChanged)]) {
                    [dockView _atriaUpdateDockForSettingsChanged];
                }
                ARILayoutIconListView(listView);
            } else {
                SBFloatingDockController *fdController = ARIFloatingDockControllerSharedInstance();
                SBFloatingDockViewController *fdvc = [fdController respondsToSelector:@selector(floatingDockViewController)]
                    ? [fdController floatingDockViewController]
                    : (SBFloatingDockViewController *)ARISafeValueForKey(fdController, @"_viewController");
                SBFloatingDockView *dockView = [fdvc respondsToSelector:@selector(dockView)]
                    ? [fdvc dockView]
                    : (SBFloatingDockView *)ARISafeValueForKey(fdvc, @"_dockView");
                // Icon list and suggestions
                SBIconListView *userListView = [fdController respondsToSelector:@selector(userIconListView)]
                    ? [fdController userIconListView]
                    : (SBIconListView *)ARISafeValueForKey(dockView, @"_userIconListView");
                SBIconListView *suggestionsListView = [fdController respondsToSelector:@selector(suggestionsIconListView)]
                    ? [fdController suggestionsIconListView]
                    : (SBIconListView *)ARISafeValueForKey(dockView, @"_recentIconListView");
                ARILayoutIconListView(userListView);
                ARILayoutIconListView(suggestionsListView);
                // Fix for library pod icon
                SBIconView *libraryPodIconView = [fdvc respondsToSelector:@selector(libraryPodIconView)]
                    ? [fdvc libraryPodIconView]
                    : nil;
                if([libraryPodIconView respondsToSelector:@selector(_atriaUpdateIconContentScale)]) {
                    [libraryPodIconView _atriaUpdateIconContentScale];
                }
                // Update dock background
                if([dockView respondsToSelector:@selector(_atriaUpdateDockForSettingsChanged)]) {
                    [dockView _atriaUpdateDockForSettingsChanged];
                }
            }
        }

        if(forRoot) {
            // Enumerate list views in root and lay them out as well
            for(SBIconListView *listView in [self allRootListViews]) {
                ARILayoutIconListView(listView);
            }
        }
    };

    // If we want animation, pass the block here. Otherwise, call the block directly
    if(animated) {
        [UIView animateWithDuration:0.6f
                              delay:0.0f
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:applyLayout
                         completion:updateVisibleIcons];
    } else {
        applyLayout();
        updateVisibleIcons(YES);
    }
}

// This lags the device somewhat, so limit this as much as possible!
- (void)relayoutEntireIconModel {
    // This will cause the entire icon model to re-layout.
    id iconController = ARIIconControllerSharedInstance();
    SBHIconManager *iconManager = [iconController respondsToSelector:@selector(iconManager)] ? [iconController iconManager] : nil;
    SBIconListModel *iconModel = [iconManager respondsToSelector:@selector(iconModel)] ? [iconManager iconModel] : nil;
    if([iconModel respondsToSelector:@selector(layout)]) [iconModel layout];
    // In order to fix custom widget sizing, refresh only root list views. Dock
    // geometry is view-owned; changing its model here regressed iOS 15 drags.
    [self updateLayoutForRoot:YES forDock:NO animated:NO];
}

// Util

- (void)feedbackForButton {
    static UIImpactFeedbackGenerator *generator = nil;
    if(!generator) generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft];
    [generator impactOccurred];
}

- (void)onSpringboardLaunched {
    // Floating-dock support is safe to query only after SpringBoard launches.
    // Match upstream Atria by changing the option default at this point.
    if([self boolValueForKey:@"forceFloatingDock"] || [[self class] isUsingFloatingDock]) {
        [self _registerOption:@"dock_columns"
                  translation:@"Columns"
                 defaultValue:@(15) // iPad Pro dock icon limit
                   lowerLimit:2.0F
                   upperLimit:20.0F];
        [self relayoutEntireIconModel];
    }

    if([[self class] isUsingFloatingDock]) {
        // Floating-dock support is detected after launch, so refresh its background now.
        SBFloatingDockController *fdController = ARIFloatingDockControllerSharedInstance();
        SBFloatingDockViewController *fdvc = [fdController respondsToSelector:@selector(floatingDockViewController)]
            ? [fdController floatingDockViewController]
            : (SBFloatingDockViewController *)ARISafeValueForKey(fdController, @"_viewController");
        SBFloatingDockView *dockView = [fdvc respondsToSelector:@selector(dockView)]
            ? [fdvc dockView]
            : (SBFloatingDockView *)ARISafeValueForKey(fdvc, @"_dockView");
        if([dockView respondsToSelector:@selector(_atriaUpdateDockForSettingsChanged)]) {
            [dockView _atriaUpdateDockForSettingsChanged];
        }
    }
}

- (SBRootFolderView *)rootFolderView {
    id iconController = ARIIconControllerSharedInstance();
    if([iconController respondsToSelector:@selector(_rootFolderController)]) {
        id rootFolderController = [iconController _rootFolderController];
        if([rootFolderController respondsToSelector:@selector(rootFolderView)]) {
            SBRootFolderView *rootFolderView = [rootFolderController rootFolderView];
            if(rootFolderView) return rootFolderView;
        }
    }

    // Future SpringBoard versions may move ownership again. Fall back to the
    // live home-screen hierarchy instead of messaging an assumed controller.
    Class rootFolderViewClass = objc_getClass("SBRootFolderView");
    UIApplication *application = [UIApplication sharedApplication];
    for(UIWindow *window in application.windows) {
        SBRootFolderView *rootFolderView = (SBRootFolderView *)ARIFindSubviewOfClass(window, rootFolderViewClass);
        if(rootFolderView) return rootFolderView;
    }
    return nil;
}

- (NSArray<SBIconListView *> *)allRootListViews {
    SBRootFolderView *rootFolderView = [self rootFolderView];
    id listViews = [rootFolderView respondsToSelector:@selector(iconListViews)]
        ? rootFolderView.iconListViews
        : nil;
    return [listViews isKindOfClass:[NSArray class]] ? listViews : @[];
}

- (SBIconListView *)userDockListView {
    return ARIUserDockListView([self rootFolderView]);
}

- (void)registerPersistentUserDockListView:(SBIconListView *)listView {
    if(!listView) return;
    _persistentUserDockListView = listView;
}

- (BOOL)isPersistentUserDockModel:(SBIconListModel *)model {
    if(!model) return NO;
    // Dock reset validation must never identify suggestions or another
    // transient list as the persistent user Dock. Read only existing backing
    // ivars here: the folder's Dock getter is lazy on iOS 15.
    id folder = ARIExistingObjectIvar(model, "_folder");
    id folderDock = ARIExistingObjectIvar(folder, "_dock");
    if(folderDock == model) return YES;

    SBIconListView *listView = _persistentUserDockListView;
    SBIconListModel *liveModel = [listView respondsToSelector:@selector(model)]
        ? [listView model]
        : nil;
    NSString *liveLocation = [listView.iconLocation isKindOfClass:[NSString class]]
        ? listView.iconLocation
        : nil;
    if(liveLocation.length > 0 &&
       ![liveLocation isEqualToString:@"SBIconLocationDock"] &&
       ![liveLocation isEqualToString:@"SBIconLocationFloatingDock"]) {
        return NO;
    }
    return liveModel != nil && liveModel == model;
}

- (NSUInteger)indexOfListView:(SBIconListView *)target {
    if(!target) return NSNotFound;
    return [[self allRootListViews] indexOfObject:target];
}

- (SBIconListView *)firstIconListView {
    SBRootFolderView *rootFolderView = [self rootFolderView];
    id listView = [rootFolderView respondsToSelector:@selector(firstIconListView)]
        ? [rootFolderView firstIconListView]
        : [self allRootListViews].firstObject;
    Class listViewClass = objc_getClass("SBIconListView");
    return [listView isKindOfClass:listViewClass] ? listView : nil;
}

- (SBIconListView *)currentListView {
    SBRootFolderView *rootFolderView = [self rootFolderView];
    id listView = nil;
    if([rootFolderView respondsToSelector:@selector(currentIconListView)]) {
        listView = [rootFolderView currentIconListView];
    }
    if(!listView) listView = [self allRootListViews].firstObject;
    Class listViewClass = objc_getClass("SBIconListView");
    return [listView isKindOfClass:listViewClass] ? listView : nil;
}

// Returns a string which serves as a prefix for per-page layout settings

- (NSString *)prefixForListView:(SBIconListView *)target {
    if(!target || !IconListIsRoot(target)) return @"";
    NSUInteger index = [self indexOfListView:target];
    if(index == NSNotFound) return @"";
    return [NSString stringWithFormat:@"Page%lu_", (unsigned long)index];
}

// Obtain information about available settings

- (NSOrderedSet<NSString *> *)editorSettingsKeys {
    return _orderedSettingKeys;
}

- (ARIOption *)getSettingByKey:(NSString *)key {
    return _optionsRegistry[key];
}

- (ARIOption *)_optionForPreferenceKey:(NSString *)key {
    if(![key isKindOfClass:[NSString class]] || key.length == 0) return nil;

    ARIOption *option = _optionsRegistry[key];
    if(option) return option;

    NSString *baseKey = nil;
    if(!ARIParsePagePreferenceKey(key, nil, &baseKey) || baseKey.length == 0) return nil;
    return _optionsRegistry[ARINormalizedPreferenceBaseKey(baseKey)];
}

- (id)_validatedPreferenceValue:(id)value forKey:(NSString *)key {
    ARIOption *option = [self _optionForPreferenceKey:key];
    if(!option) return value;

    id defaultValue = option.defaultValue;
    if([defaultValue isKindOfClass:[NSNumber class]]) {
        BOOL defaultIsBoolean = CFGetTypeID((__bridge CFTypeRef)defaultValue) == CFBooleanGetTypeID();
        if(defaultIsBoolean) {
            return [value isKindOfClass:[NSNumber class]] ? @([value boolValue]) : defaultValue;
        }

        if(![value isKindOfClass:[NSNumber class]]) return defaultValue;
        double number = [value doubleValue];
        if(!isfinite(number)) number = [defaultValue doubleValue];

        // Runtime meaning must not change merely because the editor's visual
        // control is switched. Every write path therefore uses the same hard
        // semantic range; the slider itself still exposes its original range.
        if(option.hardUpperLimit > option.hardLowerLimit) {
            number = fmax(option.hardLowerLimit,
                          fmin(option.hardUpperLimit, number));
        }
        if(option.isIntegralValue) {
            number = round(number);
        }
        return @(number);
    }

    if([defaultValue isKindOfClass:[NSString class]]) {
        return [value isKindOfClass:[NSString class]] ? value : defaultValue;
    }

    return value ?: defaultValue;
}

// Get/set preference values

- (int)intValueForKey:(NSString *)key {
    id value = [self rawValueForKey:key];
    return [value respondsToSelector:@selector(integerValue)] ? (int)[value integerValue] : 0;
}

- (BOOL)boolValueForKey:(NSString *)key {
    id value = [self rawValueForKey:key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

- (float)floatValueForKey:(NSString *)key {
    id value = [self rawValueForKey:key];
    return [value respondsToSelector:@selector(floatValue)] ? [value floatValue] : 0.0F;
}

- (id)rawValueForKey:(NSString *)key {
    if(![key isKindOfClass:[NSString class]] || key.length == 0) return nil;
    id value = [_preferences objectForKey:key];
    if(!value) return [self _optionForPreferenceKey:key].defaultValue;
    return [self _validatedPreferenceValue:value forKey:key];
}

- (void)setValue:(id)val forKey:(NSString *)key {
    if(![key isKindOfClass:[NSString class]] || key.length == 0) return;
    if(!val) {
        [self resetValueForKey:key];
        return;
    }

    id validatedValue = [self _validatedPreferenceValue:val forKey:key];
    if(!validatedValue) return;

    // Only global keys remove a value when it equals the default.  A per-page
    // key must remain explicit or later global edits would silently alter it.
    ARIOption *directOption = _optionsRegistry[key];
    if(directOption && [validatedValue isEqual:directOption.defaultValue]) {
        // Matches default value, remove from preferences
        [self resetValueForKey:key];
    } else {
        if(![validatedValue isEqual:[_preferences objectForKey:key]])
            [_preferences setObject:validatedValue forKey:key];
    }
}

- (void)resetValueForKey:(NSString *)key {
    if(![key isKindOfClass:[NSString class]] || key.length == 0) return;
    [_preferences removeObjectForKey:key];
}

// Get/set preference values by icon list view
// We try to locate value for the current list view, if it exists

- (int)intValueForKey:(NSString *)key forListView:(SBIconListView *)list {
    id value = [self rawValueForKey:key forListView:list];
    return [value respondsToSelector:@selector(integerValue)] ? (int)[value integerValue] : 0;
}

- (id)rawValueForKey:(NSString *)key forListView:(SBIconListView *)list {
    NSString *prefix = [self prefixForListView:list];
    if(prefix.length == 0) return [self rawValueForKey:key];
    BOOL independentPageValue = [key isEqualToString:@"pageLabelText"];
    if(!independentPageValue) {
        id storedPerPage = [_preferences objectForKey:@"_perPageListViews"];
        BOOL hasCustomConfig = [storedPerPage isKindOfClass:[NSArray class]] &&
            [(NSArray *)storedPerPage containsObject:prefix];
        if(!hasCustomConfig) return [self rawValueForKey:key];
    }
    NSString *pageKey = [prefix stringByAppendingString:key];
    id value = [_preferences objectForKey:pageKey];
    return value ? [self _validatedPreferenceValue:value forKey:pageKey] : [self rawValueForKey:key];
}

- (float)floatValueForKey:(NSString *)key forListView:(SBIconListView *)list {
    id value = [self rawValueForKey:key forListView:list];
    return [value respondsToSelector:@selector(floatValue)] ? [value floatValue] : 0.0F;
}

- (void)setValue:(id)val forKey:(NSString *)key forListView:(SBIconListView *)listView {
    if(!listView)
        [self setValue:val forKey:key];
    else {
        NSString *prefix = [self prefixForListView:listView];
        if(prefix.length == 0) return;
        [self setValue:val forKey:[prefix stringByAppendingString:key]];
    }
}

- (void)resetValueForKey:(NSString *)key forListView:(SBIconListView *)listView {
    if(!listView)
        [self resetValueForKey:key];
    else {
        NSString *prefix = [self prefixForListView:listView];
        if(prefix.length == 0) return;
        [self resetValueForKey:[prefix stringByAppendingString:key]];
    }
}

// Per-page layout creation/deletion and management

- (void)deleteCustomForListView:(SBIconListView *)listView {
    // Delete any keys for that list view
    NSString *prefix = [self prefixForListView:listView];
    if(prefix.length == 0) return;
    NSDictionary *preferences = [_preferences dictionaryRepresentation];
    NSString *pageLabelKey = [prefix stringByAppendingString:@"pageLabelText"];
    for(NSString *key in [preferences allKeys]) {
        if([key hasPrefix:prefix] && ![key isEqualToString:pageLabelKey]) {
            [self resetValueForKey:key];
        }
    }

    id storedPerPage = [self rawValueForKey:@"_perPageListViews"];
    NSMutableArray *perPage = [storedPerPage isKindOfClass:[NSArray class]]
        ? [storedPerPage mutableCopy]
        : [NSMutableArray new];
    [perPage removeObject:prefix];
    [self setValue:perPage forKey:@"_perPageListViews"];

    [self updateLayoutForEditing:YES];
}

- (void)createCustomForListView:(SBIconListView *)listView {
    // Freeze list view settings to what the current global config is
    NSString *prefix = [self prefixForListView:listView];
    if(prefix.length == 0) return;

    id storedPerPage = [self rawValueForKey:@"_perPageListViews"];
    NSMutableArray *perPage = [storedPerPage isKindOfClass:[NSArray class]]
        ? [storedPerPage mutableCopy]
        : [NSMutableArray new];
    if(![perPage containsObject:prefix]) [perPage addObject:prefix];
    [self setValue:perPage forKey:@"_perPageListViews"];

    for(NSString *key in _orderedSettingKeys) {
        [_preferences setObject:[self rawValueForKey:key]
                         forKey:[NSString stringWithFormat:@"%@%@", prefix, key]];
    }
    [self updateLayoutForEditing:YES];
}

- (BOOL)doesCustomConfigForListViewExist:(SBIconListView *)listView {
    NSString *prefix = [self prefixForListView:listView];
    if(prefix.length == 0) return NO;
    NSArray *perPage = [self rawValueForKey:@"_perPageListViews"];
    if(![perPage isKindOfClass:[NSArray class]]) return NO;
    return [perPage containsObject:prefix];
}

+ (UIInterfaceOrientation)currentDeviceOrientation {
    static UIInterfaceOrientation lastKnownOrientation = UIInterfaceOrientationPortrait;
    UIApplication *application = [UIApplication sharedApplication];
    UIWindowScene *scene = [ARITweakManager sharedInstance].rootFolderView.window.windowScene;

    if(!scene) {
        for(UIScene *candidate in application.connectedScenes) {
            if(![candidate isKindOfClass:[UIWindowScene class]]) continue;
            if(candidate.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)candidate;
                break;
            }
        }
    }

    if(!scene) {
        for(UIWindow *window in application.windows) {
            if(window.isKeyWindow && window.windowScene) {
                scene = window.windowScene;
                break;
            }
        }
    }

    UIInterfaceOrientation orientation = scene.interfaceOrientation;
    if(orientation != UIInterfaceOrientationUnknown) lastKnownOrientation = orientation;
    return lastKnownOrientation;
}

+ (BOOL)isUsingFloatingDock {
    Class controllerClass = objc_getClass("SBFloatingDockController");
    return [controllerClass respondsToSelector:@selector(isFloatingDockSupported)]
        ? [controllerClass isFloatingDockSupported]
        : NO;
}

+ (void)dismissFloatingDockIfPossible {
    if([self isUsingFloatingDock]) {
        SBFloatingDockController *controller = ARIFloatingDockControllerSharedInstance();
        if([controller respondsToSelector:@selector(_dismissFloatingDockIfPresentedAnimated:completionHandler:)]) {
            [controller _dismissFloatingDockIfPresentedAnimated:YES completionHandler:nil];
        }
    }
}

+ (void)presentFloatingDockIfPossible {
    if([self isUsingFloatingDock]) {
        SBFloatingDockController *controller = ARIFloatingDockControllerSharedInstance();
        if([controller respondsToSelector:@selector(_presentFloatingDockIfDismissedAnimated:completionHandler:)]) {
            [controller _presentFloatingDockIfDismissedAnimated:YES completionHandler:nil];
        }
    }
}

@end

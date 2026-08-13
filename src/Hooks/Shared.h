//
// Created by ren7995 on 2021-04-25 12:49:18
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class SBIconListView;

// AppLibrary = SBIconLocationAppLibrary
// Root = SBIconLocationRoot OR SBIconLocationRootWithWidgets
// Dock = SBIconLocationDock OR SBIconLocationFloatingDock
// AppLibraryPod = SBIconLocationAppLibraryCategoryPod OR SBIconLocationAppLibraryCategoryPodExpanded
// TodayView = SBIconLocationTodayView
// Folder = SBIconLocationFolder

#define IsLocationRoot(x) [x containsString:@"SBIconLocationRoot"]
#define IsLocationFloatingDock(x) [x isEqualToString:@"SBIconLocationFloatingDock"]
#define IsLocationFloatingDockSuggestions(x) [x isEqualToString:@"SBIconLocationFloatingDockSuggestions"]
#define IsLocationFloatingDockContent(x) (IsLocationFloatingDock(x) || IsLocationFloatingDockSuggestions(x))
#define IsLocationDock(x) ([x isEqualToString:@"SBIconLocationDock"] || IsLocationFloatingDock(x))
#define IsLocationAppLibrary(x) [x isEqualToString:@"SBIconLocationAppLibrary"]
#define IsLocationAppLibraryPod(x) [x containsString:@"SBIconLocationAppLibraryCategoryPod"]
#define IsLocationFolder(x) [x isEqualToString:@"SBIconLocationFolder"]

#define IconListIsRoot(x) IsLocationRoot(x.iconLocation)
#define IconListIsDock(x) IsLocationDock(x.iconLocation)

#define IconIsInRoot(x) IsLocationRoot(x.location)
#define IconIsInDock(x) IsLocationDock(x.location)
#define IconIsInFloatingDockContent(x) IsLocationFloatingDockContent(x.location)
#define IconIsInAppLibrary(x) IsLocationAppLibrary(x.location)
#define IconIsInAppLibraryPod(x) IsLocationAppLibraryPod(x.location)
#define IconIsInFolder(x) IsLocationFolder(x.location)

/// True only for the concrete layout-provider instance owned by App Library.
/// Keeping this identity out-of-band avoids replacing SpringBoard's configured
/// provider object on releases where the property is readonly.
FOUNDATION_EXPORT BOOL ARIIsAppLibraryLayoutProvider(id provider);

/// Records the concrete host location used by the Floating Dock placement
/// interoperability boundary. The implementation is a no-op for nil models.
FOUNDATION_EXPORT void ARIObserveFloatingDockPlacementHost(SBIconListView *listView);

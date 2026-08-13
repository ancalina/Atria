//
// Created by ren7995 on 2021-04-25 12:49:12
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdint.h>

#import "../Options/ARIOption.h"

typedef struct SBHIconGridSize {
    uint16_t width;
    uint16_t height;
} SBHIconGridSize;

// This is the struct definition for iOS 14-15
// Note that on iOS 16, the fields are reversed
typedef struct SBIconCoordinate {
    NSInteger row;
    NSInteger col;
} SBIconCoordinate;

typedef struct SBHIconGridSizeClassSizes {
    struct SBHIconGridSize small;
    struct SBHIconGridSize medium;
    struct SBHIconGridSize large;
    struct SBHIconGridSize extraLarge;
} SBHIconGridSizeClassSizes;

@interface SBIcon : NSObject
- (id)application;
@end

@interface SBDockView : UIView
- (void)setBackgroundAlpha:(CGFloat)alpha;
- (void)_atriaUpdateDockForSettingsChanged;
@end

@class SBIconListView;
@interface SBIconListModel : NSObject
@property (nonatomic, strong) NSString *_atriaLocation;
@property (nonatomic, strong) id folder;
- (SBIconListView *)_atriaListView;
- (void)_atriaUpdateModelGridSizes;
- (struct SBHIconGridSize)gridSize;
- (void)setGridSize:(struct SBHIconGridSize)gridSize;
- (NSUInteger)maxNumberOfIcons;
- (NSArray *)icons;
- (void)layout;
- (id)gridCellInfoForGridSize:(struct SBHIconGridSize)gridSize
                       options:(NSUInteger)options;
@end

@class SBSApplicationShortcutItem;
@interface SBIconView : UIView
@property (nonatomic, strong) SBIconListView *_atriaLastIconListView;
@property (nonatomic, strong) id icon;
@property (nonatomic, strong) UIView *contentContainerView;
@property (nonatomic, assign) BOOL allowsLabelArea;
@property (nonatomic, assign) CGFloat iconContentScale;
@property (nonatomic, assign) CGFloat iconLabelAlpha;
@property (nonatomic, assign, getter=isIconContentScalingEnabled) BOOL iconContentScalingEnabled;
@property (nonatomic, strong) NSString *location;
- (void)_updateIconImageViewAnimated:(BOOL)arg1;
- (void)_updateLabelArea;
- (BOOL)isFolderIcon;
- (CGFloat)iconImageCornerRadius;
- (void)_atriaUpdateIconContentScale;
- (void)_atriaSetupDropShadow:(BOOL)isEditing;
- (void)_atriaGenerateDropShadow:(CGRect)rect;
- (SBSApplicationShortcutItem *)_atriaGenerateItemWithTitle:(NSString *)title type:(NSString *)type;
@end

@interface SBIconListGridLayoutConfiguration : NSObject
@property (nonatomic, readwrite, assign) NSUInteger numberOfPortraitColumns;
@property (nonatomic, readwrite, assign) NSUInteger numberOfPortraitRows;
@property (nonatomic, readwrite, assign) NSUInteger numberOfLandscapeColumns;
@property (nonatomic, readwrite, assign) NSUInteger numberOfLandscapeRows;
@property (nonatomic, readwrite, assign) UIEdgeInsets portraitLayoutInsets;
@property (nonatomic, readwrite, assign) UIEdgeInsets landscapeLayoutInsets;
@end

@interface SBIconListFlowExtendedLayout : NSObject
@property (nonatomic, strong) SBIconListGridLayoutConfiguration *layoutConfiguration;
- (id)initWithLayoutConfiguration:(SBIconListGridLayoutConfiguration *)config;
@end

@interface SBIconListViewLayoutMetrics : NSObject
@property (nonatomic, assign) UIEdgeInsets iconInsets;
@property (nonatomic, assign) CGSize alignmentIconSize;
@property (nonatomic, assign) CGFloat iconContentScale;
@end

@class SBIcon;
@class ARILabelView;
@class ARIBackgroundView;
@interface SBIconListView : UIView
@property (nonatomic, assign, getter=isEditing) BOOL editing;
@property (nonatomic, strong) NSString *iconLocation;
@property (nonatomic, assign) SBIconListFlowExtendedLayout *layout;
@property (nonatomic, assign) CGFloat iconContentScale;
@property (nonatomic, assign) UIEdgeInsets additionalLayoutInsets;

@property (nonatomic, strong) ARILabelView *_atriaPageLabel;
@property (nonatomic, strong) ARIBackgroundView *_atriaBackground;
@property (nonatomic, strong) UITapGestureRecognizer *_atriaTap;
@property (nonatomic, strong) SBIconListFlowExtendedLayout *_atriaCachedLayout;
@property (nonatomic, strong) SBIconListFlowExtendedLayout *_originalLayout;
@property (nonatomic, assign) BOOL _atriaNeedsLayout;
- (void)_atriaBeginEditing;
- (void)_atriaUpdateLayoutCache;

- (NSArray<SBIconView *> *)icons;
- (SBIconListViewLayoutMetrics *)layoutMetrics;
- (SBIcon *)iconAtCoordinate:(struct SBIconCoordinate)co metrics:(id)metrics;
- (struct SBIconCoordinate)coordinateForIcon:(id)icon;
- (CGPoint)originForIconAtCoordinate:(struct SBIconCoordinate)co metrics:(id)metrics;
- (CGPoint)_alignedIconPointForPoint:(CGPoint)point;
- (CGPoint)centerForIconCoordinate:(struct SBIconCoordinate)co metrics:(id)metrics;
- (CGRect)rectForDefaultSizedCellsOfSize:(struct SBHIconGridSize)size
				   startingAtCoordinate:(struct SBIconCoordinate)coordinate
				   metrics:(id)metrics;
- (CGSize)effectiveIconSpacing;
- (SBIconListModel *)model;
- (void)setVisibleColumnRange:(NSRange)range;
- (void)setVisibleRowRange:(NSRange)range;
- (void)layoutIconsNow;
- (void)layoutIconsIfNeeded;
@end

@interface SBRootFolderView : UIView
@property (nonatomic, readonly, strong) NSArray<SBIconListView *> *iconListViews;
@property (nonatomic, strong) UIView *pageControl; // SBIconListPageControl
@property (nonatomic, strong) UIView *scrollAccessoryView;
- (void)_atriaApplyPageControlOffset;
- (SBIconListView *)currentIconListView;
- (SBIconListView *)firstIconListView;
- (SBDockView *)dockView;
@end

@interface SBRootFolderController : UIViewController
- (SBRootFolderView *)rootFolderView;
@end

@interface SBHIconManager : NSObject
@property (nonatomic, assign, getter=isEditing) BOOL editing;
- (SBIconListModel *)iconModel;
- (BOOL)relayout;
@end

@interface SBFloatingDockView : UIView
@property (nonatomic, strong) UIView *backgroundView;
- (void)_atriaUpdateDockForSettingsChanged;
@end

@interface SBFloatingDockViewController : UIViewController
- (SBFloatingDockView *)dockView;
- (SBIconView *)libraryPodIconView;
@end

@interface SBFloatingDockController : NSObject
- (id)initWithIconController:(id)arg1;                      // iOS 13-15
- (id)initWithWindowScene:(id)arg1 iconController:(id)arg2; // iOS 16+
- (void)_dismissFloatingDockIfPresentedAnimated:(BOOL)arg1 completionHandler:(id)arg2;
- (void)_presentFloatingDockIfDismissedAnimated:(BOOL)arg1 completionHandler:(id)arg2;
- (SBIconListView *)userIconListView;
- (SBIconListView *)suggestionsIconListView;
- (SBFloatingDockViewController *)floatingDockViewController;
+ (BOOL)isFloatingDockSupported;
+ (SBFloatingDockController *)_atriaSharedInstance;
@end

// UIViewController through iOS 16; a controller/coordinator object on iOS 17+.
@interface SBIconController : NSObject
- (SBFloatingDockController *)floatingDockController; // iOS 13-15 only (does not exist on 16)
- (SBRootFolderController *)_rootFolderController;
- (SBHIconManager *)iconManager;
+ (SBIconController *)sharedInstance;
@end

@interface ARITweakManager : NSObject
@property (nonatomic, readonly, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly, strong) NSUserDefaults *preferences;
@property (nonatomic, readonly, strong) NSMapTable *listViewModelMap;
@property (nonatomic, readonly, assign, getter=isDeviceIPad) BOOL deviceIPad;
@property (nonatomic, readonly, assign, getter=isShyLabelsInstalled) BOOL shyLabelsInstalled;
- (void)updateLayoutForEditing:(BOOL)animated;
- (void)updateLayoutForRoot:(BOOL)forRoot forDock:(BOOL)forDock animated:(BOOL)animated;
- (void)relayoutEntireIconModel;
- (void)feedbackForButton;
- (void)onSpringboardLaunched;
- (NSUInteger)indexOfListView:(SBIconListView *)target;
- (SBRootFolderView *)rootFolderView;
- (NSArray<SBIconListView *> *)allRootListViews;
- (SBIconListView *)userDockListView;
- (void)registerPersistentUserDockListView:(SBIconListView *)listView;
- (BOOL)isPersistentUserDockModel:(SBIconListModel *)model;
- (NSString *)prefixForListView:(SBIconListView *)target;
- (SBIconListView *)currentListView;
- (SBIconListView *)firstIconListView;

// Obtain information about available settings
- (NSOrderedSet<NSString *> *)editorSettingsKeys;
- (ARIOption *)getSettingByKey:(NSString *)key;

// Get/set preference values
- (int)intValueForKey:(NSString *)key;
- (float)floatValueForKey:(NSString *)key;
- (BOOL)boolValueForKey:(NSString *)key;
- (id)rawValueForKey:(NSString *)key;
- (void)setValue:(id)val forKey:(NSString *)key;
- (void)resetValueForKey:(NSString *)key;

// Get/set preference values by icon list view
- (int)intValueForKey:(NSString *)key forListView:(SBIconListView *)list;
- (id)rawValueForKey:(NSString *)key forListView:(SBIconListView *)list;
- (float)floatValueForKey:(NSString *)key forListView:(SBIconListView *)list;
- (void)setValue:(id)val forKey:(NSString *)key forListView:(SBIconListView *)listView;
- (void)resetValueForKey:(NSString *)key forListView:(SBIconListView *)listView;

// Per-page layout creation/deletion and management
- (void)deleteCustomForListView:(SBIconListView *)listView;
- (void)createCustomForListView:(SBIconListView *)listView;
- (BOOL)doesCustomConfigForListViewExist:(SBIconListView *)listView;

+ (instancetype)sharedInstance;
+ (UIInterfaceOrientation)currentDeviceOrientation;
+ (BOOL)isUsingFloatingDock;
+ (void)dismissFloatingDockIfPossible;
+ (void)presentFloatingDockIfPossible;
@end

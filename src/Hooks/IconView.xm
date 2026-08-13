//
// Created by ren7995 on 2021-04-25 12:49:37
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"
#import "../Manager/ARIEditManager.h"

#include <objc/message.h>
#include <objc/runtime.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

static const char *ARIIconUnqualifiedTypeEncoding(const char *encoding) {
	while(encoding && *encoding && strchr("rnNoORV", *encoding)) encoding++;
	return encoding;
}

static BOOL ARIIconTypeMatches(const char *encoding, char expectedKind,
							   NSUInteger expectedSize) {
	const char *unqualified = ARIIconUnqualifiedTypeEncoding(encoding);
	if(!unqualified || *unqualified != expectedKind) return NO;
	if(expectedKind == 'v') return expectedSize == 0;

	NSUInteger actualSize = 0;
	NSGetSizeAndAlignment(unqualified, &actualSize, NULL);
	return actualSize == expectedSize;
}

static BOOL ARIIconMethodMatchesVoidObjectABI(Class cls, SEL selector,
										  BOOL classMethod,
										  NSUInteger objectArgumentCount) {
	if(!cls || !selector) return NO;
	Method method = classMethod
		? class_getClassMethod(cls, selector)
		: class_getInstanceMethod(cls, selector);
	if(!method || method_getNumberOfArguments(method) != objectArgumentCount + 2)
		return NO;

	char *returnType = method_copyReturnType(method);
	BOOL matches = ARIIconTypeMatches(returnType, 'v', 0);
	free(returnType);
	if(!matches) return NO;

	for(NSUInteger index = 0; index < objectArgumentCount; index++) {
		char *argumentType = method_copyArgumentType(
			method, (unsigned int)index + 2);
		matches = ARIIconTypeMatches(argumentType, '@', sizeof(id));
		free(argumentType);
		if(!matches) return NO;
	}
	return YES;
}

static id ARIObjectByCallingNoArgumentSelector(id object, SEL selector) {
	if(!object || !selector || ![object respondsToSelector:selector]) return nil;

	Method method = class_getInstanceMethod(object_getClass(object), selector);
	if(!method || method_getNumberOfArguments(method) != 2) return nil;

	char *returnType = method_copyReturnType(method);
	BOOL returnsObject = ARIIconTypeMatches(returnType, '@', sizeof(id));
	free(returnType);
	if(!returnsObject) return nil;

	return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static id ARIIconControllerSharedInstance(void) {
	Class controllerClass = objc_getClass("SBIconController");
	return [controllerClass respondsToSelector:@selector(sharedInstance)]
		? [controllerClass sharedInstance]
		: nil;
}

@interface SBIconImageView : UIView
@end

@interface SBFolderIconImageView : SBIconImageView
@end

@interface SBSApplicationShortcutIcon : NSObject
@end

@interface SBSApplicationShortcutItem : NSObject
@property (nonatomic, retain) NSString *type;
@property (nonatomic, copy) NSString *localizedTitle;
- (void)setIcon:(SBSApplicationShortcutIcon *)arg1;
@end

@interface SBSApplicationShortcutCustomImageIcon : SBSApplicationShortcutIcon
- (id)initWithImagePNGData:(id)arg1;
@end

@interface SBHIconViewApplicationShortcutsContextMenuProvider : NSObject
+ (void)activateShortcut:(SBSApplicationShortcutItem *)item
	withBundleIdentifier:(NSString *)bundleID
	forIconView:(SBIconView *)iconView;
@end

static BOOL ARIHandleEditorShortcut(SBSApplicationShortcutItem *item) {
	id rawType = ARIObjectByCallingNoArgumentSelector(item, @selector(type));
	if(![rawType isKindOfClass:[NSString class]]) return NO;

	NSString *type = (NSString *)rawType;
	NSString *prefix = @"me.lau.atria.edit.";
	if(![type hasPrefix:prefix] || type.length <= prefix.length) return NO;

	NSString *location = [type substringFromIndex:prefix.length];
	[[ARIEditManager sharedInstance] toggleEditView:YES
							  withTargetLocation:location];
	return YES;
}

%hook SBIconView
// I hope this doesn't cause issues
%property (nonatomic, strong) SBIconListView *_atriaLastIconListView;

- (CGFloat)iconContentScale {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	// Fixes folder icon bug on open
	CGFloat orig = %orig;
	if([self isFolderIcon]) {
		if(IconIsInRoot(self)) {
			return [manager floatValueForKey:@"hs_iconScale" forListView:self._atriaLastIconListView];
		} else if(IconIsInDock(self)) {
			return [manager floatValueForKey:@"dock_iconScale"];
		}
	}

	return orig;
}

- (void)setAllowsLabelArea:(BOOL)allows {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	if([manager isShyLabelsInstalled]) {
		%orig(allows);
		return;
	}

	if(IconIsInRoot(self)) {
	    	if([manager boolValueForKey:@"hideLabels"]) allows = NO;
	} else if(IconIsInAppLibrary(self) || IconIsInAppLibraryPod(self)) {
		if([manager boolValueForKey:@"hideLabelsAppLibrary"]) allows = NO;
	} else if(IconIsInFolder(self)) {
		if([manager boolValueForKey:@"hideLabelsFolders"]) allows = NO;
	}
	%orig(allows);
}

- (void)_updateIconImageViewAnimated:(BOOL)arg1 {
	%orig(arg1);
	[self _atriaUpdateIconContentScale];
}

- (void)setIconContentScale:(CGFloat)scale {
	%orig(scale);
	[self _atriaUpdateIconContentScale];
}

%new
- (void)_atriaUpdateIconContentScale {
	// Reset icon content scale
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	CATransform3D old = self.layer.sublayerTransform;

	// Scale only SpringBoard's concrete user/suggestions Dock locations. A
	// substring match could accidentally classify an independently managed
	// custom icon location as Atria's Dock.
	BOOL inDock = IconIsInDock(self) || IconIsInFloatingDockContent(self);
	BOOL inRoot = IconIsInRoot(self);
	BOOL scaleFolder = IconIsInFolder(self) &&
		[manager boolValueForKey:@"scaleInsideFolders"];
	if(!(inDock || inRoot || scaleFolder)) {
		if(old.m11 != 1 || old.m22 != 1) self.layer.sublayerTransform = CATransform3DMakeScale(1, 1, 1);
		return;
	}

	CGFloat customScale = 1;
	BOOL isWidget = [self.icon isKindOfClass:objc_getClass("SBWidgetIcon")];
	if(isWidget) {
		customScale = [manager floatValueForKey:@"hs_widgetIconScale" forListView:self._atriaLastIconListView];
	} else {
		if(inRoot || scaleFolder) {
			customScale = [manager floatValueForKey:@"hs_iconScale" forListView:self._atriaLastIconListView];
		} else if(inDock) {
			customScale = [manager floatValueForKey:@"dock_iconScale"];
		}
	}

	// "Returns a transform that scales by (sx, sy, sz)."
	// By doing this, we essentially make sure that any icon animations
	// also respect our scaling (since sublayerTransform is set for our icon layer)
	if(old.m11 == customScale && old.m22 == customScale) return;

	void (^resize)() = ^void() {
		self.layer.sublayerTransform = CATransform3DMakeScale(
			customScale,
			customScale,
			1);
	};

	// Animate if in edit mode
	if([ARIEditManager sharedInstance].isEditing) {
		// Stupid Core Animation
		[CATransaction begin];
		[CATransaction setAnimationDuration:0.2f];
		// Setup animation to and from
		CATransform3D from = self.layer.sublayerTransform;
		CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"sublayerTransform"];
		animation.fromValue = [NSValue value:&from withObjCType:@encode(CATransform3D)];
		resize();
		CATransform3D to = self.layer.sublayerTransform;
		animation.toValue = [NSValue value:&to withObjCType:@encode(CATransform3D)];
		// Add completion handler (must be done before adding animation to layer)
		[CATransaction setCompletionBlock:^{ [self _atriaGenerateDropShadow:self.bounds]; }];
		// Add animation to layer and commit
		[self.layer addAnimation:animation forKey:animation.keyPath];
		[CATransaction commit];
	} else {
		// Resize and update drop shadow immediately
		resize();
		[self _atriaGenerateDropShadow:self.bounds];
	}
}

- (void)didMoveToSuperview {
	%orig;
	if(self.superview && [self.superview isKindOfClass:objc_getClass("SBIconListView")]) {
		self._atriaLastIconListView = (SBIconListView *)self.superview;
		// Update allowsLabelArea
		[self setAllowsLabelArea:self.allowsLabelArea];
	}
	id iconController = ARIIconControllerSharedInstance();
	SBHIconManager *iconManager = [iconController respondsToSelector:@selector(iconManager)] ? [iconController iconManager] : nil;
	BOOL isEditing = [iconManager respondsToSelector:@selector(isEditing)] ? iconManager.isEditing : NO;
	[self _atriaSetupDropShadow:isEditing];
	// Reapply Atria's transform directly. Calling SpringBoard's private image
	// refresh selector here would turn a future selector removal into a missing
	// %orig call merely because the icon changed superviews.
	[self _atriaUpdateIconContentScale];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
	[self _atriaSetupDropShadow:editing];
	%orig(editing, animated);
}

%new
- (void)_atriaGenerateDropShadow:(CGRect)rect {
	if(self.layer.shadowRadius > 0.0F) {
		CGFloat width = rect.size.width;
		CGFloat height = rect.size.height;
		CGFloat scaleX = fabs(self.layer.sublayerTransform.m11);
		CGFloat scaleY = fabs(self.layer.sublayerTransform.m22);
		if(!isfinite(scaleX)) scaleX = 1.0F;
		if(!isfinite(scaleY)) scaleY = 1.0F;
		CGFloat scaledWidth = width * scaleX;
		CGFloat scaledHeight = height * scaleY;
		CGRect scaledRect = CGRectInset(rect, 
			(width - scaledWidth) / 2.0F,
			(height - scaledHeight) / 2.0F);
		CGFloat cornerRadius = [self iconImageCornerRadius] * MIN(scaleX, scaleY);
		self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:scaledRect cornerRadius:cornerRadius].CGPath;
	}
}

%new
- (void)_atriaSetupDropShadow:(BOOL)isEditing {
	BOOL enabled = [[ARITweakManager sharedInstance] boolValueForKey:@"dropShadow"];
	// Avoid private-method inspection for the default disabled state and for
	// cases where Atria cannot apply a stable shadow anyway.
	if(!enabled || isEditing || IconIsInFloatingDockContent(self)) {
		self.layer.shadowOpacity = 0.0F;
		self.layer.shadowRadius = 0.0F;
		return;
	}
	SBIcon *icon = [self icon];
	BOOL isApplicationIcon =
		ARIObjectByCallingNoArgumentSelector(icon, @selector(application)) != nil;
	BOOL widgetOrAppIcon = isApplicationIcon ||
		[icon isKindOfClass:objc_getClass("SBWidgetIcon")] ||
		[icon isKindOfClass:objc_getClass("SBBookmarkIcon")];
	// Don't apply shadows in SpringBoard's floating user/suggestions Dock,
	// because its dynamic icon scaling makes the shadow geometry unstable.
	if(widgetOrAppIcon) {
		if(self.layer.shadowRadius > 0.0F) return;
		self.layer.masksToBounds = NO;
		self.layer.shadowOpacity = 0.4F;
		self.layer.shadowRadius = 5.0F;
		self.layer.shadowColor = [UIColor blackColor].CGColor;
		self.layer.drawsAsynchronously = YES;
		[self _atriaGenerateDropShadow:self.bounds];
	} else {
		self.layer.shadowOpacity = 0.0F;
		self.layer.shadowRadius = 0.0F;
	}
}

- (void)setBounds:(CGRect)arg1 {
	%orig(arg1);
	[self _atriaGenerateDropShadow:arg1];
}

%new
- (SBSApplicationShortcutItem *)_atriaGenerateItemWithTitle:(NSString *)title type:(NSString *)type {
	SBSApplicationShortcutItem *item = [[objc_getClass("SBSApplicationShortcutItem") alloc] init];
	item.localizedTitle = title;
	item.type = type;

	// SFSymbols
	UIImage *image = [UIImage systemImageNamed:@"gear"];

	// Tint our image
	image = [image imageWithTintColor:[UIColor labelColor]];

	// Get data respresentation of the image
	NSData *iconData = UIImagePNGRepresentation(image);
	SBSApplicationShortcutCustomImageIcon *icon = [[objc_getClass("SBSApplicationShortcutCustomImageIcon") alloc] initWithImagePNGData:iconData];
	[item setIcon:icon];

	return item;
}

- (NSArray *)applicationShortcutItems {
	if([[ARITweakManager sharedInstance] boolValueForKey:@"hide3DTouchActions"] || [self isFolderIcon]) return %orig;

	// Add shortcut item to activate editor
	// I found this really cool gist to allow me to do this, tyvm to the author <3
	// Link: https://gist.github.com/MTACS/8e26c4f430b27d6a1d2a11f0a828f250
	NSMutableArray *items = [%orig mutableCopy];
	if(!(IconIsInRoot(self) || IconIsInDock(self))) return items;
	if(!items) items = [NSMutableArray new];

	if(IconIsInRoot(self)) {
		[items addObject:[self _atriaGenerateItemWithTitle:@"홈화면 편집" type:@"me.lau.atria.edit.hs"]];
		[items addObject:[self _atriaGenerateItemWithTitle:@"인디케이터 편집" type:@"me.lau.atria.edit.pagedot"]];
		[items addObject:[self _atriaGenerateItemWithTitle:@"페이지 레이블 편집" type:@"me.lau.atria.edit.label"]];
		if([[ARITweakManager sharedInstance] boolValueForKey:@"showBackground"]) {
			[items addObject:[self _atriaGenerateItemWithTitle:@"배경 블러 편집" type:@"me.lau.atria.edit.blur"]];
		}
	} else if(IconIsInDock(self)) {
		[items addObject:[self _atriaGenerateItemWithTitle:@"독 편집" type:@"me.lau.atria.edit.dock"]];
	}

	return items;
}

%end

%group ARILegacyShortcutActivation

%hook SBIconView

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(SBIconView *)iconView {
	if(!ARIHandleEditorShortcut(item)) %orig(item, bundleID, iconView);
}

%end


%end


%group ARIModernShortcutActivation

%hook SBHIconViewApplicationShortcutsContextMenuProvider

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(SBIconView *)iconView {
	if(!ARIHandleEditorShortcut(item)) %orig(item, bundleID, iconView);
}

%end


%end

// I don't think this needs explaining
%hook SBIconBadgeView

- (CGFloat)alpha {
	CGFloat orig = %orig;
	return orig == 1 ? ![[ARITweakManager sharedInstance] boolValueForKey:@"hideBadges"] : orig;
}

- (void)setAlpha:(CGFloat)arg1 {
	%orig(arg1 == 1 ? ![[ARITweakManager sharedInstance] boolValueForKey:@"hideBadges"] : arg1);
}


%end

%hook SBIconListPageControl

- (void)setHidden:(BOOL)arg1  {
	// Hide page dots
	if([[ARITweakManager sharedInstance] boolValueForKey:@"hidePageDots"]) {
		%orig(YES);
		return;
	}
	%orig(arg1);
}

%end

%group ARIFolderIconBackgroundView

%hook SBFolderIconImageView

- (void)setBackgroundView:(id)arg1 {
	if([[ARITweakManager sharedInstance] boolValueForKey:@"hideFolderIconBG"]) {
		// By setting a fresh UIView, it doesn't bug out, and it fades instead of glitching when closing the folder
		%orig([UIView new]);
		return;
	}

	%orig(arg1);
}

%end


%end

%ctor {
	if([[ARITweakManager sharedInstance] isEnabled]) {
		NSLog(@"[Atria]: Loading hooks from %s", __FILE__);
		%init();

		SEL activationSelector =
			@selector(activateShortcut:withBundleIdentifier:forIconView:);
		Class legacyActivationClass = objc_getClass("SBIconView");
		if(ARIIconMethodMatchesVoidObjectABI(
				legacyActivationClass, activationSelector, YES, 3)) {
			%init(ARILegacyShortcutActivation);
		} else {
			NSLog(@"[Atria]: Skipping legacy shortcut activation hook: incompatible ABI");
		}

		Class modernActivationClass = objc_getClass(
			"SBHIconViewApplicationShortcutsContextMenuProvider");
		if(ARIIconMethodMatchesVoidObjectABI(
				modernActivationClass, activationSelector, YES, 3)) {
			%init(ARIModernShortcutActivation);
		} else {
			NSLog(@"[Atria]: Skipping modern shortcut activation hook: incompatible ABI");
		}

		Class folderImageClass = objc_getClass("SBFolderIconImageView");
		if(ARIIconMethodMatchesVoidObjectABI(
				folderImageClass, @selector(setBackgroundView:), NO, 1)) {
			%init(ARIFolderIconBackgroundView);
		} else {
			NSLog(@"[Atria]: Skipping folder background hook: incompatible ABI");
		}
	}
}

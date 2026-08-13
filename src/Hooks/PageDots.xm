//
// Created by ren7995 on 2021-07-06 14:59:57
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>

// SpringBoard changed the fields inside SBRootFolderViewMetrics several times
// after iOS 15.  The pointer ABI stayed stable, so this hook deliberately
// treats the pointee as opaque and only forwards it to the original method.

@interface ARIPageIndicatorLayoutState : NSObject
@property (nonatomic, weak) UIView *targetView;
@property (nonatomic, assign) CGRect baseFrame;
@property (nonatomic, assign) CGPoint appliedOffset;
@property (nonatomic, assign) BOOL hasBaseFrame;
@end

@implementation ARIPageIndicatorLayoutState
@end

static const void *ARIPageIndicatorLayoutStateKey =
    &ARIPageIndicatorLayoutStateKey;

static const char *ARIPageIndicatorUnqualifiedType(const char *encoding) {
    while(encoding && *encoding && strchr("rnNoORV", *encoding)) encoding++;
    return encoding;
}

static BOOL ARIPageIndicatorObjectTypeMatches(const char *encoding) {
    const char *type = ARIPageIndicatorUnqualifiedType(encoding);
    if(!type || *type != '@' || type[1] == '?') return NO;
    NSUInteger size = 0;
    NSGetSizeAndAlignment(type, &size, NULL);
    return size == sizeof(id);
}

static BOOL ARIPageIndicatorSelectorTypeMatches(const char *encoding) {
    const char *type = ARIPageIndicatorUnqualifiedType(encoding);
    return type && type[0] == ':' && type[1] == '\0';
}

static BOOL ARIPageIndicatorGetterMatchesABI(Class cls, SEL selector) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if(!method || method_getNumberOfArguments(method) != 2) return NO;
    char *returnType = method_copyReturnType(method);
    BOOL matches = ARIPageIndicatorObjectTypeMatches(returnType);
    free(returnType);

    char *selfType = method_copyArgumentType(method, 0);
    char *selectorType = method_copyArgumentType(method, 1);
    matches = matches && ARIPageIndicatorObjectTypeMatches(selfType) &&
        ARIPageIndicatorSelectorTypeMatches(selectorType);
    free(selfType);
    free(selectorType);
    return matches;
}

static BOOL ARIPageIndicatorLayoutMethodMatchesABI(Class cls) {
    Method method = cls
        ? class_getInstanceMethod(cls, @selector(layoutPageControlWithMetrics:))
        : NULL;
    if(!method || method_getNumberOfArguments(method) != 3) return NO;

    char *returnType = method_copyReturnType(method);
    const char *unqualifiedReturn =
        ARIPageIndicatorUnqualifiedType(returnType);
    BOOL matches = unqualifiedReturn && *unqualifiedReturn == 'v';
    free(returnType);
    if(!matches) return NO;

    char *selfType = method_copyArgumentType(method, 0);
    char *selectorType = method_copyArgumentType(method, 1);
    matches = ARIPageIndicatorObjectTypeMatches(selfType) &&
        ARIPageIndicatorSelectorTypeMatches(selectorType);
    free(selfType);
    free(selectorType);
    if(!matches) return NO;

    char *argumentType = method_copyArgumentType(method, 2);
    const char *unqualifiedArgument =
        ARIPageIndicatorUnqualifiedType(argumentType);
    // Require the named private metrics structure, but never depend on or copy
    // any of its version-specific fields.
    static const char expectedPrefix[] = "^{SBRootFolderViewMetrics=";
    matches = unqualifiedArgument &&
        strncmp(unqualifiedArgument,
                expectedPrefix,
                sizeof(expectedPrefix) - 1) == 0;
    if(matches) {
        NSUInteger size = 0;
        NSGetSizeAndAlignment(unqualifiedArgument, &size, NULL);
        matches = size == sizeof(void *);
    }
    free(argumentType);
    return matches;
}

static id ARIPageIndicatorObjectByCallingSelector(id object, SEL selector) {
    if(!object || !selector ||
       !ARIPageIndicatorGetterMatchesABI(object_getClass(object), selector)) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

// Official Atria moves the direct page control on the legacy hierarchy and
// the complete scroll accessory on the modern hierarchy.  Keeping the modern
// search/background accessory together also keeps its hit-testing and system
// animation geometry aligned with the visible indicator.
static UIView *ARIPageIndicatorTarget(SBRootFolderView *rootFolderView) {
    if(!rootFolderView) return nil;
    Class cls = object_getClass(rootFolderView);
    SEL accessorySelector = @selector(scrollAccessoryView);
    if(class_getInstanceMethod(cls, accessorySelector)) {
        id accessory = ARIPageIndicatorObjectByCallingSelector(
            rootFolderView, accessorySelector);
        return [accessory isKindOfClass:[UIView class]] ? accessory : nil;
    }

    id pageControl = ARIPageIndicatorObjectByCallingSelector(
        rootFolderView, @selector(pageControl));
    return [pageControl isKindOfClass:[UIView class]] ? pageControl : nil;
}

static ARIPageIndicatorLayoutState *ARIPageIndicatorState(
    SBRootFolderView *rootFolderView, BOOL create) {
    ARIPageIndicatorLayoutState *state = objc_getAssociatedObject(
        rootFolderView, ARIPageIndicatorLayoutStateKey);
    if(!state && create) {
        state = [ARIPageIndicatorLayoutState new];
        objc_setAssociatedObject(rootFolderView,
                                 ARIPageIndicatorLayoutStateKey,
                                 state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static CGRect ARIPageIndicatorFrameWithOffset(CGRect frame, CGPoint offset) {
    frame.origin.x += offset.x;
    frame.origin.y += offset.y;
    return frame;
}

static BOOL ARIPageIndicatorOriginsNearlyEqual(CGRect lhs,
                                                CGRect rhs,
                                                UIView *view) {
    CGFloat scale = view.window.screen.scale;
    if(scale <= 0.0) scale = UIScreen.mainScreen.scale;
    if(scale <= 0.0) scale = 1.0;
    CGFloat epsilon = 0.5 / scale;
    return fabs(CGRectGetMinX(lhs) - CGRectGetMinX(rhs)) <= epsilon &&
           fabs(CGRectGetMinY(lhs) - CGRectGetMinY(rhs)) <= epsilon;
}

static void ARIPageIndicatorRestoreTrackedFrameIfUnchanged(
    ARIPageIndicatorLayoutState *state) {
    UIView *target = state.targetView;
    if(!target || !state.hasBaseFrame) return;
    CGRect expected = ARIPageIndicatorFrameWithOffset(state.baseFrame,
                                                       state.appliedOffset);
    CGRect currentFrame = target.frame;
    if(ARIPageIndicatorOriginsNearlyEqual(currentFrame, expected, target)) {
        // Atria owns only the translation. Preserve any size update that
        // SpringBoard performed independently before this layout callback.
        currentFrame.origin = state.baseFrame.origin;
        target.frame = currentFrame;
        state.baseFrame = currentFrame;
    } else if(ARIPageIndicatorOriginsNearlyEqual(currentFrame,
                                                  state.baseFrame,
                                                  target)) {
        state.baseFrame = currentFrame;
    }
}

static void ARIPageIndicatorPrepareForSystemLayout(
    SBRootFolderView *rootFolderView) {
    ARIPageIndicatorLayoutState *state =
        ARIPageIndicatorState(rootFolderView, NO);
    if(state) ARIPageIndicatorRestoreTrackedFrameIfUnchanged(state);
}

static void ARIPageIndicatorApplyOffset(SBRootFolderView *rootFolderView,
                                        BOOL systemLayoutCompleted) {
    ARIPageIndicatorLayoutState *state =
        ARIPageIndicatorState(rootFolderView, NO);
    UIView *target = ARIPageIndicatorTarget(rootFolderView);
    if(!target) {
        // The modern accessory is replaced while search/editing modes change.
        // Do not leave a detached old target translated or reuse its geometry
        // when SpringBoard later installs a new accessory instance.
        if(state) {
            ARIPageIndicatorRestoreTrackedFrameIfUnchanged(state);
            state.targetView = nil;
            state.hasBaseFrame = NO;
            state.appliedOffset = CGPointZero;
        }
        return;
    }

    if(!state) state = ARIPageIndicatorState(rootFolderView, YES);
    if(state.targetView != target) {
        ARIPageIndicatorRestoreTrackedFrameIfUnchanged(state);
        state.targetView = target;
        state.hasBaseFrame = NO;
        state.appliedOffset = CGPointZero;
    }

    CGRect currentFrame = target.frame;
    if(!systemLayoutCompleted && state.hasBaseFrame) {
        CGRect expected = ARIPageIndicatorFrameWithOffset(state.baseFrame,
                                                           state.appliedOffset);
        if(ARIPageIndicatorOriginsNearlyEqual(currentFrame, expected, target)) {
            // Live editor updates do not run SpringBoard's layout method first.
            // Remove only our previous translation and retain a system size
            // update before applying the new absolute preference value.
            currentFrame.origin = state.baseFrame.origin;
        }
    }

    // At the system hook this is the authoritative post-%orig frame. For a
    // live editor call it is either the restored old base or a newly supplied
    // system frame. In both cases it becomes the sole base for this update.
    state.baseFrame = currentFrame;
    state.hasBaseFrame = YES;

    ARITweakManager *manager = [ARITweakManager sharedInstance];
    CGPoint offset = CGPointMake(
        [manager floatValueForKey:@"pagedot_offsetX"],
        [manager floatValueForKey:@"pagedot_offsetY"]);
    target.frame = ARIPageIndicatorFrameWithOffset(state.baseFrame, offset);
    state.appliedOffset = offset;
}

%hook SBRootFolderView

%new
- (void)_atriaApplyPageControlOffset {
    ARIPageIndicatorApplyOffset(self, NO);
}

%end


%group ARIPageIndicatorSystemLayout

%hook SBRootFolderView

- (void)layoutPageControlWithMetrics:(const void *)metrics {
    ARIPageIndicatorPrepareForSystemLayout(self);
    %orig(metrics);
    ARIPageIndicatorApplyOffset(self, YES);
}

%end


%end


%ctor {
    if([[ARITweakManager sharedInstance] isEnabled]) {
        NSLog(@"[Atria]: Loading hooks from %s", __FILE__);
        %init();

        Class rootFolderViewClass = objc_getClass("SBRootFolderView");
        if(ARIPageIndicatorLayoutMethodMatchesABI(rootFolderViewClass))
            %init(ARIPageIndicatorSystemLayout);
    }
}

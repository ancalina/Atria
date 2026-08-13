//
// Created by ren7995 on 2023-01-05 15:47:33
// Copyright (c) 2023 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"
#import <objc/message.h>
#import <objc/runtime.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>

// Widget dimensions must never collapse to zero on sparse iPad grids.
#define ROUND_SHORT(x) (uint16_t)MAX(1.0, (x) + 0.5)

typedef struct {
	NSUInteger size;
	const char *encoding;
} ARIABITypeExpectation;

#define ARI_ABI_TYPE(type) ((ARIABITypeExpectation) { sizeof(type), @encode(type) })

static const char *ARIUnqualifiedTypeEncoding(const char *encoding) {
	while(encoding && *encoding && strchr("rnNoORV", *encoding)) encoding++;
	return encoding;
}

static char *ARICopyCanonicalAggregateEncoding(const char *encoding) {
	const char *cursor = ARIUnqualifiedTypeEncoding(encoding);
	if(!cursor) return NULL;

	size_t inputLength = strlen(cursor);
	char *canonical = (char *)calloc(inputLength + 1, sizeof(char));
	if(!canonical) return NULL;

	size_t outputIndex = 0;
	while(*cursor) {
		// Field and Objective-C class names are descriptive only. Strip them so
		// private aggregate renames do not disable an otherwise identical ABI.
		if(*cursor == '"') {
			cursor++;
			while(*cursor && *cursor != '"') {
				if(*cursor == '\\' && cursor[1]) cursor += 2;
				else cursor++;
			}
			if(*cursor == '"') cursor++;
			continue;
		}

		if(*cursor == '{' || *cursor == '(') {
			char closing = *cursor == '{' ? '}' : ')';
			canonical[outputIndex++] = *cursor++;
			// Aggregate names precede '=' and are not part of the calling ABI.
			while(*cursor && *cursor != '=' && *cursor != closing) cursor++;
			if(*cursor == '=') canonical[outputIndex++] = *cursor++;
			else if(*cursor == closing) {
				canonical[outputIndex++] = *cursor++;
			}
			continue;
		}

		if(strchr("rnNoORV", *cursor)) {
			cursor++;
			continue;
		}
		canonical[outputIndex++] = *cursor++;
	}
	canonical[outputIndex] = '\0';
	return canonical;
}

static BOOL ARITypeMatchesABI(const char *actualEncoding,
							  ARIABITypeExpectation expected) {
	if(!actualEncoding || !expected.encoding) return NO;
	NSUInteger actualSize = 0;
	NSGetSizeAndAlignment(actualEncoding, &actualSize, NULL);
	const char *actual = ARIUnqualifiedTypeEncoding(actualEncoding);
	const char *wanted = ARIUnqualifiedTypeEncoding(expected.encoding);
	if(!actual || !*actual || !wanted || !*wanted || actualSize != expected.size)
		return NO;
	if(*actual != *wanted) return NO;
	if(*actual != '{' && *actual != '(') return YES;

	// Size alone is not sufficient for aggregates: reordered or differently
	// typed fields can use a different calling convention while occupying the
	// same bytes. Ignore private type/field names, but compare every encoded
	// field and nesting boundary before installing or calling a hook.
	char *canonicalActual = ARICopyCanonicalAggregateEncoding(actual);
	char *canonicalWanted = ARICopyCanonicalAggregateEncoding(wanted);
	BOOL matches = canonicalActual && canonicalWanted &&
		strcmp(canonicalActual, canonicalWanted) == 0;
	free(canonicalActual);
	free(canonicalWanted);
	return matches;
}

static BOOL ARIMethodMatchesABI(Class cls, SEL selector,
								ARIABITypeExpectation expectedReturnType,
								const ARIABITypeExpectation *explicitArguments,
								NSUInteger explicitArgumentCount) {
	Method method = class_getInstanceMethod(cls, selector);
	if(!method || method_getNumberOfArguments(method) != explicitArgumentCount + 2)
		return NO;

	char *actualReturnType = method_copyReturnType(method);
	BOOL matches = ARITypeMatchesABI(actualReturnType, expectedReturnType);
	free(actualReturnType);
	if(!matches) return NO;

	for(NSUInteger index = 0; index < explicitArgumentCount; index++) {
		char *argumentType = method_copyArgumentType(method, (unsigned int)index + 2);
		matches = ARITypeMatchesABI(argumentType, explicitArguments[index]);
		free(argumentType);
		if(!matches) return NO;
	}
	return YES;
}

// Function to calculate the widget grid sizes to be appropriate for the amount of columns and rows
// Messy math
static struct SBHIconGridSizeClassSizes generateGridSizeClassSizes(double cols, double rows, BOOL landscape) {
	struct SBHIconGridSizeClassSizes sizes = {};
	if([[ARITweakManager sharedInstance] isDeviceIPad]) {
		// Usually 1x1, 2x1, 2x2, 2x3
		if (landscape) {
			// Use rows to calculate widths and columns to calculate height since it is inverted
			sizes.small = (struct SBHIconGridSize) { .width = ROUND_SHORT(rows / 6), .height = ROUND_SHORT(cols / 4) };
			sizes.medium = (struct SBHIconGridSize) { .width = ROUND_SHORT(rows / 3), .height = ROUND_SHORT(cols / 4) };
			sizes.large = (struct SBHIconGridSize) { .width = ROUND_SHORT(rows / 3), .height = ROUND_SHORT(cols / 2) };
			sizes.extraLarge = (struct SBHIconGridSize) { .width = ROUND_SHORT(rows / 3), .height = ROUND_SHORT(cols / 1.5) };
		} else {
			sizes.small = (struct SBHIconGridSize) { .width = ROUND_SHORT(cols / 4), .height = ROUND_SHORT(rows / 5) };
			sizes.medium = (struct SBHIconGridSize) { .width = ROUND_SHORT(cols / 2), .height = ROUND_SHORT(rows / 5) };
			sizes.large = (struct SBHIconGridSize) { .width = ROUND_SHORT(cols / 2), .height = ROUND_SHORT(rows / 3) };
			sizes.extraLarge = (struct SBHIconGridSize) { .width = ROUND_SHORT(cols / 2), .height = ROUND_SHORT(rows / 1.5) };
		}
	} else {
		// Usually 2x2, 4x2, 4x4, 4x6
		sizes.small = (struct SBHIconGridSize) { .width = ROUND_SHORT(cols / 2), .height = ROUND_SHORT(rows / 3) };
		sizes.medium = (struct SBHIconGridSize) { .width = ROUND_SHORT(cols), .height = ROUND_SHORT(rows / 3) };
		sizes.large = (struct SBHIconGridSize) { .width = ROUND_SHORT(cols), .height = ROUND_SHORT(rows * 2 / 3) };
		sizes.extraLarge = (struct SBHIconGridSize) { .width = ROUND_SHORT(cols), .height = ROUND_SHORT(rows) };
	}
	return sizes;
}

static BOOL ARIIvarStorage(id object, const char *name, void **storage,
						  NSUInteger *size, const char **typeEncoding) {
	if(!object || !name || !storage || !size || !typeEncoding) return NO;

	Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
	if(!ivar) return NO;

	const char *encoding = ivar_getTypeEncoding(ivar);
	NSUInteger encodedSize = 0;
	if(!encoding) return NO;
	NSGetSizeAndAlignment(encoding, &encodedSize, NULL);
	if(encodedSize == 0) return NO;

	*storage = (uint8_t *)(__bridge void *)object + ivar_getOffset(ivar);
	*size = encodedSize;
	*typeEncoding = encoding;
	return YES;
}

static BOOL ARIWriteGridSize(id model, struct SBHIconGridSize gridSize) {
	const ARIABITypeExpectation argument[] = {
		ARI_ABI_TYPE(struct SBHIconGridSize)
	};
	if(!ARIMethodMatchesABI(object_getClass(model), @selector(setGridSize:),
								 (ARIABITypeExpectation) { 0, @encode(void) },
								 argument, 1)) return NO;
	((void (*)(id, SEL, struct SBHIconGridSize))objc_msgSend)(
		model, @selector(setGridSize:), gridSize);
	return YES;
}

static BOOL ARIReadGridSize(id model, struct SBHIconGridSize *gridSize) {
	if(!gridSize) return NO;
	if(!ARIMethodMatchesABI(object_getClass(model), @selector(gridSize),
								 ARI_ABI_TYPE(struct SBHIconGridSize), NULL, 0)) return NO;
	*gridSize = ((struct SBHIconGridSize (*)(id, SEL))objc_msgSend)(
		model, @selector(gridSize));
	return YES;
}

static BOOL ARIReadUnsignedInteger(id object, SEL selector, NSUInteger *value) {
	if(!object || !selector || !value) return NO;
	if(!ARIMethodMatchesABI(object_getClass(object), selector,
								 ARI_ABI_TYPE(NSUInteger), NULL, 0)) return NO;
	*value = ((NSUInteger (*)(id, SEL))objc_msgSend)(object, selector);
	return YES;
}

typedef NS_ENUM(NSUInteger, ARIWidgetGridTokenKind) {
	ARIWidgetGridTokenKindNone = 0,
	ARIWidgetGridTokenKindInteger,
	ARIWidgetGridTokenKindObject
};

// SpringBoard used an integer grid-size class through iOS 17 and moved to an
// object token later. Select the adapter from the live method ABI instead of
// guessing from an OS version or hard-coding private token values.
static ARIWidgetGridTokenKind ARIWidgetGridTokenKindValue;

static BOOL ARIReadWidgetGridToken(id icon, NSUInteger *integerToken,
									id __autoreleasing *objectToken) {
	if(!icon || !integerToken || !objectToken) return NO;
	*integerToken = 0;
	*objectToken = nil;

	switch(ARIWidgetGridTokenKindValue) {
		case ARIWidgetGridTokenKindInteger:
			return ARIReadUnsignedInteger(icon, @selector(gridSizeClass),
										  integerToken);
		case ARIWidgetGridTokenKindObject:
			if(!ARIMethodMatchesABI(object_getClass(icon),
									 @selector(gridSizeClass), ARI_ABI_TYPE(id),
									 NULL, 0)) return NO;
			*objectToken = ((id (*)(id, SEL))objc_msgSend)(
				icon, @selector(gridSizeClass));
			return *objectToken != nil;
		default:
			return NO;
	}
}

static BOOL ARIReadGridSizeForToken(id object, SEL selector,
									NSUInteger integerToken, id objectToken,
									struct SBHIconGridSize *gridSize) {
	if(!object || !selector || !gridSize) return NO;

	if(ARIWidgetGridTokenKindValue == ARIWidgetGridTokenKindInteger) {
		const ARIABITypeExpectation argument[] = {
			ARI_ABI_TYPE(NSUInteger)
		};
		if(!ARIMethodMatchesABI(object_getClass(object), selector,
									 ARI_ABI_TYPE(struct SBHIconGridSize),
									 argument, 1)) return NO;
		*gridSize = ((struct SBHIconGridSize (*)(id, SEL, NSUInteger))
			objc_msgSend)(object, selector, integerToken);
	} else if(ARIWidgetGridTokenKindValue == ARIWidgetGridTokenKindObject) {
		const ARIABITypeExpectation argument[] = { ARI_ABI_TYPE(id) };
		if(!objectToken ||
		   !ARIMethodMatchesABI(object_getClass(object), selector,
									 ARI_ABI_TYPE(struct SBHIconGridSize),
									 argument, 1)) return NO;
		*gridSize = ((struct SBHIconGridSize (*)(id, SEL, id))objc_msgSend)(
			object, selector, objectToken);
	} else {
		return NO;
	}
	return gridSize->width > 0 && gridSize->height > 0;
}

static BOOL ARIReadIconImageSizeForToken(SBIconListView *listView,
										NSUInteger integerToken, id objectToken,
										CGSize *imageSize) {
	if(!listView || !imageSize) return NO;
	SEL selector = @selector(iconImageSizeForGridSizeClass:);

	if(ARIWidgetGridTokenKindValue == ARIWidgetGridTokenKindInteger) {
		const ARIABITypeExpectation argument[] = {
			ARI_ABI_TYPE(NSUInteger)
		};
		if(!ARIMethodMatchesABI(object_getClass(listView), selector,
									 ARI_ABI_TYPE(CGSize), argument, 1)) return NO;
		*imageSize = ((CGSize (*)(id, SEL, NSUInteger))objc_msgSend)(
			listView, selector, integerToken);
	} else if(ARIWidgetGridTokenKindValue == ARIWidgetGridTokenKindObject) {
		const ARIABITypeExpectation argument[] = { ARI_ABI_TYPE(id) };
		if(!objectToken ||
		   !ARIMethodMatchesABI(object_getClass(listView), selector,
									 ARI_ABI_TYPE(CGSize), argument, 1)) return NO;
		*imageSize = ((CGSize (*)(id, SEL, id))objc_msgSend)(
			listView, selector, objectToken);
	} else {
		return NO;
	}
	return isfinite(imageSize->width) && isfinite(imageSize->height) &&
		imageSize->width > 0.0 && imageSize->height > 0.0;
}

// originForIconAtCoordinate: normally returns a list-local point, but while
// SpringBoard animates an unlock it may return a point that an effective layout
// delegate has already converted into the animator's zoom view. Keep Atria's
// widget adjustment on the local side of that conversion by carrying it into
// the private pixel-alignment seam used immediately before the delegate call.
// The stack is thread-local because nested list layout is legal and the whole
// operation is synchronous.
typedef struct ARIWidgetOriginContext {
	void *listView;
	CGFloat targetX;
	CGFloat xOffset;
	CGFloat yOffset;
	BOOL active;
	BOOL consumed;
	struct ARIWidgetOriginContext *previous;
} ARIWidgetOriginContext;

static __thread ARIWidgetOriginContext *ARIWidgetOriginContextTop;

static void ARIPushWidgetOriginBarrier(ARIWidgetOriginContext *context,
									   SBIconListView *listView) {
	if(!context) return;
	*context = (ARIWidgetOriginContext) {
		.listView = (__bridge void *)listView,
		.active = NO,
		.consumed = NO,
		.previous = ARIWidgetOriginContextTop
	};
	ARIWidgetOriginContextTop = context;
}

static void ARIPopWidgetOriginContext(ARIWidgetOriginContext *context) {
	if(!context) return;
	// A mismatch means an unknown future path did not unwind synchronously.
	// Discard the thread-local chain rather than retaining a stack pointer.
	ARIWidgetOriginContextTop = ARIWidgetOriginContextTop == context ?
		context->previous : NULL;
}

static void ARIArmWidgetOriginContext(ARIWidgetOriginContext *context,
									  CGFloat targetX, CGFloat xOffset,
									  CGFloat yOffset) {
	if(!context || ARIWidgetOriginContextTop != context || !isfinite(targetX) ||
	   !isfinite(xOffset) || !isfinite(yOffset)) return;
	context->targetX = targetX;
	context->xOffset = xOffset;
	context->yOffset = yOffset;
	context->active = YES;
}

static ARIWidgetOriginContext *ARIActiveWidgetOriginContext(
	SBIconListView *listView) {
	if(!listView) return NULL;
	ARIWidgetOriginContext *context = ARIWidgetOriginContextTop;
	if(!context) return NULL;
	if(!context->active || context->consumed ||
	   context->listView != (__bridge void *)listView) return NULL;
	return context;
}

static BOOL ARICalculateWidgetOriginAdjustment(
	SBIconListView *listView, SBIcon *icon,
	SBIconListViewLayoutMetrics *metrics, CGFloat *targetX,
	CGFloat *xOffset, CGFloat *yOffset) {
	if(!listView || !icon || !metrics || !targetX || !xOffset || !yOffset)
		return NO;

	NSUInteger integerToken = 0;
	id objectToken = nil;
	if(!ARIReadWidgetGridToken(icon, &integerToken, &objectToken)) return NO;

	struct SBHIconGridSize gridSize = {};
	if(!ARIReadGridSizeForToken(listView, @selector(iconGridSizeForClass:),
									integerToken, objectToken, &gridSize)) return NO;

	// Ask the icon list for the model's canonical coordinate instead of
	// interpreting private struct fields whose row/column order has changed.
	struct SBIconCoordinate anchor = [listView coordinateForIcon:icon];
	CGRect allocatedCells =
		[listView rectForDefaultSizedCellsOfSize:gridSize
							 startingAtCoordinate:anchor
							 metrics:metrics];
	CGSize imageSize = CGSizeZero;
	if(!ARIReadIconImageSizeForToken(listView, integerToken, objectToken,
										 &imageSize)) return NO;
	CGFloat contentScale = metrics.iconContentScale;
	if(CGRectIsNull(allocatedCells) || CGRectIsInfinite(allocatedCells) ||
	   CGRectIsEmpty(allocatedCells) || !isfinite(imageSize.width) ||
	   imageSize.width <= 0.0 || !isfinite(contentScale) ||
	   contentScale <= 0.0) return NO;

	ARITweakManager *manager = [ARITweakManager sharedInstance];
	CGFloat configuredXOffset =
		[manager floatValueForKey:@"hs_widgetXOffset" forListView:listView];
	CGFloat configuredYOffset =
		[manager floatValueForKey:@"hs_widgetYOffset" forListView:listView];
	CGFloat calculatedX = CGRectGetMidX(allocatedCells) -
		(imageSize.width * contentScale) / 2.0;
	if(!isfinite(calculatedX) || !isfinite(configuredXOffset) ||
	   !isfinite(configuredYOffset)) return NO;

	*targetX = calculatedX;
	*xOffset = configuredXOffset;
	*yOffset = configuredYOffset;
	return YES;
}

static const char *ARISkipTypeFieldName(const char *cursor) {
	if(!cursor || *cursor != '"') return cursor;
	cursor++;
	while(*cursor && *cursor != '"') {
		if(*cursor == '\\' && cursor[1]) cursor += 2;
		else cursor++;
	}
	return *cursor == '"' ? cursor + 1 : NULL;
}

static BOOL ARIGridSizeSlotMatchesEncoding(const char *encoding) {
	const char *cursor = ARIUnqualifiedTypeEncoding(encoding);
	if(!cursor || *cursor != '{') return NO;
	const char *fields = strchr(cursor, '=');
	if(!fields) return NO;
	cursor = fields + 1;
	for(NSUInteger field = 0; field < 2; field++) {
		cursor = ARISkipTypeFieldName(cursor);
		const char *scalar = ARIUnqualifiedTypeEncoding(cursor);
		if(!scalar || *scalar != @encode(uint16_t)[0]) return NO;
		NSUInteger size = 0;
		const char *next = NSGetSizeAndAlignment(cursor, &size, NULL);
		if(!next || next <= cursor || size != sizeof(uint16_t)) return NO;
		cursor = next;
	}
	cursor = ARISkipTypeFieldName(cursor);
	return cursor && *cursor == '}';
}

static BOOL ARIGridSizeClassSlotsMatchEncoding(const char *encoding,
											NSUInteger expectedSlots) {
	const char *cursor = ARIUnqualifiedTypeEncoding(encoding);
	if(!cursor || *cursor != '{') return NO;
	const char *fields = strchr(cursor, '=');
	if(!fields) return NO;
	cursor = fields + 1;

	for(NSUInteger slot = 0; slot < expectedSlots; slot++) {
		cursor = ARISkipTypeFieldName(cursor);
		if(!cursor || !ARIGridSizeSlotMatchesEncoding(cursor)) return NO;
		NSUInteger size = 0;
		const char *next = NSGetSizeAndAlignment(cursor, &size, NULL);
		if(!next || next <= cursor || size != sizeof(struct SBHIconGridSize))
			return NO;
		cursor = next;
	}
	cursor = ARISkipTypeFieldName(cursor);
	return cursor && *cursor == '}';
}

static void ARIWriteGridSizeClassSizes(id model, struct SBHIconGridSizeClassSizes calculated) {
	void *storage = NULL;
	NSUInteger size = 0;
	const char *encoding = NULL;
	if(!ARIIvarStorage(model, "_gridSizeClassSizes", &storage, &size,
						 &encoding)) return;

	if(size == sizeof(struct SBHIconGridSizeClassSizes) &&
	   ARIGridSizeClassSlotsMatchEncoding(encoding, 4)) {
		memcpy(storage, &calculated, sizeof(calculated));
		return;
	}

	NSUInteger slotSize = sizeof(struct SBHIconGridSize);
	NSUInteger slotCount = size / slotSize;
	if(size == slotSize * 5 && slotCount == 5 &&
	   ARIGridSizeClassSlotsMatchEncoding(encoding, 5)) {
		// The known five-slot ABI inserts a system-owned class between large and
		// extraLarge. Preserve that middle slot and reject every unknown layout.
		memcpy((uint8_t *)storage + slotSize * 0, &calculated.small, slotSize);
		memcpy((uint8_t *)storage + slotSize * 1, &calculated.medium, slotSize);
		memcpy((uint8_t *)storage + slotSize * 2, &calculated.large, slotSize);
		memcpy((uint8_t *)storage + slotSize * 4, &calculated.extraLarge, slotSize);
	}
}

// List model hook
%hook SBIconListModel
%property (nonatomic, strong) NSString *_atriaLocation;

%new 
- (SBIconListView *)_atriaListView {
	return [[ARITweakManager sharedInstance].listViewModelMap objectForKey:self];
}

%new
- (void)_atriaUpdateModelGridSizes {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	NSString *location = self._atriaLocation;
	SBIconListView *listView = [self _atriaListView];
	BOOL isRoot = [location isKindOfClass:[NSString class]] &&
		IsLocationRoot(location);
	if(!isRoot) return;

	struct SBHIconGridSize gridSize = {};
	if(!ARIReadGridSize(self, &gridSize)) return;
	NSUInteger cols = [manager intValueForKey:@"hs_columns" forListView:listView];
	NSUInteger rows = [manager intValueForKey:@"hs_rows" forListView:listView];
	if(cols == 0 || rows == 0 || cols > UINT16_MAX || rows > UINT16_MAX) return;

	gridSize.height = rows;
	gridSize.width = cols;
	if(!ARIWriteGridSize(self, gridSize)) return;

	// Update grid size class sizes
	if([manager boolValueForKey:@"dynamicWidgetSizing"]) {
		ARIWriteGridSizeClassSizes(
			self,
			generateGridSizeClassSizes(
				cols,
				rows,
				UIInterfaceOrientationIsLandscape([ARITweakManager currentDeviceOrientation])
			)
		);
	}
}

%end

// Official Atria deliberately removes capacity limits while SpringBoard is
// constructing a transient list model that has not yet been attached to a
// concrete icon location. iOS 15 consults that model during drag admission;
// applying a normal page or Dock capacity before the host view assigns the
// location can reject or evict an otherwise valid move. Once a location is
// present, every model (including Dock suggestions and independently managed
// lists) falls straight through to SpringBoard's original implementation.
%group ARITransientModelAdmissionHooks

%hook SBIconListModel

- (struct SBHIconGridSize)gridSize {
	if(!self._atriaLocation) {
		struct SBHIconGridSize size = {
			.height = (uint16_t)0x7FFFu,
			.width = (uint16_t)0x7FFFu
		};
		return size;
	}
	return %orig;
}

- (NSUInteger)maxNumberOfIcons {
	return self._atriaLocation ? %orig : NSUIntegerMax;
}

- (NSUInteger)numberOfFreeSlots {
	if(!self._atriaLocation || IsLocationRoot(self._atriaLocation))
		return NSUIntegerMax;
	return %orig;
}

%end

%end

// Version specific hooks for widget support
%group Widgets14Origin

%hook SBIconListView

// Newer SpringBoard versions align several intermediate cell corners while
// computing this rectangle. Keep those helper-internal alignments behind an
// inactive stack entry so only the final icon-origin alignment performed by
// originForIconAtCoordinate:metrics: can consume the widget adjustment.
- (CGRect)rectForDefaultSizedCellsOfSize:(struct SBHIconGridSize)size
				   startingAtCoordinate:(struct SBIconCoordinate)coordinate
				   metrics:(SBIconListViewLayoutMetrics *)metrics {
	ARIWidgetOriginContext context;
	ARIPushWidgetOriginBarrier(&context, self);

	CGRect rect = CGRectZero;
	@try {
		rect = %orig;
	} @finally {
		ARIPopWidgetOriginContext(&context);
	}
	return rect;
}

// Will crash on iOS 13 due to method signature changes and ARC trying to retain a non-object
// This hook is to center widgets in their available grid space. By default, they align with the left
// side of the space, which isn't desirable when the layout gets changed. This hook injects our own
// icon origin calculation method that is designed to work outside of the default layout.
- (CGPoint)originForIconAtCoordinate:(struct SBIconCoordinate)co metrics:(SBIconListViewLayoutMetrics *)metrics {
	// Even non-widget/nested origins need an inactive top-of-stack barrier so
	// their alignment call cannot consume an outer widget's adjustment.
	ARIWidgetOriginContext context;
	ARIPushWidgetOriginBarrier(&context, self);

	CGPoint origin = CGPointZero;
	@try {
		SBIcon *icon = [self iconAtCoordinate:co metrics:metrics];
		if([icon isKindOfClass:objc_getClass("SBWidgetIcon")] && IconListIsRoot(self)) {
			CGFloat targetX = 0.0;
			CGFloat xOffset = 0.0;
			CGFloat yOffset = 0.0;
			if(ARICalculateWidgetOriginAdjustment(
					self, icon, metrics, &targetX, &xOffset, &yOffset))
				ARIArmWidgetOriginContext(&context, targetX, xOffset, yOffset);
		}

		origin = %orig;
	} @finally {
		// Always restore the prior context, even if a private SpringBoard method
		// raises an exception that an outer caller elects to catch.
		ARIPopWidgetOriginContext(&context);
	}
	return origin;
}

// SpringBoard calls this with a list-local icon origin immediately before it
// asks the current effective layout delegate (including unlock animators) to
// transform the point. Modifying both axes here prevents mixed coordinate
// spaces and automatically follows future delegates that preserve this ABI.
- (CGPoint)_alignedIconPointForPoint:(CGPoint)point {
	ARIWidgetOriginContext *context = ARIActiveWidgetOriginContext(self);
	if(!context) return %orig;

	context->consumed = YES;
	point.x = context->targetX;
	CGPoint alignedPoint = %orig(point);
	CGFloat shiftedX = alignedPoint.x + context->xOffset;
	CGFloat shiftedY = alignedPoint.y + context->yOffset;
	if(isfinite(shiftedX)) alignedPoint.x = shiftedX;
	if(isfinite(shiftedY)) alignedPoint.y = shiftedY;
	return alignedPoint;
}

%end

%end


%group Widgets14Sizing

%hook SBIconListView

// This hook forces the list view to respect the adjusted grid size of the widgets
- (struct SBHIconGridSize)iconGridSizeForClass:(NSUInteger)arg1 {
	if(!IconListIsRoot(self)) return %orig;

	// Determine if we need to override the grid sizes
	// Size 0 is a 1x1 icon (not a widget)
	if(![[ARITweakManager sharedInstance] boolValueForKey:@"dynamicWidgetSizing"] || arg1 == 0) return %orig;
	SBIconListModel *model = [self model];
	if(![model respondsToSelector:@selector(gridSizeForGridSizeClass:)]) return %orig;
	struct SBHIconGridSize gridSize = {};
	if(!ARIReadGridSizeForToken(model, @selector(gridSizeForGridSizeClass:),
									arg1, nil, &gridSize)) return %orig;
	return gridSize;
}

%end

%end


%ctor {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	if([manager isEnabled] && [manager boolValueForKey:@"layoutEnabled"]) {
		NSLog(@"[Atria]: Loading hooks from %s", __FILE__);

		%init();

		Class listViewClass = objc_getClass("SBIconListView");
		Class listModelClass = objc_getClass("SBIconListModel");
		Class iconClass = objc_getClass("SBIcon");
		Class metricsClass = objc_getClass("SBIconListViewLayoutMetrics");

		BOOL transientModelAdmissionABIValid =
			ARIMethodMatchesABI(
				listModelClass, @selector(gridSize),
				ARI_ABI_TYPE(struct SBHIconGridSize), NULL, 0) &&
			ARIMethodMatchesABI(
				listModelClass, @selector(maxNumberOfIcons),
				ARI_ABI_TYPE(NSUInteger), NULL, 0) &&
			ARIMethodMatchesABI(
				listModelClass, @selector(numberOfFreeSlots),
				ARI_ABI_TYPE(NSUInteger), NULL, 0);
		if(transientModelAdmissionABIValid)
			%init(ARITransientModelAdmissionHooks);

		const ARIABITypeExpectation coordinateAndObjectArguments[] = {
			ARI_ABI_TYPE(struct SBIconCoordinate), ARI_ABI_TYPE(id)
		};
		const ARIABITypeExpectation integerArgument[] = {
			ARI_ABI_TYPE(NSUInteger)
		};
		const ARIABITypeExpectation objectArgument[] = {
			ARI_ABI_TYPE(id)
		};
		const ARIABITypeExpectation pointArgument[] = {
			ARI_ABI_TYPE(CGPoint)
		};
		const ARIABITypeExpectation gridCoordinateAndObjectArguments[] = {
			ARI_ABI_TYPE(struct SBHIconGridSize),
			ARI_ABI_TYPE(struct SBIconCoordinate), ARI_ABI_TYPE(id)
		};
		BOOL widgetCommonABIValid =
			ARIMethodMatchesABI(
				listViewClass, @selector(iconAtCoordinate:metrics:),
				ARI_ABI_TYPE(id), coordinateAndObjectArguments, 2);
		BOOL widgetIntegerTokenABIValid = widgetCommonABIValid &&
			ARIMethodMatchesABI(
				listViewClass, @selector(iconImageSizeForGridSizeClass:),
				ARI_ABI_TYPE(CGSize), integerArgument, 1) &&
			ARIMethodMatchesABI(
				listViewClass, @selector(iconGridSizeForClass:),
				ARI_ABI_TYPE(struct SBHIconGridSize), integerArgument, 1) &&
			ARIMethodMatchesABI(
				iconClass, @selector(gridSizeClass),
				ARI_ABI_TYPE(NSUInteger), NULL, 0);
		BOOL widgetObjectTokenABIValid = widgetCommonABIValid &&
			ARIMethodMatchesABI(
				listViewClass, @selector(iconImageSizeForGridSizeClass:),
				ARI_ABI_TYPE(CGSize), objectArgument, 1) &&
			ARIMethodMatchesABI(
				listViewClass, @selector(iconGridSizeForClass:),
				ARI_ABI_TYPE(struct SBHIconGridSize), objectArgument, 1) &&
			ARIMethodMatchesABI(
				iconClass, @selector(gridSizeClass), ARI_ABI_TYPE(id), NULL, 0);

		if(widgetIntegerTokenABIValid != widgetObjectTokenABIValid &&
		   widgetIntegerTokenABIValid)
			ARIWidgetGridTokenKindValue = ARIWidgetGridTokenKindInteger;
		else if(widgetIntegerTokenABIValid != widgetObjectTokenABIValid &&
				widgetObjectTokenABIValid)
			ARIWidgetGridTokenKindValue = ARIWidgetGridTokenKindObject;

		BOOL widgetOriginABIValid =
			ARIWidgetGridTokenKindValue != ARIWidgetGridTokenKindNone &&
			ARIMethodMatchesABI(
				listViewClass, @selector(originForIconAtCoordinate:metrics:),
				ARI_ABI_TYPE(CGPoint), coordinateAndObjectArguments, 2) &&
			ARIMethodMatchesABI(
				listViewClass, @selector(coordinateForIcon:),
				ARI_ABI_TYPE(struct SBIconCoordinate), objectArgument, 1) &&
			ARIMethodMatchesABI(
				listViewClass, @selector(_alignedIconPointForPoint:),
				ARI_ABI_TYPE(CGPoint), pointArgument, 1) &&
			ARIMethodMatchesABI(
				listViewClass,
				@selector(rectForDefaultSizedCellsOfSize:startingAtCoordinate:metrics:),
				ARI_ABI_TYPE(CGRect), gridCoordinateAndObjectArguments, 3) &&
			ARIMethodMatchesABI(
				metricsClass, @selector(iconContentScale),
				ARI_ABI_TYPE(CGFloat), NULL, 0);

		BOOL modelIntegerGridClassABIValid = ARIMethodMatchesABI(
			listModelClass, @selector(gridSizeForGridSizeClass:),
			ARI_ABI_TYPE(struct SBHIconGridSize), integerArgument, 1);
		BOOL widgetIntegerSizingABIValid = widgetIntegerTokenABIValid &&
			modelIntegerGridClassABIValid &&
			ARIMethodMatchesABI(
				listViewClass, @selector(model), ARI_ABI_TYPE(id), NULL, 0);
		if(widgetIntegerSizingABIValid) %init(Widgets14Sizing);
		if(widgetOriginABIValid) %init(Widgets14Origin);
	}
}

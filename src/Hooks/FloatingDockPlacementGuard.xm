//
// Floating Dock placement interoperability boundary.
//
// A separately installed placement tweak exposes a BOOL model flag that is
// used as the admission gate for rebuilding SpringBoard's grid-cell map.  The
// public selector is the only interoperability surface used here; none of the
// external tweak's placement or persistence implementation is included.
//


#import "Shared.h"
#import "../Manager/ARITweakManager.h"

#import <CydiaSubstrate/CydiaSubstrate.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <atomic>
#include <stdlib.h>
#include <string.h>

// The iOS 15 unarchiver passes five size classes by value.  The public
// project header intentionally models the four-field layout used elsewhere,
// so keep this private pass-through aggregate separate and never reinterpret
// either representation as the other.
typedef struct ARIPlacementLegacyGridSizeClassSizes {
	struct SBHIconGridSize small;
	struct SBHIconGridSize medium;
	struct SBHIconGridSize large;
	struct SBHIconGridSize newsLargeTall;
	struct SBHIconGridSize extraLarge;
} ARIPlacementLegacyGridSizeClassSizes;

static_assert(sizeof(ARIPlacementLegacyGridSizeClassSizes) == 20,
	"legacy icon-state aggregate size changed");
static_assert(__alignof__(ARIPlacementLegacyGridSizeClassSizes) == 2,
	"legacy icon-state aggregate alignment changed");

typedef NS_ENUM(NSUInteger, ARIPlacementABIKind) {
	ARIPlacementABIKindVoid,
	ARIPlacementABIKindObject,
	ARIPlacementABIKindSelector,
	ARIPlacementABIKindBoolean,
	ARIPlacementABIKindInteger,
	ARIPlacementABIKindPointer,
	ARIPlacementABIKindGridSize,
	ARIPlacementABIKindLegacyGridSizeClassSizes,
};

typedef struct {
	ARIPlacementABIKind kind;
	NSUInteger size;
} ARIPlacementABIType;

#define ARI_PLACEMENT_ABI(kindValue, type) \
	((ARIPlacementABIType) { (kindValue), sizeof(type) })

static const ARIPlacementABIType ARIPlacementABIVoid = {
	ARIPlacementABIKindVoid, 0
};
static const ARIPlacementABIType ARIPlacementABIObject =
	ARI_PLACEMENT_ABI(ARIPlacementABIKindObject, id);
static const ARIPlacementABIType ARIPlacementABISelector =
	ARI_PLACEMENT_ABI(ARIPlacementABIKindSelector, SEL);
static const ARIPlacementABIType ARIPlacementABIBoolean =
	ARI_PLACEMENT_ABI(ARIPlacementABIKindBoolean, BOOL);
static const ARIPlacementABIType ARIPlacementABIInteger =
	ARI_PLACEMENT_ABI(ARIPlacementABIKindInteger, NSUInteger);
static const ARIPlacementABIType ARIPlacementABIPointer =
	ARI_PLACEMENT_ABI(ARIPlacementABIKindPointer, const void *);
static const ARIPlacementABIType ARIPlacementABIGridSize =
	ARI_PLACEMENT_ABI(ARIPlacementABIKindGridSize, struct SBHIconGridSize);
static const ARIPlacementABIType ARIPlacementABILegacyGridSizeClassSizes =
	ARI_PLACEMENT_ABI(ARIPlacementABIKindLegacyGridSizeClassSizes,
		ARIPlacementLegacyGridSizeClassSizes);

static const NSUInteger ARIPlacementMaximumDiscoveryAttempts = 8;
static const NSTimeInterval ARIPlacementDiscoveryInterval = 0.25;

static std::atomic<IMP> ARIOriginalPlacementShouldPatch(NULL);
static std::atomic<IMP> ARIOriginalPlacementGridCellInfo(NULL);
static std::atomic<IMP> ARIOriginalPlacementAddIcon(NULL);
static std::atomic<IMP> ARIOriginalPlacementGridSize(NULL);
static std::atomic<IMP> ARIOriginalPlacementFolderUnarchive(NULL);
static std::atomic<IMP> ARIOriginalPlacementLegacyListUnarchive(NULL);
static std::atomic<IMP> ARIOriginalPlacementPointerListUnarchive(NULL);
static std::atomic<IMP> ARIOriginalPlacementObjectListUnarchive(NULL);
static std::atomic_bool ARIPlacementGetterInstalled(false);
static std::atomic_bool ARIPlacementGetterInstallAttempted(false);
static std::atomic_bool ARIPlacementGridCellBoundaryAttempted(false);
static std::atomic_bool ARIPlacementGridCellBoundaryInstalled(false);
static std::atomic_bool ARIPlacementRootSuppressionActive(false);
static std::atomic_bool ARIPlacementModelAddBoundaryAttempted(false);
static std::atomic_bool ARIPlacementModelAddBoundaryInstalled(false);
static std::atomic_bool ARIPlacementModelAddBoundaryActive(false);
static std::atomic_bool ARIPlacementBlockLogged(false);
static std::atomic_bool ARIPlacementRootSuppressionLogged(false);
static std::atomic_bool ARIPlacementModelAddBlockLogged(false);
static std::atomic_bool ARIPlacementObservationFailureLogged(false);
static std::atomic_bool ARIPlacementDiscoveryActive(true);
static std::atomic_bool ARIPlacementImageCallbacksReady(false);
static std::atomic_bool ARIPlacementImageRetryQueued(false);
static std::atomic_uint ARIPlacementDiscoveryGeneration(0);
static std::atomic_bool ARIPlacementUnarchiveBoundaryAttempted(false);
static std::atomic_bool ARIPlacementUnarchiveBoundaryInstalled(false);
static std::atomic_bool ARIPlacementUnarchiveBoundaryActive(false);
static void *ARIPlacementModelHostsKey = &ARIPlacementModelHostsKey;
static void *ARIPlacementHostObservationKey =
	&ARIPlacementHostObservationKey;
static __thread void *ARIPlacementActiveHost = NULL;
static __thread void *ARIPlacementActiveModel = NULL;
static __thread NSUInteger ARIPlacementGetterDepth = 0;

typedef NS_ENUM(NSUInteger, ARIPlacementSemanticRole) {
	ARIPlacementSemanticRoleUnknown,
	ARIPlacementSemanticRoleEligible,
	ARIPlacementSemanticRoleNonHome,
};

typedef struct ARIPlacementSemanticScope {
	void *owner;
	ARIPlacementSemanticRole role;
	struct ARIPlacementSemanticScope *previous;
} ARIPlacementSemanticScope;

static __thread ARIPlacementSemanticScope *
	ARIPlacementActiveSemanticScope = NULL;

@interface ARIPlacementUnarchiveRoles : NSObject
@property (nonatomic, strong) NSArray *eligibleRepresentations;
@property (nonatomic, strong) NSArray *nonHomeRepresentations;
@end

@implementation ARIPlacementUnarchiveRoles
@end

typedef struct ARIPlacementUnarchiveFrame {
	void *unarchiver;
	void *context;
	__unsafe_unretained ARIPlacementUnarchiveRoles *roles;
	struct ARIPlacementUnarchiveFrame *previous;
} ARIPlacementUnarchiveFrame;

static __thread ARIPlacementUnarchiveFrame *
	ARIPlacementActiveUnarchiveFrame = NULL;

static NSString *ARIPlacementIconListsArchiveKey = nil;
static NSString *ARIPlacementDockArchiveKey = nil;
static NSString *ARIPlacementTodayArchiveKey = nil;
static NSString *ARIPlacementFavoriteTodayArchiveKey = nil;
static NSString *ARIPlacementIgnoredArchiveKey = nil;
static NSString *ARIPlacementDockUtilitiesArchiveKey = nil;

@interface ARIPlacementHostObservation : NSObject
@property (nonatomic, weak) id host;
@property (nonatomic, weak) id model;
@end

@implementation ARIPlacementHostObservation
@end

@interface ARIPlacementModelHosts : NSObject
@property (nonatomic, strong) NSHashTable *hosts;
@end

@implementation ARIPlacementModelHosts

- (instancetype)init {
	self = [super init];
	if(self) _hosts = [NSHashTable weakObjectsHashTable];
	return self;
}

@end

typedef struct {
	void *previousHost;
	void *previousModel;
} ARIPlacementHostScope;

typedef struct ARIPlacementGridBypassScope {
	void *model;
	BOOL pending;
	BOOL consumed;
	struct ARIPlacementGridBypassScope *previous;
} ARIPlacementGridBypassScope;

static __thread ARIPlacementGridBypassScope *
	ARIPlacementActiveGridBypassScope = NULL;

typedef struct ARIPlacementGridCellScope {
	void *model;
	BOOL suppress;
	struct ARIPlacementGridCellScope *previous;
} ARIPlacementGridCellScope;

static __thread ARIPlacementGridCellScope *
	ARIPlacementActiveGridCellScope = NULL;

typedef NS_ENUM(NSUInteger, ARIPlacementHostPolicy) {
	ARIPlacementHostPolicyUnknown,
	ARIPlacementHostPolicyEligible,
	ARIPlacementHostPolicyIneligible,
	ARIPlacementHostPolicyRoot,
	ARIPlacementHostPolicyFloatingDock,
	ARIPlacementHostPolicyAmbiguous,
	ARIPlacementHostPolicyUnrecognized,
};

static struct SBHIconGridSize ARIPlacementGridSizeReplacement(
	id self, SEL selector);
static id ARIPlacementGridCellInfoReplacement(id self, SEL selector,
	struct SBHIconGridSize gridSize, NSUInteger options);

static const char *ARIPlacementUnqualifiedType(const char *encoding) {
	while(encoding && *encoding && strchr("rnNoORV", *encoding)) encoding++;
	return encoding;
}

static char *ARIPlacementCopyCanonicalAggregate(const char *encoding) {
	const char *cursor = ARIPlacementUnqualifiedType(encoding);
	if(!cursor) return NULL;

	size_t inputLength = strlen(cursor);
	char *canonical = (char *)calloc(inputLength + 1, sizeof(char));
	if(!canonical) return NULL;

	size_t outputIndex = 0;
	while(*cursor) {
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
			while(*cursor && *cursor != '=' && *cursor != closing) cursor++;
			if(*cursor == '=') canonical[outputIndex++] = *cursor++;
			else if(*cursor == closing) canonical[outputIndex++] = *cursor++;
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

static BOOL ARIPlacementTypeMatches(const char *encoding,
									ARIPlacementABIType expected) {
	const char *type = ARIPlacementUnqualifiedType(encoding);
	if(!type || !*type) return NO;
	if(expected.kind == ARIPlacementABIKindVoid)
		return *type == 'v' && expected.size == 0;

	BOOL kindMatches = NO;
	switch(expected.kind) {
		case ARIPlacementABIKindObject:
			kindMatches = *type == '@' && type[1] != '?';
			break;
		case ARIPlacementABIKindSelector:
			kindMatches = *type == ':';
			break;
		case ARIPlacementABIKindBoolean:
			kindMatches = *type == 'B' || *type == 'c' || *type == 'C';
			break;
		case ARIPlacementABIKindInteger:
			kindMatches = strchr("cCsSiIlLqQ", *type) != NULL;
			break;
		case ARIPlacementABIKindPointer:
			kindMatches = *type == '^';
			break;
		case ARIPlacementABIKindGridSize:
		case ARIPlacementABIKindLegacyGridSizeClassSizes:
			kindMatches = *type == '{';
			break;
		case ARIPlacementABIKindVoid:
			break;
	}
	if(!kindMatches) return NO;

	NSUInteger actualSize = 0;
	NSUInteger actualAlignment = 0;
	NSGetSizeAndAlignment(type, &actualSize, &actualAlignment);
	if(actualSize != expected.size) return NO;

	if(expected.kind != ARIPlacementABIKindGridSize &&
	   expected.kind != ARIPlacementABIKindLegacyGridSizeClassSizes) return YES;
	NSUInteger expectedAlignment = expected.kind == ARIPlacementABIKindGridSize
		? __alignof__(struct SBHIconGridSize)
		: __alignof__(ARIPlacementLegacyGridSizeClassSizes);
	if(actualAlignment != expectedAlignment) return NO;

	char *actual = ARIPlacementCopyCanonicalAggregate(type);
	char *wanted = ARIPlacementCopyCanonicalAggregate(
		expected.kind == ARIPlacementABIKindGridSize
			? @encode(struct SBHIconGridSize)
			: @encode(ARIPlacementLegacyGridSizeClassSizes));
	BOOL matches = actual && wanted && strcmp(actual, wanted) == 0;
	free(actual);
	free(wanted);
	return matches;
}

static BOOL ARIPlacementMethodMatches(Method method,
									  ARIPlacementABIType returnType,
									  const ARIPlacementABIType *arguments,
									  NSUInteger argumentCount) {
	if(!method || method_getNumberOfArguments(method) != argumentCount + 2)
		return NO;

	char *selfType = method_copyArgumentType(method, 0);
	char *selectorType = method_copyArgumentType(method, 1);
	BOOL matches = ARIPlacementTypeMatches(selfType, ARIPlacementABIObject) &&
		ARIPlacementTypeMatches(selectorType, ARIPlacementABISelector);
	free(selfType);
	free(selectorType);
	if(!matches) return NO;

	char *actualReturnType = method_copyReturnType(method);
	matches = ARIPlacementTypeMatches(actualReturnType, returnType);
	free(actualReturnType);
	if(!matches) return NO;

	for(NSUInteger index = 0; index < argumentCount; index++) {
		char *argumentType = method_copyArgumentType(
			method, (unsigned int)index + 2);
		matches = ARIPlacementTypeMatches(argumentType, arguments[index]);
		free(argumentType);
		if(!matches) return NO;
	}
	return YES;
}

static Method ARIPlacementDirectInstanceMethod(Class cls, SEL selector) {
	if(!cls || !selector) return NULL;

	unsigned int count = 0;
	Method *methods = class_copyMethodList(cls, &count);
	Method result = NULL;
	for(unsigned int index = 0; index < count; index++) {
		if(method_getName(methods[index]) == selector) {
			result = methods[index];
			break;
		}
	}
	free(methods);
	return result;
}

static id ARIPlacementObjectByCallingNoArgumentSelector(id object,
												 SEL selector) {
	if(!object || !selector) return nil;
	Method method = class_getInstanceMethod(object_getClass(object), selector);
	if(!ARIPlacementMethodMatches(method, ARIPlacementABIObject, NULL, 0))
		return nil;
	return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL ARIPlacementHostOwnsModel(id host, id model) {
	return host && model &&
		ARIPlacementObjectByCallingNoArgumentSelector(
			host, @selector(model)) == model;
}

static ARIPlacementHostPolicy ARIPlacementPolicyForLocation(id value) {
	if(![value isKindOfClass:[NSString class]] ||
	   [(NSString *)value length] == 0) {
		return ARIPlacementHostPolicyUnknown;
	}
	NSString *location = (NSString *)value;
	if(IsLocationFloatingDock(location))
		return ARIPlacementHostPolicyFloatingDock;
	// Match the external provider's concrete Root surface exactly. A substring
	// match would silently opt an unknown future SpringBoard location into a
	// third-party placement policy it may not support.
	if([location isEqualToString:@"SBIconLocationRoot"] ||
	   [location isEqualToString:@"SBIconLocationRootWithWidgets"])
		return ARIPlacementHostPolicyRoot;
	if(IsLocationDock(location) || IsLocationFolder(location))
		return ARIPlacementHostPolicyEligible;
	if(IsLocationFloatingDockSuggestions(location) ||
	   IsLocationAppLibrary(location) ||
	   [location isEqualToString:@"SBIconLocationAppLibraryCategoryPod"] ||
	   [location isEqualToString:
		   @"SBIconLocationAppLibraryCategoryPodExpanded"] ||
	   [location isEqualToString:@"SBIconLocationTodayView"])
		return ARIPlacementHostPolicyIneligible;
	return ARIPlacementHostPolicyUnrecognized;
}

static ARIPlacementHostPolicy ARIPlacementPolicyForHost(id host, id model) {
	if(!ARIPlacementHostOwnsModel(host, model))
		return ARIPlacementHostPolicyUnknown;
	return ARIPlacementPolicyForLocation(
		ARIPlacementObjectByCallingNoArgumentSelector(
			host, @selector(iconLocation)));
}

static ARIPlacementHostPolicy ARIPlacementPolicyForModel(id model) {
	// SpringBoard's icon-list lifecycle is a main-thread UI contract.  Refuse
	// to classify from a background thread instead of racing a reused host.
	if(!model || ![NSThread isMainThread])
		return ARIPlacementHostPolicyUnknown;

	id activeModel = (__bridge id)ARIPlacementActiveModel;
	id activeHost = (__bridge id)ARIPlacementActiveHost;
	if(activeModel == model && activeHost)
		return ARIPlacementPolicyForHost(activeHost, model);

	ARIPlacementModelHosts *registry = objc_getAssociatedObject(
		model, ARIPlacementModelHostsKey);
	NSArray *hosts = registry.hosts.allObjects;
	id onlyLiveHost = nil;
	for(id host in hosts) {
		if(!ARIPlacementHostOwnsModel(host, model)) {
			[registry.hosts removeObject:host];
			continue;
		}
		if(onlyLiveHost && onlyLiveHost != host) {
			// A model temporarily shared by multiple list views is ambiguous.
			// Fail open so Root/Folder placement is never disabled by a stale
			// Floating Dock host; the active layout scope remains precise.
			return ARIPlacementHostPolicyAmbiguous;
		}
		onlyLiveHost = host;
	}
	if(onlyLiveHost) return ARIPlacementPolicyForHost(onlyLiveHost, model);

	// MainLayout records the concrete host identity on the model. Use it only
	// when there is no live observed host; a live host with an empty location is
	// an authoritative transient state and is intentionally handled above.
	return ARIPlacementPolicyForLocation(
		ARIPlacementObjectByCallingNoArgumentSelector(
			model, @selector(_atriaLocation)));
}

static BOOL ARIPlacementInstallGetterBoundary(void);
static BOOL ARIPlacementInstallGridCellBoundary(
	Class modelClass, void *providerImageBase);
static BOOL ARIPlacementInstallUnarchiveBoundaries(void);
static void ARIPlacementActivateUnarchiveBoundary(void);
static void ARIPlacementBeginBoundedDiscovery(void);

static id ARIPlacementNormalizedModel(id model) {
	id unrotated = ARIPlacementObjectByCallingNoArgumentSelector(
		model, NSSelectorFromString(@"unrotatedIconListModel"));
	return unrotated ?: model;
}

static BOOL ARIPlacementModelBelongsToSemanticOwner(id model, id owner) {
	if(!model || !owner) return NO;
	id subject = ARIPlacementNormalizedModel(model);
	id folder = ARIPlacementObjectByCallingNoArgumentSelector(
		subject, @selector(folder));
	id parent = ARIPlacementObjectByCallingNoArgumentSelector(
		subject, NSSelectorFromString(@"parent"));
	// Conflicting ownership evidence makes the private model relationship
	// ambiguous, so decline classification and preserve the original behavior.
	if(folder && parent && folder != parent) return NO;
	return (folder ?: parent) == owner;
}

static ARIPlacementSemanticRole ARIPlacementSemanticRoleForModel(id model) {
	if(!model) return ARIPlacementSemanticRoleUnknown;
	// The newest list-unarchive scope is authoritative.  Treat it as a barrier
	// even when its owner cannot be proven, rather than leaking a role from an
	// enclosing recursive folder conversion into the current list.
	ARIPlacementSemanticScope *scope = ARIPlacementActiveSemanticScope;
	if(scope && ARIPlacementModelBelongsToSemanticOwner(
			model, (__bridge id)scope->owner)) return scope->role;
	return ARIPlacementSemanticRoleUnknown;
}

static NSString *ARIPlacementResolveArchiveKey(void *imageHandle,
		const char *symbolName) {
	if(!imageHandle || !symbolName) return nil;
	void *slot = dlsym(imageHandle, symbolName);
	if(!slot) return nil;
	@try {
		__unsafe_unretained id *valueSlot = (__unsafe_unretained id *)slot;
		id candidate = *valueSlot;
		return [candidate isKindOfClass:[NSString class]]
			? (NSString *)candidate : nil;
	} @catch(__unused NSException *exception) {
		return nil;
	}
}

static BOOL ARIPlacementResolvedArchiveKeysAreDistinct(void) {
	NSString *keys[] = {
		ARIPlacementIconListsArchiveKey,
		ARIPlacementDockArchiveKey,
		ARIPlacementTodayArchiveKey,
		ARIPlacementFavoriteTodayArchiveKey,
		ARIPlacementIgnoredArchiveKey,
		ARIPlacementDockUtilitiesArchiveKey,
	};
	for(NSUInteger left = 0; left < sizeof(keys) / sizeof(keys[0]); left++) {
		if(!keys[left]) continue;
		for(NSUInteger right = left + 1;
			right < sizeof(keys) / sizeof(keys[0]); right++) {
			if(keys[left] == keys[right] ||
			   [keys[left] isEqualToString:keys[right]]) return NO;
		}
	}
	return YES;
}

static void ARIPlacementAppendArrayValue(NSMutableArray *destination,
		id value) {
	if([value isKindOfClass:[NSArray class]]) [destination addObject:value];
}

static ARIPlacementUnarchiveRoles *ARIPlacementBuildUnarchiveRoles(
		id representation) {
	if(![representation isKindOfClass:[NSDictionary class]]) return nil;
	NSDictionary *dictionary = (NSDictionary *)representation;
	NSMutableArray *eligible = [NSMutableArray array];
	NSMutableArray *nonHome = [NSMutableArray array];

	id pages = ARIPlacementIconListsArchiveKey
		? dictionary[ARIPlacementIconListsArchiveKey] : nil;
	if([pages isKindOfClass:[NSArray class]]) {
		// Current releases pass each direct page array to the list converter.
		for(id page in (NSArray *)pages)
			ARIPlacementAppendArrayValue(eligible, page);
	}

	id dock = ARIPlacementDockArchiveKey
		? dictionary[ARIPlacementDockArchiveKey] : nil;
	ARIPlacementAppendArrayValue(eligible, dock);

	NSString *nonHomeKeys[] = {
		ARIPlacementTodayArchiveKey,
		ARIPlacementFavoriteTodayArchiveKey,
		ARIPlacementIgnoredArchiveKey,
		ARIPlacementDockUtilitiesArchiveKey,
	};
	for(NSUInteger index = 0;
		index < sizeof(nonHomeKeys) / sizeof(nonHomeKeys[0]); index++) {
		NSString *key = nonHomeKeys[index];
		if(key) ARIPlacementAppendArrayValue(nonHome, dictionary[key]);
	}

	ARIPlacementUnarchiveRoles *roles = [ARIPlacementUnarchiveRoles new];
	roles.eligibleRepresentations = [eligible copy];
	roles.nonHomeRepresentations = [nonHome copy];
	return roles;
}

static BOOL ARIPlacementArrayContainsIdenticalObject(NSArray *array,
		id object) {
	for(id candidate in array) {
		if(candidate == object) return YES;
	}
	return NO;
}

static ARIPlacementSemanticRole ARIPlacementSemanticRoleForRepresentation(
		id representation, id context, id unarchiver) {
	for(ARIPlacementUnarchiveFrame *frame = ARIPlacementActiveUnarchiveFrame;
		frame; frame = frame->previous) {
		if(frame->unarchiver != (__bridge void *)unarchiver) continue;
		if(frame->context != (__bridge void *)context) continue;
		// The newest frame for this context is authoritative, including an
		// unknown result. This is the recursion barrier for malformed/nested data.
		BOOL eligible = ARIPlacementArrayContainsIdenticalObject(
			frame->roles.eligibleRepresentations, representation);
		BOOL nonHome = ARIPlacementArrayContainsIdenticalObject(
			frame->roles.nonHomeRepresentations, representation);
		if(eligible == nonHome) return ARIPlacementSemanticRoleUnknown;
		return nonHome ? ARIPlacementSemanticRoleNonHome
			: ARIPlacementSemanticRoleEligible;
	}
	return ARIPlacementSemanticRoleUnknown;
}

static void ARIPlacementResolveListSemanticScope(id representation,
		id context, id unarchiver, void **owner,
		ARIPlacementSemanticRole *role) {
	*owner = NULL;
	*role = ARIPlacementSemanticRoleUnknown;
	@try {
		*role = ARIPlacementSemanticRoleForRepresentation(
			representation, context, unarchiver);
		id currentFolder = ARIPlacementObjectByCallingNoArgumentSelector(
			context, sel_registerName("_currentFolder"));
		*owner = (__bridge void *)currentFolder;
	} @catch(__unused NSException *exception) {
		*owner = NULL;
		*role = ARIPlacementSemanticRoleUnknown;
	}
}

static id ARIPlacementFolderUnarchiveReplacement(id self, SEL selector,
		id representation, id context) {
	IMP implementation = ARIOriginalPlacementFolderUnarchive.load(
		std::memory_order_acquire);
	if(!implementation ||
	   implementation == (IMP)ARIPlacementFolderUnarchiveReplacement)
		return nil;

	// This synchronous entry occurs after tweak constructors and before any
	// child list is converted, closing both provider-first and Atria-first load
	// orders without depending on the first run-loop turn.
	if(ARIPlacementDiscoveryActive.load(std::memory_order_acquire) &&
	   !ARIPlacementGetterInstalled.load(std::memory_order_acquire) &&
	   !ARIPlacementGetterInstallAttempted.load(std::memory_order_acquire)) {
		@try {
			ARIPlacementInstallGetterBoundary();
		} @catch(__unused NSException *exception) {
			// Discovery is optional; never obstruct stock icon-state recovery.
		}
	}

	if(!ARIPlacementUnarchiveBoundaryActive.load(
		   std::memory_order_acquire)) {
		return ((id (*)(id, SEL, id, id))implementation)(
			self, selector, representation, context);
	}

	__attribute__((objc_precise_lifetime))
	ARIPlacementUnarchiveRoles *roles = nil;
	@try {
		roles = ARIPlacementBuildUnarchiveRoles(representation);
	} @catch(__unused NSException *exception) {
		roles = nil;
	}
	ARIPlacementUnarchiveFrame frame = {
		.unarchiver = (__bridge void *)self,
		.context = (__bridge void *)context,
		.roles = roles,
		.previous = ARIPlacementActiveUnarchiveFrame,
	};
	ARIPlacementActiveUnarchiveFrame = &frame;
	id result = nil;
	@try {
		result = ((id (*)(id, SEL, id, id))implementation)(
			self, selector, representation, context);
	} @finally {
		ARIPlacementActiveUnarchiveFrame = frame.previous;
	}
	return result;
}

static id ARIPlacementLegacyListUnarchiveReplacement(id self, SEL selector,
		id representation, struct SBHIconGridSize listGridSize,
		struct SBHIconGridSize nonDefaultGridSize,
		ARIPlacementLegacyGridSizeClassSizes classSizes,
		NSUInteger rotatedClass, NSUInteger allowedClasses,
		NSUInteger addOptions, id identifier, id context, id overflow) {
	IMP implementation = ARIOriginalPlacementLegacyListUnarchive.load(
		std::memory_order_acquire);
	if(!implementation || implementation ==
			(IMP)ARIPlacementLegacyListUnarchiveReplacement) return nil;

	ARIPlacementSemanticScope scope = {
		.owner = NULL,
		.role = ARIPlacementSemanticRoleUnknown,
		.previous = ARIPlacementActiveSemanticScope,
	};
	BOOL linked = ARIPlacementUnarchiveBoundaryActive.load(
		std::memory_order_acquire);
	if(linked) {
		ARIPlacementResolveListSemanticScope(
			representation, context, self, &scope.owner, &scope.role);
		ARIPlacementActiveSemanticScope = &scope;
	}
	id result = nil;
	@try {
		result = ((id (*)(id, SEL, id, struct SBHIconGridSize,
			struct SBHIconGridSize, ARIPlacementLegacyGridSizeClassSizes,
			NSUInteger, NSUInteger, NSUInteger, id, id, id))implementation)(
				self, selector, representation, listGridSize,
				nonDefaultGridSize, classSizes, rotatedClass, allowedClasses,
				addOptions, identifier, context, overflow);
	} @finally {
		if(linked) ARIPlacementActiveSemanticScope = scope.previous;
	}
	return result;
}

static id ARIPlacementPointerListUnarchiveReplacement(id self, SEL selector,
		id representation, const void *properties, id identifier,
		id context, id overflow) {
	IMP implementation = ARIOriginalPlacementPointerListUnarchive.load(
		std::memory_order_acquire);
	if(!implementation || implementation ==
			(IMP)ARIPlacementPointerListUnarchiveReplacement) return nil;
	ARIPlacementSemanticScope scope = {
		.owner = NULL,
		.role = ARIPlacementSemanticRoleUnknown,
		.previous = ARIPlacementActiveSemanticScope,
	};
	BOOL linked = ARIPlacementUnarchiveBoundaryActive.load(
		std::memory_order_acquire);
	if(linked) {
		ARIPlacementResolveListSemanticScope(
			representation, context, self, &scope.owner, &scope.role);
		ARIPlacementActiveSemanticScope = &scope;
	}
	id result = nil;
	@try {
		result = ((id (*)(id, SEL, id, const void *, id, id, id))
			implementation)(self, selector, representation, properties,
				identifier, context, overflow);
	} @finally {
		if(linked) ARIPlacementActiveSemanticScope = scope.previous;
	}
	return result;
}

static id ARIPlacementObjectListUnarchiveReplacement(id self, SEL selector,
		id representation, id properties, id identifier,
		id context, id overflow) {
	IMP implementation = ARIOriginalPlacementObjectListUnarchive.load(
		std::memory_order_acquire);
	if(!implementation || implementation ==
			(IMP)ARIPlacementObjectListUnarchiveReplacement) return nil;
	ARIPlacementSemanticScope scope = {
		.owner = NULL,
		.role = ARIPlacementSemanticRoleUnknown,
		.previous = ARIPlacementActiveSemanticScope,
	};
	BOOL linked = ARIPlacementUnarchiveBoundaryActive.load(
		std::memory_order_acquire);
	if(linked) {
		ARIPlacementResolveListSemanticScope(
			representation, context, self, &scope.owner, &scope.role);
		ARIPlacementActiveSemanticScope = &scope;
	}
	id result = nil;
	@try {
		result = ((id (*)(id, SEL, id, id, id, id, id))implementation)(
			self, selector, representation, properties,
			identifier, context, overflow);
	} @finally {
		if(linked) ARIPlacementActiveSemanticScope = scope.previous;
	}
	return result;
}

typedef NS_ENUM(NSUInteger, ARIPlacementListUnarchiveVariant) {
	ARIPlacementListUnarchiveVariantNone,
	ARIPlacementListUnarchiveVariantLegacy,
	ARIPlacementListUnarchiveVariantPointerProperties,
	ARIPlacementListUnarchiveVariantObjectProperties,
};

static void ARIPlacementResolveArchiveKeys(void *imageHandle) {
	ARIPlacementIconListsArchiveKey =
		ARIPlacementResolveArchiveKey(imageHandle, "kSBIconStateIconLists");
	ARIPlacementDockArchiveKey =
		ARIPlacementResolveArchiveKey(imageHandle, "kSBIconStateDock");
	ARIPlacementTodayArchiveKey =
		ARIPlacementResolveArchiveKey(
			imageHandle, "kSBIconStateTodayPageList");
	ARIPlacementFavoriteTodayArchiveKey =
		ARIPlacementResolveArchiveKey(
			imageHandle, "kSBIconStateFavoriteTodayPageList");
	ARIPlacementIgnoredArchiveKey =
		ARIPlacementResolveArchiveKey(imageHandle, "kSBIconStateIgnoredList");
	ARIPlacementDockUtilitiesArchiveKey =
		ARIPlacementResolveArchiveKey(
			imageHandle, "kSBIconStateDockUtilities");
}

static void ARIPlacementActivateUnarchiveBoundary(void) {
	BOOL active = ARIPlacementUnarchiveBoundaryInstalled.load(
			std::memory_order_acquire) &&
		ARIPlacementModelAddBoundaryActive.load(std::memory_order_acquire) &&
		ARIOriginalPlacementFolderUnarchive.load(
			std::memory_order_acquire) != NULL &&
		(ARIOriginalPlacementLegacyListUnarchive.load(
				std::memory_order_acquire) != NULL ||
		 ARIOriginalPlacementPointerListUnarchive.load(
				std::memory_order_acquire) != NULL ||
		 ARIOriginalPlacementObjectListUnarchive.load(
				std::memory_order_acquire) != NULL);
	ARIPlacementUnarchiveBoundaryActive.store(
		active, std::memory_order_release);
}

static BOOL ARIPlacementInstallUnarchiveBoundaries(void) {
	if(ARIPlacementUnarchiveBoundaryInstalled.load(
			std::memory_order_acquire)) {
		ARIPlacementActivateUnarchiveBoundary();
		return YES;
	}
	if(ARIPlacementUnarchiveBoundaryAttempted.load(
			std::memory_order_acquire)) return NO;

	@synchronized([ARITweakManager class]) {
		if(ARIPlacementUnarchiveBoundaryInstalled.load(
				std::memory_order_acquire)) {
			ARIPlacementActivateUnarchiveBoundary();
			return YES;
		}
		if(ARIPlacementUnarchiveBoundaryAttempted.load(
				std::memory_order_acquire)) return NO;

		Class unarchiverClass = objc_getClass("SBHIconStateUnarchiver");
		SEL folderSelector = sel_registerName(
			"_folderFromRepresentation:withContext:");
		SEL legacyListSelector = sel_registerName(
			"_listFromRepresentation:listGridSize:"
			"listWithNonDefaultSizedIconsGridSize:gridSizeClassSizes:"
			"listRotatedLayoutClusterGridSizeClass:"
			"listAllowedGridSizeClasses:listAddOptions:identifier:"
			"context:overflow:");
		SEL modernListSelector = sel_registerName(
			"_listFromRepresentation:properties:identifier:context:overflow:");

		const ARIPlacementABIType folderArguments[] = {
			ARIPlacementABIObject,
			ARIPlacementABIObject,
		};
		Method folderMethod = ARIPlacementDirectInstanceMethod(
			unarchiverClass, folderSelector);
		if(!ARIPlacementMethodMatches(folderMethod,
				ARIPlacementABIObject, folderArguments, 2)) return NO;

		Method listMethod = NULL;
		SEL listSelector = NULL;
		IMP listReplacement = NULL;
		std::atomic<IMP> *listOriginal = NULL;
		ARIPlacementListUnarchiveVariant variant =
			ARIPlacementListUnarchiveVariantNone;

		const ARIPlacementABIType legacyArguments[] = {
			ARIPlacementABIObject,
			ARIPlacementABIGridSize,
			ARIPlacementABIGridSize,
			ARIPlacementABILegacyGridSizeClassSizes,
			ARIPlacementABIInteger,
			ARIPlacementABIInteger,
			ARIPlacementABIInteger,
			ARIPlacementABIObject,
			ARIPlacementABIObject,
			ARIPlacementABIObject,
		};
		Method legacyMethod = ARIPlacementDirectInstanceMethod(
			unarchiverClass, legacyListSelector);
		if(ARIPlacementMethodMatches(legacyMethod,
				ARIPlacementABIObject, legacyArguments, 10)) {
			variant = ARIPlacementListUnarchiveVariantLegacy;
			listMethod = legacyMethod;
			listSelector = legacyListSelector;
			listReplacement = (IMP)ARIPlacementLegacyListUnarchiveReplacement;
			listOriginal = &ARIOriginalPlacementLegacyListUnarchive;
		} else {
			Method modernMethod = ARIPlacementDirectInstanceMethod(
				unarchiverClass, modernListSelector);
			const ARIPlacementABIType pointerArguments[] = {
				ARIPlacementABIObject,
				ARIPlacementABIPointer,
				ARIPlacementABIObject,
				ARIPlacementABIObject,
				ARIPlacementABIObject,
			};
			const ARIPlacementABIType objectArguments[] = {
				ARIPlacementABIObject,
				ARIPlacementABIObject,
				ARIPlacementABIObject,
				ARIPlacementABIObject,
				ARIPlacementABIObject,
			};
			if(ARIPlacementMethodMatches(modernMethod,
					ARIPlacementABIObject, pointerArguments, 5)) {
				variant = ARIPlacementListUnarchiveVariantPointerProperties;
				listMethod = modernMethod;
				listSelector = modernListSelector;
				listReplacement =
					(IMP)ARIPlacementPointerListUnarchiveReplacement;
				listOriginal = &ARIOriginalPlacementPointerListUnarchive;
			} else if(ARIPlacementMethodMatches(modernMethod,
					ARIPlacementABIObject, objectArguments, 5)) {
				variant = ARIPlacementListUnarchiveVariantObjectProperties;
				listMethod = modernMethod;
				listSelector = modernListSelector;
				listReplacement =
					(IMP)ARIPlacementObjectListUnarchiveReplacement;
				listOriginal = &ARIOriginalPlacementObjectListUnarchive;
			}
		}
		if(variant == ARIPlacementListUnarchiveVariantNone ||
		   !listMethod || !listSelector || !listReplacement || !listOriginal)
			return NO;

		IMP folderImplementation = method_getImplementation(folderMethod);
		IMP listImplementation = method_getImplementation(listMethod);
		if(!folderImplementation || !listImplementation ||
		   folderImplementation ==
			   (IMP)ARIPlacementFolderUnarchiveReplacement ||
		   listImplementation == listReplacement) return NO;
		// Resolve data exports from the class-defining framework, not from the
		// current method IMP: an earlier interoperability hook may legitimately
		// make that IMP belong to a different image.
		const char *frameworkPath = class_getImageName(unarchiverClass);
		if(!frameworkPath) return NO;
		void *frameworkHandle = dlopen(frameworkPath,
			RTLD_LAZY | RTLD_NOLOAD);
		if(!frameworkHandle) return NO;
		ARIPlacementResolveArchiveKeys(frameworkHandle);
		dlclose(frameworkHandle);
		// A standard-page key, the ordinary Dock key, and at least one special
		// list key are required before this classifier can make a useful claim.
		// Missing or aliased exports leave the entire boundary dormant.
		BOOL hasSpecialKey = ARIPlacementTodayArchiveKey ||
			ARIPlacementFavoriteTodayArchiveKey ||
			ARIPlacementIgnoredArchiveKey ||
			ARIPlacementDockUtilitiesArchiveKey;
		if(!ARIPlacementIconListsArchiveKey ||
		   !ARIPlacementDockArchiveKey || !hasSpecialKey ||
		   !ARIPlacementResolvedArchiveKeysAreDistinct()) return NO;

		ARIOriginalPlacementFolderUnarchive.store(
			folderImplementation, std::memory_order_release);
		listOriginal->store(listImplementation, std::memory_order_release);
		// From this point onward a retry could capture one of our own wrappers.
		ARIPlacementUnarchiveBoundaryAttempted.store(
			true, std::memory_order_release);

		IMP folderPredecessor = NULL;
		MSHookMessageEx(unarchiverClass, folderSelector,
			(IMP)ARIPlacementFolderUnarchiveReplacement, &folderPredecessor);
		if(folderPredecessor && folderPredecessor !=
				(IMP)ARIPlacementFolderUnarchiveReplacement) {
			ARIOriginalPlacementFolderUnarchive.store(
				folderPredecessor, std::memory_order_release);
		}

		IMP listPredecessor = NULL;
		MSHookMessageEx(unarchiverClass, listSelector,
			listReplacement, &listPredecessor);
		if(listPredecessor && listPredecessor != listReplacement)
			listOriginal->store(listPredecessor, std::memory_order_release);

		Method installedFolderMethod = ARIPlacementDirectInstanceMethod(
			unarchiverClass, folderSelector);
		Method installedListMethod = ARIPlacementDirectInstanceMethod(
			unarchiverClass, listSelector);
		BOOL installed = installedFolderMethod && installedListMethod &&
			method_getImplementation(installedFolderMethod) ==
				(IMP)ARIPlacementFolderUnarchiveReplacement &&
			method_getImplementation(installedListMethod) == listReplacement &&
			folderPredecessor && folderPredecessor !=
				(IMP)ARIPlacementFolderUnarchiveReplacement &&
			listPredecessor && listPredecessor != listReplacement;
		ARIPlacementUnarchiveBoundaryInstalled.store(
			installed, std::memory_order_release);
		ARIPlacementActivateUnarchiveBoundary();
		return installed;
	}
}

static id ARIPlacementObserveListView(id listView) {
	if(!listView || ![NSThread isMainThread]) return nil;

	id model = ARIPlacementObjectByCallingNoArgumentSelector(
		listView, @selector(model));
	ARIPlacementHostObservation *previous = objc_getAssociatedObject(
		listView, ARIPlacementHostObservationKey);
	id previousModel = previous.model;
	if(previousModel && previousModel != model &&
	   previous.host == listView) {
		ARIPlacementModelHosts *previousRegistry =
			objc_getAssociatedObject(previousModel,
				ARIPlacementModelHostsKey);
		[previousRegistry.hosts removeObject:listView];
		if(previousRegistry.hosts.count == 0) {
			objc_setAssociatedObject(previousModel,
				ARIPlacementModelHostsKey, nil,
				OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
	}
	if(!model) {
		objc_setAssociatedObject(listView,
			ARIPlacementHostObservationKey, nil,
			OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return nil;
	}

	ARIPlacementHostObservation *observation = previous;
	if(!observation) observation = [ARIPlacementHostObservation new];
	observation.host = listView;
	observation.model = model;
	objc_setAssociatedObject(listView, ARIPlacementHostObservationKey,
		observation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	ARIPlacementModelHosts *registry = objc_getAssociatedObject(
		model, ARIPlacementModelHostsKey);
	if(!registry) {
		registry = [ARIPlacementModelHosts new];
		objc_setAssociatedObject(model, ARIPlacementModelHostsKey,
			registry, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	[registry.hosts addObject:listView];

	// This is also an on-demand discovery point for Atria-first load order.
	if(ARIPlacementDiscoveryActive.load(std::memory_order_acquire) &&
	   !ARIPlacementGetterInstalled.load(std::memory_order_acquire))
		ARIPlacementInstallGetterBoundary();
	return model;
}

static id ARIPlacementSafelyObserveListView(id listView) {
	@try {
		return ARIPlacementObserveListView(listView);
	} @catch(__unused NSException *exception) {
		// Observation is optional interoperability metadata. A third-party
		// replacement for model/iconLocation must never prevent SpringBoard's
		// original layout implementation from running.
		if(!ARIPlacementObservationFailureLogged.exchange(
				true, std::memory_order_acq_rel)) {
			NSLog(@"[Atria]: Floating Dock placement observation failed open");
		}
		return nil;
	}
}

void ARIObserveFloatingDockPlacementHost(SBIconListView *listView) {
	ARIPlacementSafelyObserveListView(listView);
}

static ARIPlacementHostScope ARIPlacementBeginHostScope(id host, id model) {
	ARIPlacementHostScope scope = {
		.previousHost = ARIPlacementActiveHost,
		.previousModel = ARIPlacementActiveModel,
	};
	ARIPlacementActiveHost = (__bridge void *)host;
	ARIPlacementActiveModel = (__bridge void *)model;
	return scope;
}

static void ARIPlacementEndHostScope(ARIPlacementHostScope scope) {
	ARIPlacementActiveHost = scope.previousHost;
	ARIPlacementActiveModel = scope.previousModel;
}

static BOOL ARIPlacementImplementationComesFromImage(IMP implementation,
											 void *imageBase) {
	if(!implementation || !imageBase) return NO;
	Dl_info info = {};
	return dladdr((const void *)implementation, &info) != 0 &&
		info.dli_fbase == imageBase;
}

static BOOL ARIPlacementShouldSuppressRootGrid(id model) {
	if(!model || ![NSThread isMainThread] ||
	   ARIPlacementPolicyForModel(model) != ARIPlacementHostPolicyRoot)
		return NO;

	Class placeholderClass = objc_getClass("SBPlaceholderIcon");
	if(!placeholderClass) return NO;

	SEL iconsSelector = @selector(icons);
	Class modelClass = objc_getClass("SBIconListModel");
	if(!modelClass || ![model isKindOfClass:modelClass]) return NO;
	Method iconsMethod = ARIPlacementDirectInstanceMethod(
		modelClass, iconsSelector);
	if(!ARIPlacementMethodMatches(
			iconsMethod, ARIPlacementABIObject, NULL, 0)) return NO;
	IMP iconsImplementation = method_getImplementation(iconsMethod);
	if(!iconsImplementation) return NO;

	id value = ((id (*)(id, SEL))iconsImplementation)(
		model, iconsSelector);
	if(![value isKindOfClass:[NSArray class]]) return NO;
	for(id icon in (NSArray *)value) {
		if([icon isKindOfClass:placeholderClass]) return YES;
	}
	return NO;
}

static id ARIPlacementGridCellInfoReplacement(id self, SEL selector,
		struct SBHIconGridSize gridSize, NSUInteger options) {
	IMP implementation = ARIOriginalPlacementGridCellInfo.load(
		std::memory_order_acquire);
	if(!implementation ||
	   implementation == (IMP)ARIPlacementGridCellInfoReplacement) return nil;

	ARIPlacementGridCellScope scope = {
		.model = (__bridge void *)self,
		.suppress = NO,
		.previous = ARIPlacementActiveGridCellScope,
	};
	// Link a false frame before consulting any private model state. Nested grid
	// work therefore cannot inherit an enclosing same-model decision.
	ARIPlacementActiveGridCellScope = &scope;
	id result = nil;
	@try {
		if(ARIPlacementRootSuppressionActive.load(
				std::memory_order_acquire)) {
			Method currentMethod = class_getInstanceMethod(
				object_getClass(self), selector);
			if(currentMethod && method_getImplementation(currentMethod) ==
					(IMP)ARIPlacementGridCellInfoReplacement) {
				@try {
					scope.suppress = ARIPlacementShouldSuppressRootGrid(self);
				} @catch(__unused NSException *exception) {
					scope.suppress = NO;
				}
			}
		}
		result = ((id (*)(id, SEL, struct SBHIconGridSize, NSUInteger))
			implementation)(self, selector, gridSize, options);
	} @finally {
		ARIPlacementActiveGridCellScope = scope.previous;
	}
	return result;
}

static BOOL ARIPlacementGridCellBoundaryIsCurrent(Class modelClass) {
	const ARIPlacementABIType arguments[] = {
		ARIPlacementABIGridSize,
		ARIPlacementABIInteger,
	};
	Method method = ARIPlacementDirectInstanceMethod(
		modelClass, @selector(gridCellInfoForGridSize:options:));
	return ARIPlacementMethodMatches(
			method, ARIPlacementABIObject, arguments, 2) &&
		method_getImplementation(method) ==
			(IMP)ARIPlacementGridCellInfoReplacement;
}

static BOOL ARIPlacementInstallGridCellBoundary(
		Class modelClass, void *providerImageBase) {
	if(ARIPlacementGridCellBoundaryInstalled.load(
			std::memory_order_acquire)) return YES;
	if(ARIPlacementGridCellBoundaryAttempted.load(
			std::memory_order_acquire)) return NO;
	if(!modelClass || !providerImageBase) return NO;

	SEL selector = @selector(gridCellInfoForGridSize:options:);
	Method method = ARIPlacementDirectInstanceMethod(modelClass, selector);
	const ARIPlacementABIType arguments[] = {
		ARIPlacementABIGridSize,
		ARIPlacementABIInteger,
	};
	if(!ARIPlacementMethodMatches(
			method, ARIPlacementABIObject, arguments, 2)) return NO;

	IMP current = method_getImplementation(method);
	if(!current || current == (IMP)ARIPlacementGridCellInfoReplacement ||
	   !ARIPlacementImplementationComesFromImage(
			current, providerImageBase)) return NO;

	// Publish a delegating fallback before the replacement can be called. Once
	// this mutation starts it is never retried, even if strict proof later fails.
	ARIOriginalPlacementGridCellInfo.store(
		current, std::memory_order_release);
	ARIPlacementGridCellBoundaryAttempted.store(
		true, std::memory_order_release);
	IMP predecessor = NULL;
	MSHookMessageEx(modelClass, selector,
		(IMP)ARIPlacementGridCellInfoReplacement, &predecessor);
	if(predecessor &&
	   predecessor != (IMP)ARIPlacementGridCellInfoReplacement) {
		ARIOriginalPlacementGridCellInfo.store(
			predecessor, std::memory_order_release);
	}

	BOOL installed = ARIPlacementGridCellBoundaryIsCurrent(modelClass) &&
		predecessor &&
		predecessor != (IMP)ARIPlacementGridCellInfoReplacement &&
		ARIPlacementImplementationComesFromImage(
			predecessor, providerImageBase);
	ARIPlacementGridCellBoundaryInstalled.store(
		installed, std::memory_order_release);
	return installed;
}

static BOOL ARIPlacementShouldBypassModelAdd(id model) {
	if(!ARIPlacementModelAddBoundaryActive.load(
			std::memory_order_acquire)) return NO;
	Method currentGridMethod = class_getInstanceMethod(
		object_getClass(model), @selector(gridSize));
	if(!currentGridMethod ||
	   method_getImplementation(currentGridMethod) !=
		(IMP)ARIPlacementGridSizeReplacement) {
		// A later grid hook would see the one-shot return. Keep this boundary
		// inert unless Atria is the outermost grid reader for the current class.
		return NO;
	}
	ARIPlacementHostPolicy policy = [NSThread isMainThread]
		? ARIPlacementPolicyForModel(model)
		: ARIPlacementHostPolicyUnknown;
	if(policy == ARIPlacementHostPolicyFloatingDock) return YES;
	if(policy == ARIPlacementHostPolicyIneligible) return YES;
	// A concrete Root, Folder, or ordinary Dock host is authoritative and must
	// retain the external provider's saved-position admission path. Unknown,
	// ambiguous, and future locations likewise fail open.
	if(policy != ARIPlacementHostPolicyUnknown) return NO;

	// During icon-state restoration there is no list view or location yet. The
	// archive representation's exact identity plus the context's current folder
	// distinguishes special lists without guessing from a transient grid size.
	// Explicit Root pages and Dock lists are pushed as pass-through barriers.
	return ARIPlacementSemanticRoleForModel(model) ==
		ARIPlacementSemanticRoleNonHome;
}

static struct SBHIconGridSize ARIPlacementGridSizeReplacement(
		id self, SEL selector) {
	ARIPlacementGridBypassScope *scope = ARIPlacementActiveGridBypassScope;
	for(; scope; scope = scope->previous) {
		if(scope->model != (__bridge void *)self) continue;
		// The newest same-model scope is a barrier. A nested pass-through add
		// must not consume an older outer call's pending one-shot value.
		if(!scope->pending) break;
		Method currentGridMethod = class_getInstanceMethod(
			object_getClass(self), selector);
		if(!currentGridMethod ||
		   method_getImplementation(currentGridMethod) !=
			   (IMP)ARIPlacementGridSizeReplacement) {
			// Revalidate at the actual consumption point. If another tweak
			// installs an outer grid hook after add admission but before its
			// first read, that unverified hook must receive the real grid.
			break;
		}
		scope->pending = NO;
		scope->consumed = YES;

		IMP implementation = ARIOriginalPlacementGridSize.load(
			std::memory_order_acquire);
		struct SBHIconGridSize size = implementation &&
			implementation != (IMP)ARIPlacementGridSizeReplacement
			? ((struct SBHIconGridSize (*)(id, SEL))implementation)(
				self, selector)
			: (struct SBHIconGridSize) { .width = 0, .height = 0 };
		// The verified external add wrapper compares only its row dimension.
		// Preserve the real width so the one-shot return disturbs the smallest
		// possible part of the private aggregate.
		size.height = (uint16_t)0x8000u;
		return size;
	}

	IMP implementation = ARIOriginalPlacementGridSize.load(
		std::memory_order_acquire);
	return implementation &&
		implementation != (IMP)ARIPlacementGridSizeReplacement
		? ((struct SBHIconGridSize (*)(id, SEL))implementation)(
			self, selector)
		: (struct SBHIconGridSize) { .width = 0, .height = 0 };
}

static BOOL ARIPlacementAddIconReplacement(id self, SEL selector,
		id icon, NSUInteger options) {
	IMP implementation = ARIOriginalPlacementAddIcon.load(
		std::memory_order_acquire);
	if(!implementation ||
	   implementation == (IMP)ARIPlacementAddIconReplacement) return NO;

	BOOL bypass = NO;
	@try {
		bypass = ARIPlacementShouldBypassModelAdd(self);
	} @catch(__unused NSException *exception) {
		bypass = NO;
	}

	ARIPlacementGridBypassScope scope = {
		.model = (__bridge void *)self,
		.pending = bypass,
		.consumed = NO,
		.previous = ARIPlacementActiveGridBypassScope,
	};
	// Always link the scope. A non-bypassing nested call is a same-model barrier
	// that prevents it from consuming an outer call's one-shot grid value.
	ARIPlacementActiveGridBypassScope = &scope;

	BOOL result = NO;
	@try {
		result = ((BOOL (*)(id, SEL, id, NSUInteger))implementation)(
			self, selector, icon, options);
	} @finally {
		ARIPlacementActiveGridBypassScope = scope.previous;
		if(scope.consumed &&
		   !ARIPlacementModelAddBlockLogged.exchange(
				true, std::memory_order_acq_rel)) {
			NSLog(@"[Atria]: isolated external placement model admission");
		}
	}
	return result;
}

static BOOL ARIPlacementInstallModelAddBoundary(
		Class modelClass, void *providerImageBase) {
	if(ARIPlacementModelAddBoundaryInstalled.load(
			std::memory_order_acquire)) return YES;
	if(ARIPlacementModelAddBoundaryAttempted.load(
			std::memory_order_acquire)) return NO;
	if(!modelClass || !providerImageBase) return NO;

	SEL addSelector = @selector(addIcon:options:);
	SEL gridSelector = @selector(gridSize);
	Method addMethod = class_getInstanceMethod(modelClass, addSelector);
	Method gridMethod = class_getInstanceMethod(modelClass, gridSelector);
	const ARIPlacementABIType addArguments[] = {
		ARIPlacementABIObject,
		ARIPlacementABIInteger
	};
	if(!ARIPlacementMethodMatches(
			addMethod, ARIPlacementABIBoolean, addArguments, 2) ||
	   !ARIPlacementMethodMatches(
			gridMethod, ARIPlacementABIGridSize, NULL, 0)) return NO;

	IMP addImplementation = method_getImplementation(addMethod);
	IMP gridImplementation = method_getImplementation(gridMethod);
	// Only an add wrapper supplied by the same image as the discovered property
	// provider is eligible. A stock/additional tweak chain that merely happens to
	// expose the same Objective-C signatures is left completely untouched.
	if(!ARIPlacementImplementationComesFromImage(
			addImplementation, providerImageBase)) return NO;
	if(!addImplementation || !gridImplementation ||
	   addImplementation == (IMP)ARIPlacementAddIconReplacement ||
	   gridImplementation == (IMP)ARIPlacementGridSizeReplacement) return NO;

	ARIOriginalPlacementAddIcon.store(
		addImplementation, std::memory_order_release);
	ARIOriginalPlacementGridSize.store(
		gridImplementation, std::memory_order_release);

	IMP gridPredecessor = NULL;
	// Once the first hook is installed, retrying could capture one of Atria's
	// own replacements as a predecessor. Mark the pair attempted before either
	// mutation; failed strict activation leaves both wrappers inert.
	ARIPlacementModelAddBoundaryAttempted.store(
		true, std::memory_order_release);
	MSHookMessageEx(modelClass, gridSelector,
		(IMP)ARIPlacementGridSizeReplacement, &gridPredecessor);
	if(gridPredecessor &&
	   gridPredecessor != (IMP)ARIPlacementGridSizeReplacement) {
		ARIOriginalPlacementGridSize.store(
			gridPredecessor, std::memory_order_release);
	}

	IMP addPredecessor = NULL;
	MSHookMessageEx(modelClass, addSelector,
		(IMP)ARIPlacementAddIconReplacement, &addPredecessor);
	if(addPredecessor &&
	   addPredecessor != (IMP)ARIPlacementAddIconReplacement) {
		ARIOriginalPlacementAddIcon.store(
			addPredecessor, std::memory_order_release);
	}

	// Revalidate the predecessor actually returned by Substrate. If another
	// tweak won a hook race, keep both installed wrappers completely inert and
	// preserve that chain rather than exposing the sentinel to an unknown image.
	Method installedGridMethod = class_getInstanceMethod(
		modelClass, gridSelector);
	Method installedAddMethod = class_getInstanceMethod(
		modelClass, addSelector);
	BOOL active = installedGridMethod && installedAddMethod &&
		method_getImplementation(installedGridMethod) ==
			(IMP)ARIPlacementGridSizeReplacement &&
		method_getImplementation(installedAddMethod) ==
			(IMP)ARIPlacementAddIconReplacement &&
		addPredecessor &&
		addPredecessor != (IMP)ARIPlacementAddIconReplacement &&
		ARIPlacementImplementationComesFromImage(
			addPredecessor, providerImageBase);
	ARIPlacementModelAddBoundaryActive.store(
		active, std::memory_order_release);
	ARIPlacementModelAddBoundaryInstalled.store(
		true, std::memory_order_release);
	if(active) ARIPlacementActivateUnarchiveBoundary();
	return YES;
}

static BOOL ARIPlacementShouldPatchReplacement(id self, SEL selector) {
	IMP implementation = ARIOriginalPlacementShouldPatch.load(
		std::memory_order_acquire);
	if(!ARIPlacementGetterInstalled.load(std::memory_order_acquire)) {
		return implementation &&
			implementation != (IMP)ARIPlacementShouldPatchReplacement
			? ((BOOL (*)(id, SEL))implementation)(self, selector)
			: YES;
	}

	ARIPlacementGridCellScope *gridScope =
		ARIPlacementActiveGridCellScope;
	if(ARIPlacementRootSuppressionActive.load(
			std::memory_order_acquire) &&
	   gridScope && gridScope->model == (__bridge void *)self &&
	   gridScope->suppress) {
		// Only the top frame is consulted. Its initial false value is a barrier
		// against an enclosing same-model grid invocation.
		if(!ARIPlacementRootSuppressionLogged.exchange(
				true, std::memory_order_acq_rel)) {
			NSLog(@"[Atria]: isolated external placement root drag remap");
		}
		return NO;
	}
	if(ARIPlacementGetterDepth > 0) {
		return implementation &&
			implementation != (IMP)ARIPlacementShouldPatchReplacement
			? ((BOOL (*)(id, SEL))implementation)(self, selector)
			: YES;
	}

	ARIPlacementGetterDepth++;
	ARIPlacementHostPolicy policy = ARIPlacementHostPolicyUnknown;
	@try {
		policy = ARIPlacementPolicyForModel(self);
	} @catch(__unused NSException *exception) {
		// Private host accessors can disappear or be replaced across releases.
		// Classification failure must never turn into a SpringBoard crash.
		policy = ARIPlacementHostPolicyUnknown;
	} @finally {
		ARIPlacementGetterDepth--;
	}
	if(policy == ARIPlacementHostPolicyFloatingDock) {
		if(!ARIPlacementBlockLogged.exchange(
				true, std::memory_order_acq_rel)) {
			NSLog(@"[Atria]: blocked external placement in Floating Dock");
		}
		return NO;
	}
	// Every non-Floating-Dock read delegates to the provider. In particular,
	// Root must retain the external tweak's requested value and call semantics.
	return implementation &&
		implementation != (IMP)ARIPlacementShouldPatchReplacement
		? ((BOOL (*)(id, SEL))implementation)(self, selector)
		: YES;
}

static BOOL ARIPlacementInstallGetterBoundary(void) {
	if(ARIPlacementGetterInstalled.load(std::memory_order_acquire))
		return YES;
	if(ARIPlacementGetterInstallAttempted.load(std::memory_order_acquire)) {
		ARIPlacementDiscoveryActive.store(false, std::memory_order_release);
		return NO;
	}

	@synchronized([ARITweakManager class]) {
		if(ARIPlacementGetterInstalled.load(std::memory_order_acquire))
			return YES;
		if(ARIPlacementGetterInstallAttempted.load(
				std::memory_order_acquire)) {
			ARIPlacementDiscoveryActive.store(
				false, std::memory_order_release);
			return NO;
		}

		Class modelClass = objc_getClass("SBIconListModel");
		SEL getterSelector = @selector(griddyShouldPatch);
		Method getter = ARIPlacementDirectInstanceMethod(modelClass, getterSelector);
		if(!ARIPlacementMethodMatches(
				getter, ARIPlacementABIBoolean, NULL, 0)) {
			return NO;
		}

		IMP getterImplementation = method_getImplementation(getter);
		if(!getterImplementation ||
		   getterImplementation ==
			   (IMP)ARIPlacementShouldPatchReplacement) {
			return NO;
		}
		Dl_info getterInfo = {};
		if(dladdr((const void *)getterImplementation, &getterInfo) == 0 ||
		   !getterInfo.dli_fbase) return NO;

		// The grid wrapper must sit immediately outside the implementation from
		// the discovered image. If that implementation is not ready yet, leave
		// discovery retryable; a post-mutation proof failure is terminal and the
		// installed wrapper remains a transparent delegate.
		BOOL gridInstalled = ARIPlacementInstallGridCellBoundary(
			modelClass, getterInfo.dli_fbase);
		if(!gridInstalled &&
		   !ARIPlacementGridCellBoundaryAttempted.load(
				std::memory_order_acquire)) return NO;

		// Publish a valid fallback before Substrate makes the replacement
		// callable. MSHookMessageEx then supplies the immediate predecessor so
		// existing hook chains and their private associated-object key survive.
		// Once Substrate is called we never attempt a second hook, even if a
		// compatibility layer exposes a dispatcher instead of our exact IMP.
		ARIPlacementGetterInstallAttempted.store(
			true, std::memory_order_release);
		ARIOriginalPlacementShouldPatch.store(
			getterImplementation, std::memory_order_release);
		IMP predecessor = NULL;
		MSHookMessageEx(modelClass, getterSelector,
			(IMP)ARIPlacementShouldPatchReplacement, &predecessor);
		if(predecessor &&
		   predecessor != (IMP)ARIPlacementShouldPatchReplacement) {
			ARIOriginalPlacementShouldPatch.store(
				predecessor, std::memory_order_release);
		}

		Method installedGetter = ARIPlacementDirectInstanceMethod(
			modelClass, getterSelector);
		BOOL getterInstalled = ARIPlacementMethodMatches(
				installedGetter, ARIPlacementABIBoolean, NULL, 0) &&
			method_getImplementation(installedGetter) ==
				(IMP)ARIPlacementShouldPatchReplacement &&
			predecessor &&
			predecessor != (IMP)ARIPlacementShouldPatchReplacement &&
			ARIPlacementImplementationComesFromImage(
				predecessor, getterInfo.dli_fbase);
		ARIPlacementGetterInstalled.store(
			getterInstalled, std::memory_order_release);
		ARIPlacementRootSuppressionActive.store(
			getterInstalled && gridInstalled &&
			ARIPlacementGridCellBoundaryIsCurrent(modelClass),
			std::memory_order_release);
		ARIPlacementDiscoveryActive.store(false, std::memory_order_release);
		if(getterInstalled) {
			ARIPlacementInstallModelAddBoundary(
				modelClass, getterInfo.dli_fbase);
			NSLog(@"[Atria]: external placement boundary active");
		}
		return getterInstalled;
	}
}

static void ARIPlacementImageAdded(
		__unused const struct mach_header *header,
		__unused intptr_t slide) {
	if(!ARIPlacementImageCallbacksReady.load(std::memory_order_acquire) ||
	   ARIPlacementGetterInstalled.load(std::memory_order_acquire) ||
	   ARIPlacementGetterInstallAttempted.load(std::memory_order_acquire)) {
		return;
	}
	ARIPlacementDiscoveryActive.store(true, std::memory_order_release);

	BOOL expected = false;
	if(!ARIPlacementImageRetryQueued.compare_exchange_strong(
			expected, true, std::memory_order_acq_rel)) {
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		ARIPlacementImageRetryQueued.store(false, std::memory_order_release);
		if(ARIPlacementGetterInstalled.load(std::memory_order_acquire))
			return;
		ARIPlacementBeginBoundedDiscovery();
	});
}

static void ARIPlacementScheduleDiscoveryAttempt(
		unsigned int generation, NSUInteger attempt) {
	dispatch_after(
		dispatch_time(DISPATCH_TIME_NOW,
			(int64_t)(ARIPlacementDiscoveryInterval * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			if(generation != ARIPlacementDiscoveryGeneration.load(
					std::memory_order_acquire)) return;
			if(ARIPlacementInstallGetterBoundary()) {
				ARIPlacementDiscoveryActive.store(
					false, std::memory_order_release);
				return;
			}
			if(ARIPlacementGetterInstallAttempted.load(
					std::memory_order_acquire)) {
				ARIPlacementDiscoveryActive.store(
					false, std::memory_order_release);
				return;
			}

			if(attempt >= ARIPlacementMaximumDiscoveryAttempts) {
				ARIPlacementDiscoveryActive.store(
					false, std::memory_order_release);
				return;
			}
			ARIPlacementScheduleDiscoveryAttempt(generation, attempt + 1);
		});
}

static void ARIPlacementBeginBoundedDiscovery(void) {
	if(ARIPlacementGetterInstalled.load(std::memory_order_acquire) ||
	   ARIPlacementGetterInstallAttempted.load(std::memory_order_acquire))
		return;
	unsigned int generation =
		ARIPlacementDiscoveryGeneration.fetch_add(
			1, std::memory_order_acq_rel) + 1;
	ARIPlacementDiscoveryActive.store(true, std::memory_order_release);
	// The first main-queue turn runs after dyld has finished the other tweak
	// constructors, closing the normal Atria-first load-order window without
	// doing unbounded image polling.
	dispatch_async(dispatch_get_main_queue(), ^{
		if(generation != ARIPlacementDiscoveryGeneration.load(
				std::memory_order_acquire)) return;
		if(ARIPlacementInstallGetterBoundary()) {
			ARIPlacementDiscoveryActive.store(
				false, std::memory_order_release);
			return;
		}
		if(ARIPlacementGetterInstallAttempted.load(
				std::memory_order_acquire)) {
			ARIPlacementDiscoveryActive.store(
				false, std::memory_order_release);
			return;
		}
		ARIPlacementScheduleDiscoveryAttempt(generation, 1);
	});
}

%group ARIFloatingDockPlacementListBoundary

%hook SBIconListView

- (void)layoutIconsIfNeeded {
	id model = ARIPlacementSafelyObserveListView(self);
	ARIPlacementHostScope scope = ARIPlacementBeginHostScope(self, model);
	@try {
		%orig;
	} @finally {
		ARIPlacementEndHostScope(scope);
	}
	ARIPlacementSafelyObserveListView(self);
}

%end


%end


%ctor {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	if(![manager isEnabled] || ![manager boolValueForKey:@"layoutEnabled"])
		return;

	Class listViewClass = objc_getClass("SBIconListView");
	Class modelClass = objc_getClass("SBIconListModel");
	// Install only when one of the known private ABIs matches exactly. These
	// wrappers remain dormant until a same-image external add boundary has also
	// been verified; the folder entry itself is the synchronous load-order retry.
	ARIPlacementInstallUnarchiveBoundaries();
	BOOL hostObservationABIValid =
		ARIPlacementMethodMatches(
			class_getInstanceMethod(listViewClass, @selector(model)),
			ARIPlacementABIObject, NULL, 0) &&
		ARIPlacementMethodMatches(
			class_getInstanceMethod(listViewClass, @selector(iconLocation)),
			ARIPlacementABIObject, NULL, 0);
	BOOL listBoundaryABIValid = hostObservationABIValid &&
		ARIPlacementMethodMatches(
			class_getInstanceMethod(
				listViewClass, @selector(layoutIconsIfNeeded)),
			ARIPlacementABIVoid, NULL, 0);

	if(listBoundaryABIValid)
		%init(ARIFloatingDockPlacementListBoundary);

	if(modelClass) {
		// Existing images are enumerated synchronously by dyld. Ignore that
		// enumeration because the normal post-constructor discovery below covers
		// it; future images get one main-queue retry after their constructors.
		_dyld_register_func_for_add_image(ARIPlacementImageAdded);
		ARIPlacementImageCallbacksReady.store(true, std::memory_order_release);
		ARIPlacementBeginBoundedDiscovery();
	}
}

//
// Moves the persistent user Dock contents back to the root folder on request
// from PreferenceLoader.  The operation deliberately runs inside SpringBoard:
// editing IconState.plist externally races the live model and Atria's cached
// icon state, while SBRootFolder's native addIcons: preserves app and folder
// objects across iOS versions.
//

#import "ARITweakManager.h"
#import "../../Shared/ARISharedConstants.h"

#import <objc/message.h>
#import <objc/runtime.h>
#include <math.h>
#include <string.h>

static BOOL ARIDockResetInProgress = NO;

static void ARIDockResetAttempt(NSString *requestID, NSUInteger attempt);
static void ARIDockResetDrainRequests(void);
static void ARIDockResetFinish(NSString *requestID,
                               NSString *result,
                               NSUInteger movedCount);
static void ARIDockResetRecordCompletion(NSString *requestID,
                                         NSString *result,
                                         NSUInteger movedCount);

static BOOL ARIDockResetValidRequestID(NSString *requestID) {
    if(![requestID isKindOfClass:[NSString class]] || requestID.length == 0 ||
       requestID.length > 64) return NO;
    return [[NSUUID alloc] initWithUUIDString:requestID] != nil;
}

static NSString *ARIDockResetRequestKey(NSString *requestID) {
    return ARIDockResetValidRequestID(requestID) ?
        [ARIDockResetRequestKeyPrefix stringByAppendingString:requestID] : nil;
}

static NSString *ARIDockResetCompletionKey(NSString *requestID) {
    return ARIDockResetValidRequestID(requestID) ?
        [ARIDockResetCompletionKeyPrefix stringByAppendingString:requestID] : nil;
}

static Method ARIDockResetMethod(id receiver, SEL selector) {
    return receiver ? class_getInstanceMethod(object_getClass(receiver), selector) : NULL;
}

static BOOL ARIDockResetMethodReturnsObject(Method method) {
    if(!method) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && (type[0] == '@' || type[0] == '#');
    free(type);
    return valid;
}

static BOOL ARIDockResetMethodReturnsVoid(Method method) {
    if(!method) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && type[0] == 'v';
    free(type);
    return valid;
}

static BOOL ARIDockResetMethodReturnsBool(Method method) {
    if(!method) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && strchr("cCB", type[0]);
    free(type);
    return valid;
}

static BOOL ARIDockResetMethodTakesObject(Method method, unsigned int index) {
    if(!method || index >= method_getNumberOfArguments(method)) return NO;
    char *type = method_copyArgumentType(method, index);
    BOOL valid = type && type[0] == '@';
    free(type);
    return valid;
}

static id ARIDockResetObject(id receiver, SEL selector) {
    Method method = ARIDockResetMethod(receiver, selector);
    if(!method || method_getNumberOfArguments(method) != 2 ||
       !ARIDockResetMethodReturnsObject(method)) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
    } @catch(__unused NSException *exception) {
        return nil;
    }
}

static BOOL ARIDockResetCanCallObjectArgument(id receiver, SEL selector) {
    Method method = ARIDockResetMethod(receiver, selector);
    return method && method_getNumberOfArguments(method) == 3 &&
           ARIDockResetMethodReturnsObject(method) &&
           ARIDockResetMethodTakesObject(method, 2);
}

static BOOL ARIDockResetCanCallVoidObjectArgument(id receiver, SEL selector) {
    Method method = ARIDockResetMethod(receiver, selector);
    return method && method_getNumberOfArguments(method) == 3 &&
           ARIDockResetMethodReturnsVoid(method) &&
           ARIDockResetMethodTakesObject(method, 2);
}

static void ARIDockResetCallVoidObjectArgument(id receiver, SEL selector, id argument) {
    ((void (*)(id, SEL, id))objc_msgSend)(receiver, selector, argument);
}

static id ARIDockResetCallObjectArgument(id receiver, SEL selector, id argument) {
    return ((id (*)(id, SEL, id))objc_msgSend)(receiver, selector, argument);
}

static BOOL ARIDockResetCanCallVoid(id receiver, SEL selector) {
    Method method = ARIDockResetMethod(receiver, selector);
    return method && method_getNumberOfArguments(method) == 2 &&
           ARIDockResetMethodReturnsVoid(method);
}

static void ARIDockResetCallVoid(id receiver, SEL selector) {
    ((void (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static BOOL ARIDockResetCanCallBool(id receiver, SEL selector) {
    Method method = ARIDockResetMethod(receiver, selector);
    return method && method_getNumberOfArguments(method) == 2 &&
           ARIDockResetMethodReturnsBool(method);
}

static BOOL ARIDockResetCallBool(id receiver, SEL selector) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static NSString *ARIDockResetStableIdentifier(id icon) {
    for(NSString *selectorName in @[
        @"uniqueIdentifier", @"applicationBundleID", @"bundleIdentifier", @"leafIdentifier"
    ]) {
        id value = ARIDockResetObject(icon, NSSelectorFromString(selectorName));
        if([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }

    id application = ARIDockResetObject(icon, @selector(application));
    for(NSString *selectorName in @[@"bundleIdentifier", @"bundleIdentifierForSystemPlaceholder"]) {
        id value = ARIDockResetObject(application, NSSelectorFromString(selectorName));
        if([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    return nil;
}

static NSDictionary<NSString *, NSNumber *> *ARIDockResetIdentifierCounts(NSArray *icons) {
    if(![icons isKindOfClass:[NSArray class]]) return nil;
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for(id icon in icons) {
        NSString *identifier = ARIDockResetStableIdentifier(icon);
        if(identifier.length == 0) return nil;
        counts[identifier] = @([counts[identifier] unsignedIntegerValue] + 1);
    }
    return counts;
}

static NSArray<NSString *> *ARIDockResetOrderedIdentifiers(NSArray *icons) {
    if(![icons isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray<NSString *> *identifiers = [NSMutableArray arrayWithCapacity:icons.count];
    for(id icon in icons) {
        NSString *identifier = ARIDockResetStableIdentifier(icon);
        if(identifier.length == 0) return nil;
        [identifiers addObject:identifier];
    }
    return identifiers;
}

static BOOL ARIDockResetContainsObjectsByIdentity(NSArray *haystack, NSArray *needles) {
    if(![haystack isKindOfClass:[NSArray class]] || ![needles isKindOfClass:[NSArray class]]) return NO;
    for(id needle in needles) {
        BOOL found = NO;
        for(id candidate in haystack) {
            if(candidate == needle) {
                found = YES;
                break;
            }
        }
        if(!found) return NO;
    }
    return YES;
}

static BOOL ARIDockResetObjectArraysEqualByIdentity(NSArray *left, NSArray *right) {
    if(![left isKindOfClass:[NSArray class]] ||
       ![right isKindOfClass:[NSArray class]] ||
       left.count != right.count) return NO;
    for(NSUInteger index = 0; index < left.count; index++) {
        if(left[index] != right[index]) return NO;
    }
    return YES;
}

static BOOL ARIDockResetRootListsContainObjectsExactlyOnce(id rootFolder,
                                                            NSArray *objects) {
    NSArray *lists = ARIDockResetObject(rootFolder, NSSelectorFromString(@"lists"));
    if(![lists isKindOfClass:[NSArray class]] ||
       ![objects isKindOfClass:[NSArray class]]) return NO;

    for(id object in objects) {
        NSUInteger occurrences = 0;
        for(id list in lists) {
            NSArray *icons = ARIDockResetObject(list, @selector(icons));
            if(![icons isKindOfClass:[NSArray class]]) return NO;
            for(id icon in icons) {
                if(icon == object) occurrences++;
            }
        }
        if(occurrences != 1) return NO;
    }
    return YES;
}

static id ARIDockResetListFixedLocations(id list) {
    SEL allowsSelector = NSSelectorFromString(@"allowsFixedIconLocations");
    SEL locationsSelector = NSSelectorFromString(@"fixedIconLocations");
    Method allowsMethod = ARIDockResetMethod(list, allowsSelector);
    Method locationsMethod = ARIDockResetMethod(list, locationsSelector);
    // iOS 15 predates fixed-location lists and exposes neither selector.
    if(!allowsMethod && !locationsMethod) return NSNull.null;
    if(!ARIDockResetCanCallBool(list, allowsSelector)) return nil;
    if(!ARIDockResetCallBool(list, allowsSelector)) return NSNull.null;
    id locations = ARIDockResetObject(list, locationsSelector);
    if(![locations conformsToProtocol:@protocol(NSCopying)] ||
       ![locations respondsToSelector:@selector(isEqual:)]) return nil;
    @try {
        return [locations copy];
    } @catch(__unused NSException *exception) {
        return nil;
    }
}

static id ARIDockResetOptionalMetadata(id list, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    Method method = ARIDockResetMethod(list, selector);
    if(!method) return NSNull.null;
    if(method_getNumberOfArguments(method) != 2 ||
       !ARIDockResetMethodReturnsObject(method)) return nil;
    id value = ARIDockResetObject(list, selector);
    if(!value) return NSNull.null;
    if(![value conformsToProtocol:@protocol(NSCopying)] ||
       ![value respondsToSelector:@selector(isEqual:)]) return nil;
    @try {
        return [value copy];
    } @catch(__unused NSException *exception) {
        return nil;
    }
}

static NSArray<NSDictionary *> *ARIDockResetRootListFingerprint(id rootFolder) {
    NSArray *lists = ARIDockResetObject(rootFolder, NSSelectorFromString(@"lists"));
    if(![lists isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray<NSDictionary *> *fingerprint = [NSMutableArray arrayWithCapacity:lists.count];
    NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet set];
    for(id list in lists) {
        NSString *identifier = ARIDockResetObject(list,
            NSSelectorFromString(@"uniqueIdentifier"));
        NSArray *icons = ARIDockResetObject(list, @selector(icons));
        NSArray *ordered = ARIDockResetOrderedIdentifiers(icons);
        id fixedLocations = ARIDockResetListFixedLocations(list);
        id focusModes = ARIDockResetOptionalMetadata(list, @"focusModeIdentifiers");
        id hiddenDate = ARIDockResetOptionalMetadata(list, @"hiddenDate");
        id hiddenValue = NSNull.null;
        SEL hiddenSelector = NSSelectorFromString(@"isHidden");
        Method hiddenMethod = ARIDockResetMethod(list, hiddenSelector);
        if(hiddenMethod) {
            if(!ARIDockResetCanCallBool(list, hiddenSelector)) return nil;
            hiddenValue = @(ARIDockResetCallBool(list, hiddenSelector));
        }
        if(![identifier isKindOfClass:[NSString class]] || identifier.length == 0 ||
           !ordered || !fixedLocations || !focusModes || !hiddenDate ||
           [seenIdentifiers containsObject:identifier]) return nil;
        [seenIdentifiers addObject:identifier];
        [fingerprint addObject:@{
            @"id": identifier,
            @"icons": ordered,
            @"fixedLocations": fixedLocations,
            @"focusModeIdentifiers": focusModes,
            @"hiddenDate": hiddenDate,
            @"isHidden": hiddenValue
        }];
    }
    return fingerprint;
}

static NSArray<NSDictionary *> *ARIDockResetRootListSnapshots(id rootFolder) {
    NSArray *lists = ARIDockResetObject(rootFolder, NSSelectorFromString(@"lists"));
    if(![lists isKindOfClass:[NSArray class]]) return nil;

    NSMutableArray<NSDictionary *> *snapshots =
        [NSMutableArray arrayWithCapacity:lists.count];
    NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet set];
    for(id list in lists) {
        NSString *identifier = ARIDockResetObject(
            list, NSSelectorFromString(@"uniqueIdentifier"));
        NSArray *icons = [ARIDockResetObject(list, @selector(icons)) copy];
        id fixedLocations = ARIDockResetListFixedLocations(list);
        if(![identifier isKindOfClass:[NSString class]] || identifier.length == 0 ||
           [seenIdentifiers containsObject:identifier] ||
           ![icons isKindOfClass:[NSArray class]] || !fixedLocations ||
           !ARIDockResetCanCallVoidObjectArgument(
               list, NSSelectorFromString(@"setIcons:"))) return nil;
        if(fixedLocations != NSNull.null &&
           !ARIDockResetCanCallVoidObjectArgument(
               list, NSSelectorFromString(@"setFixedIconLocations:"))) return nil;
        for(NSDictionary *snapshot in snapshots) {
            if(snapshot[@"list"] == list) return nil;
        }
        [seenIdentifiers addObject:identifier];
        [snapshots addObject:@{
            @"list": list,
            @"id": identifier,
            @"icons": icons,
            @"fixedLocations": fixedLocations
        }];
    }
    return snapshots;
}

static BOOL ARIDockResetRootListsMatchSnapshotsByIdentity(
    id rootFolder,
    NSArray<NSDictionary *> *snapshots) {
    NSArray *lists = ARIDockResetObject(rootFolder, NSSelectorFromString(@"lists"));
    if(![lists isKindOfClass:[NSArray class]] ||
       ![snapshots isKindOfClass:[NSArray class]] ||
       lists.count != snapshots.count) return NO;
    for(NSUInteger index = 0; index < snapshots.count; index++) {
        NSDictionary *snapshot = snapshots[index];
        id list = snapshot[@"list"];
        NSArray *expectedIcons = snapshot[@"icons"];
        NSArray *actualIcons = ARIDockResetObject(list, @selector(icons));
        if(lists[index] != list ||
           !ARIDockResetObjectArraysEqualByIdentity(actualIcons, expectedIcons)) return NO;
    }
    return YES;
}

static BOOL ARIDockResetRootListsPreservePrefix(
    NSArray<NSDictionary *> *before,
    NSArray<NSDictionary *> *after) {
    if(!before || !after) return NO;
    if(after.count < before.count) return NO;
    for(NSUInteger index = 0; index < before.count; index++) {
        NSDictionary *oldList = before[index];
        NSDictionary *newList = after[index];
        if(![oldList[@"id"] isEqual:newList[@"id"]] ||
           ![oldList[@"focusModeIdentifiers"] isEqual:newList[@"focusModeIdentifiers"]] ||
           ![oldList[@"hiddenDate"] isEqual:newList[@"hiddenDate"]] ||
           ![oldList[@"isHidden"] isEqual:newList[@"isHidden"]]) return NO;
        NSArray<NSString *> *oldIcons = oldList[@"icons"];
        NSArray<NSString *> *newIcons = newList[@"icons"];
        if(!newIcons || newIcons.count < oldIcons.count) return NO;
        if(![[newIcons subarrayWithRange:NSMakeRange(0, oldIcons.count)] isEqualToArray:oldIcons])
            return NO;

        id oldLocations = oldList[@"fixedLocations"];
        id newLocations = newList[@"fixedLocations"];
        if(oldLocations == NSNull.null) {
            if(newLocations != NSNull.null) return NO;
        } else if(![oldLocations isKindOfClass:[NSDictionary class]] ||
                  ![newLocations isKindOfClass:[NSDictionary class]]) {
            // Unknown fixed-location containers fail closed rather than
            // claiming that existing free-placement coordinates survived.
            return NO;
        } else {
            for(id key in (NSDictionary *)oldLocations) {
                if(![((NSDictionary *)oldLocations)[key]
                    isEqual:((NSDictionary *)newLocations)[key]]) return NO;
            }
        }
    }
    return YES;
}

static BOOL ARIDockResetRootListsEqual(
    NSArray<NSDictionary *> *left,
    NSArray<NSDictionary *> *right) {
    return left && right && [left isEqualToArray:right];
}

static NSDictionary *ARIDockResetFolderFingerprint(id icon) {
    id folder = ARIDockResetObject(icon, NSSelectorFromString(@"folder"));
    if(!folder) return nil;

    NSString *uniqueIdentifier = ARIDockResetObject(folder,
        NSSelectorFromString(@"uniqueIdentifier"));
    NSString *displayName = ARIDockResetObject(folder,
        NSSelectorFromString(@"displayName"));
    NSString *defaultDisplayName = ARIDockResetObject(folder,
        NSSelectorFromString(@"defaultDisplayName"));
    NSArray *lists = ARIDockResetObject(folder, NSSelectorFromString(@"lists"));
    NSArray *children = ARIDockResetObject(folder, NSSelectorFromString(@"icons"));
    if(![uniqueIdentifier isKindOfClass:[NSString class]] || uniqueIdentifier.length == 0 ||
       ![children isKindOfClass:[NSArray class]]) return nil;

    NSMutableArray *listFingerprints = [NSMutableArray array];
    if([lists isKindOfClass:[NSArray class]]) {
        for(id list in lists) {
            NSString *listIdentifier = ARIDockResetObject(list,
                NSSelectorFromString(@"uniqueIdentifier"));
            NSArray *listIcons = ARIDockResetObject(list, @selector(icons));
            NSArray *listIdentifiers = ARIDockResetOrderedIdentifiers(listIcons);
            id fixedLocations = ARIDockResetListFixedLocations(list);
            if(![listIdentifier isKindOfClass:[NSString class]] || listIdentifier.length == 0 ||
               !listIdentifiers || !fixedLocations) return nil;
            [listFingerprints addObject:@{
                @"id": listIdentifier,
                @"icons": listIdentifiers,
                @"fixedLocations": fixedLocations
            }];
        }
    }

    NSDictionary *childCounts = ARIDockResetIdentifierCounts(children);
    NSArray *orderedChildren = ARIDockResetOrderedIdentifiers(children);
    if(!childCounts || !orderedChildren) return nil;
    return @{
        @"id": uniqueIdentifier,
        @"displayName": [displayName isKindOfClass:[NSString class]] ? displayName : NSNull.null,
        @"defaultDisplayName": [defaultDisplayName isKindOfClass:[NSString class]] ? defaultDisplayName : NSNull.null,
        @"children": childCounts,
        @"orderedChildren": orderedChildren,
        @"lists": listFingerprints
    };
}

static NSDictionary<NSString *, NSDictionary *> *ARIDockResetFolderFingerprints(NSArray *icons) {
    NSMutableDictionary<NSString *, NSDictionary *> *fingerprints = [NSMutableDictionary dictionary];
    for(id icon in icons ?: @[]) {
        id folder = ARIDockResetObject(icon, NSSelectorFromString(@"folder"));
        if(!folder) continue;
        NSDictionary *fingerprint = ARIDockResetFolderFingerprint(icon);
        if(!fingerprint) return nil;
        NSString *identifier = fingerprint[@"id"];
        if(fingerprints[identifier]) return nil;
        fingerprints[identifier] = fingerprint;
    }
    return fingerprints;
}

static BOOL ARIDockResetFoldersMatchSnapshot(NSArray *icons,
                                              NSDictionary<NSString *, NSDictionary *> *expected) {
    if(!expected) return NO;
    NSDictionary *actual = ARIDockResetFolderFingerprints(icons);
    if(!actual) return NO;
    for(NSString *identifier in expected) {
        if(![actual[identifier] isEqual:expected[identifier]]) return NO;
    }
    return YES;
}

static BOOL ARIDockResetMovedStateIsValid(
    id rootFolder,
    id dockModel,
    NSArray *dockIcons,
    NSDictionary *rootCountsBefore,
    NSArray<NSDictionary *> *rootListsBefore,
    NSDictionary<NSString *, NSDictionary *> *dockFoldersBefore) {
    NSArray *dockIconsAfter = ARIDockResetObject(dockModel, @selector(icons));
    NSArray *rootIconsAfter = ARIDockResetObject(rootFolder, @selector(icons));
    NSDictionary *rootCountsAfter = ARIDockResetIdentifierCounts(rootIconsAfter);
    NSArray *rootListsAfter = ARIDockResetRootListFingerprint(rootFolder);
    return [dockIconsAfter isKindOfClass:[NSArray class]] &&
           dockIconsAfter.count == 0 && rootCountsAfter &&
           [rootCountsAfter isEqualToDictionary:rootCountsBefore] &&
           ARIDockResetRootListsPreservePrefix(rootListsBefore, rootListsAfter) &&
           ARIDockResetRootListsContainObjectsExactlyOnce(rootFolder, dockIcons) &&
           ARIDockResetFoldersMatchSnapshot(rootIconsAfter, dockFoldersBefore);
}

static void ARIDockResetRestoreFolderMetadata(
    NSArray *icons,
    NSDictionary<NSString *, NSDictionary *> *expected) {
    if(!expected) return;
    for(id icon in icons ?: @[]) {
        id folder = ARIDockResetObject(icon, NSSelectorFromString(@"folder"));
        NSString *identifier = ARIDockResetObject(folder,
            NSSelectorFromString(@"uniqueIdentifier"));
        NSDictionary *fingerprint = identifier.length > 0 ? expected[identifier] : nil;
        if(!fingerprint) continue;

        for(NSString *key in @[@"defaultDisplayName", @"displayName"]) {
            NSString *value = fingerprint[key];
            if(![value isKindOfClass:[NSString class]]) continue;
            SEL setter = NSSelectorFromString([NSString stringWithFormat:
                @"set%@%@:", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]]);
            Method method = ARIDockResetMethod(folder, setter);
            if(!method ||
               method_getNumberOfArguments(method) != 3 ||
               !ARIDockResetMethodReturnsVoid(method) ||
               !ARIDockResetMethodTakesObject(method, 2)) continue;
            ((void (*)(id, SEL, id))objc_msgSend)(folder, setter, value);
        }
    }
}

static id ARIDockResetIconController(void) {
    Class controllerClass = objc_getClass("SBIconController");
    id controller = ARIDockResetObject(controllerClass,
                                       NSSelectorFromString(@"sharedInstanceIfExists"));
    return controller ?: ARIDockResetObject(controllerClass, @selector(sharedInstance));
}

static void ARIDockResetClearCachedIconState(ARITweakManager *manager) {
    // The live SpringBoard hierarchy is authoritative after a reset. Retaining
    // an older Atria snapshot could repopulate the Dock when the tweak or its
    // layout feature is enabled again.
    [manager.preferences removeObjectForKey:@"_saveState"];
    [manager.preferences removeObjectForKey:@"_saveStateOSVersion"];
    [manager.preferences removeObjectForKey:@"_saveStateSchemaVersion"];
    [manager.preferences synchronize];
}

static BOOL ARIDockResetRollback(
    id iconModel,
    id dockModel,
    id rootFolder,
    NSArray *dockIcons,
    NSDictionary *rootCountsBefore,
    NSDictionary *dockCountsBefore,
    NSDictionary<NSString *, NSDictionary *> *dockFoldersBefore,
    NSArray<NSDictionary *> *rootListsBefore,
    NSArray<NSDictionary *> *rootListSnapshotsBefore) {
    @try {
        NSArray *currentDockIcons = ARIDockResetObject(dockModel, @selector(icons));
        NSArray *currentRootLists = ARIDockResetObject(
            rootFolder, NSSelectorFromString(@"lists"));
        if(![currentDockIcons isKindOfClass:[NSArray class]]) @throw [NSException
            exceptionWithName:@"ARIDockResetRollbackState"
                       reason:@"Dock icon state unavailable during rollback"
                     userInfo:nil];
        if(![currentRootLists isKindOfClass:[NSArray class]] ||
           ![rootListSnapshotsBefore isKindOfClass:[NSArray class]] ||
           currentRootLists.count < rootListSnapshotsBefore.count) return NO;

        // Preflight the complete concrete-list transaction before changing
        // anything. Original lists must remain the exact prefix by object
        // identity. Any appended list may only contain objects offered by this
        // reset; otherwise it could be a concurrent/system-owned page and is
        // never removed by this recovery path.
        for(NSUInteger index = 0; index < currentRootLists.count; index++) {
            id list = currentRootLists[index];
            if(!ARIDockResetCanCallVoidObjectArgument(
                   list, NSSelectorFromString(@"setIcons:"))) return NO;
            if(index < rootListSnapshotsBefore.count) {
                NSDictionary *snapshot = rootListSnapshotsBefore[index];
                if(snapshot[@"list"] != list ||
                   ![snapshot[@"id"] isEqual:ARIDockResetObject(
                       list, NSSelectorFromString(@"uniqueIdentifier"))]) return NO;
                id fixedLocations = snapshot[@"fixedLocations"];
                if(fixedLocations != NSNull.null &&
                   !ARIDockResetCanCallVoidObjectArgument(
                       list, NSSelectorFromString(@"setFixedIconLocations:"))) return NO;
                continue;
            }

            NSArray *extraIcons = ARIDockResetObject(list, @selector(icons));
            if(![extraIcons isKindOfClass:[NSArray class]] ||
               extraIcons.count == 0 ||
               !ARIDockResetContainsObjectsByIdentity(dockIcons, extraIcons)) return NO;
        }
        BOOL hasAppendedLists = currentRootLists.count > rootListSnapshotsBefore.count;
        NSArray *appendedRootLists = hasAppendedLists ? [currentRootLists
            subarrayWithRange:NSMakeRange(
                rootListSnapshotsBefore.count,
                currentRootLists.count - rootListSnapshotsBefore.count)] : @[];
        SEL removeList = NSSelectorFromString(@"removeList:");
        if(hasAppendedLists &&
           !ARIDockResetCanCallVoidObjectArgument(rootFolder, removeList)) return NO;

        NSMutableArray *missingDockIcons = [NSMutableArray array];
        for(id originalIcon in dockIcons) {
            BOOL present = NO;
            for(id currentIcon in currentDockIcons) {
                if(currentIcon == originalIcon) {
                    present = YES;
                    break;
                }
            }
            if(!present) [missingDockIcons addObject:originalIcon];
        }
        if(missingDockIcons.count > 0) {
            id rejectedIcons = ARIDockResetCallObjectArgument(
                dockModel, NSSelectorFromString(@"addIcons:"), missingDockIcons);
            if(rejectedIcons &&
               (![rejectedIcons isKindOfClass:[NSArray class]] ||
                [rejectedIcons count] > 0)) return NO;
        }

        // addIcons: is hierarchy-aware, but on iOS 15 a partially accepted
        // root add can leave a deferred containment mutation that only appears
        // after SpringBoard restarts. Reapply every concrete original page's
        // exact object array so SBFolder receives matching remove/add callbacks.
        // Restore fixed-location metadata after setIcons: because that setter
        // can normalize location records on newer releases.
        for(NSDictionary *snapshot in rootListSnapshotsBefore) {
            id list = snapshot[@"list"];
            ARIDockResetCallVoidObjectArgument(
                list, NSSelectorFromString(@"setIcons:"), snapshot[@"icons"]);
            id fixedLocations = snapshot[@"fixedLocations"];
            if(fixedLocations != NSNull.null)
                ARIDockResetCallVoidObjectArgument(
                    list, NSSelectorFromString(@"setFixedIconLocations:"),
                    fixedLocations);
        }

        // Root addIcons: can append a page at capacity. Only lists proven above
        // to be trailing, newly-created containers of offered Dock objects are
        // eligible for removal, and only through an ABI-validated selector.
        currentRootLists = ARIDockResetObject(
            rootFolder, NSSelectorFromString(@"lists"));
        if(![currentRootLists isKindOfClass:[NSArray class]] ||
           currentRootLists.count < rootListSnapshotsBefore.count) return NO;
        for(NSUInteger index = currentRootLists.count;
            index > rootListSnapshotsBefore.count; index--) {
            id extraList = currentRootLists[index - 1];
            NSUInteger appendedIndex = index - rootListSnapshotsBefore.count - 1;
            if(appendedIndex >= appendedRootLists.count ||
               appendedRootLists[appendedIndex] != extraList) return NO;
            NSArray *extraIcons = ARIDockResetObject(extraList, @selector(icons));
            if(![extraIcons isKindOfClass:[NSArray class]] ||
               !ARIDockResetContainsObjectsByIdentity(dockIcons, extraIcons)) return NO;
            ARIDockResetCallVoidObjectArgument(
                extraList, NSSelectorFromString(@"setIcons:"), @[]);
            ARIDockResetCallVoidObjectArgument(rootFolder, removeList, extraList);
            currentRootLists = ARIDockResetObject(
                rootFolder, NSSelectorFromString(@"lists"));
            if(![currentRootLists isKindOfClass:[NSArray class]] ||
               currentRootLists.count != index - 1) return NO;
        }

        ARIDockResetCallVoidObjectArgument(
            dockModel, NSSelectorFromString(@"setIcons:"), dockIcons);
        ARIDockResetRestoreFolderMetadata(dockIcons, dockFoldersBefore);
        ARIDockResetCallVoid(iconModel, @selector(layoutIfNeeded));
        NSArray *restoredDockIcons = ARIDockResetObject(dockModel, @selector(icons));
        NSArray *restoredRootIcons = ARIDockResetObject(rootFolder, @selector(icons));
        NSDictionary *restoredRootCounts = ARIDockResetIdentifierCounts(restoredRootIcons);
        NSDictionary *restoredDockCounts = ARIDockResetIdentifierCounts(restoredDockIcons);
        NSArray *restoredRootLists = ARIDockResetRootListFingerprint(rootFolder);
        NSArray *restoredDockOrder = ARIDockResetOrderedIdentifiers(restoredDockIcons);
        NSArray *originalDockOrder = ARIDockResetOrderedIdentifiers(dockIcons);
        BOOL restored = restoredRootCounts && restoredDockCounts &&
            [restoredRootCounts isEqualToDictionary:rootCountsBefore] &&
            [restoredDockCounts isEqualToDictionary:dockCountsBefore] &&
            ARIDockResetRootListsEqual(restoredRootLists, rootListsBefore) &&
            [restoredDockOrder isEqualToArray:originalDockOrder] &&
            ARIDockResetContainsObjectsByIdentity(restoredDockIcons, dockIcons) &&
            ARIDockResetRootListsMatchSnapshotsByIdentity(
                rootFolder, rootListSnapshotsBefore) &&
            ARIDockResetFoldersMatchSnapshot(restoredDockIcons, dockFoldersBefore);
        BOOL rollbackSucceeded = restored && ARIDockResetCallBool(
            iconModel, NSSelectorFromString(@"saveIconStateIfNeeded"));
        return rollbackSucceeded;
    } @catch(__unused NSException *exception) {
        return NO;
    }
}

static BOOL ARIDockResetRollbackStateIsValid(
    id dockModel,
    id rootFolder,
    NSArray *dockIcons,
    NSDictionary *rootCountsBefore,
    NSDictionary *dockCountsBefore,
    NSDictionary<NSString *, NSDictionary *> *dockFoldersBefore,
    NSArray<NSDictionary *> *rootListsBefore,
    NSArray<NSDictionary *> *rootListSnapshotsBefore) {
    NSArray *restoredDockIcons = ARIDockResetObject(dockModel, @selector(icons));
    NSArray *restoredRootIcons = ARIDockResetObject(rootFolder, @selector(icons));
    NSDictionary *restoredRootCounts = ARIDockResetIdentifierCounts(restoredRootIcons);
    NSDictionary *restoredDockCounts = ARIDockResetIdentifierCounts(restoredDockIcons);
    NSArray *restoredRootLists = ARIDockResetRootListFingerprint(rootFolder);
    NSArray *restoredDockOrder = ARIDockResetOrderedIdentifiers(restoredDockIcons);
    NSArray *originalDockOrder = ARIDockResetOrderedIdentifiers(dockIcons);
    return restoredRootCounts && restoredDockCounts &&
           [restoredRootCounts isEqualToDictionary:rootCountsBefore] &&
           [restoredDockCounts isEqualToDictionary:dockCountsBefore] &&
           ARIDockResetRootListsEqual(restoredRootLists, rootListsBefore) &&
           [restoredDockOrder isEqualToArray:originalDockOrder] &&
           ARIDockResetContainsObjectsByIdentity(restoredDockIcons, dockIcons) &&
           ARIDockResetRootListsMatchSnapshotsByIdentity(
               rootFolder, rootListSnapshotsBefore) &&
           ARIDockResetFoldersMatchSnapshot(restoredDockIcons, dockFoldersBefore);
}

static void ARIDockResetFinishAfterRollback(
    NSString *requestID,
    NSString *failureResult,
    id iconModel,
    id dockModel,
    id rootFolder,
    NSArray *dockIcons,
    NSDictionary *rootCountsBefore,
    NSDictionary *dockCountsBefore,
    NSDictionary<NSString *, NSDictionary *> *dockFoldersBefore,
    NSArray<NSDictionary *> *rootListsBefore,
    NSArray<NSDictionary *> *rootListSnapshotsBefore) {
    BOOL rollbackSaved = ARIDockResetRollback(
        iconModel, dockModel, rootFolder, dockIcons, rootCountsBefore,
        dockCountsBefore, dockFoldersBefore, rootListsBefore,
        rootListSnapshotsBefore);
    if(!rollbackSaved) {
        ARIDockResetFinish(requestID, @"rollbackFailed", 0);
        return;
    }

    // A successful save is not enough: Atria's hooks and SpringBoard's list
    // maintenance can run later in the same main-loop iteration. Observe the
    // concrete page lists and Dock again on the next turn before reporting that
    // the transaction was rolled back. This phase is deliberately read-only;
    // another layout or save could reapply the failed intermediate arrangement.
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL settled = NO;
        @try {
            settled = ARIDockResetRollbackStateIsValid(
                dockModel, rootFolder, dockIcons, rootCountsBefore,
                dockCountsBefore, dockFoldersBefore, rootListsBefore,
                rootListSnapshotsBefore);
        } @catch(__unused NSException *exception) {
            settled = NO;
        }
        ARIDockResetFinish(
            requestID, settled ? failureResult : @"rollbackFailed", 0);
    });
}

static void ARIDockResetRecordCompletion(NSString *requestID,
                                         NSString *result,
                                         NSUInteger movedCount) {
    if(!ARIDockResetValidRequestID(requestID)) return;
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    NSString *terminalResult = result ?: @"validationFailed";
    NSDictionary *request = [preferences dictionaryForKey:ARIDockResetRequestKey(requestID)];
    NSNumber *requestTimestamp = [request[ARIDockResetRequestTimestampField]
        isKindOfClass:[NSNumber class]] ? request[ARIDockResetRequestTimestampField] : @0;
    NSDictionary *completion = @{
        ARIDockResetCompletionRequestIDField: requestID,
        ARIDockResetCompletionResultField: terminalResult,
        ARIDockResetCompletionMovedCountField: @(movedCount),
        ARIDockResetCompletionRequestTimestampField: requestTimestamp,
        ARIDockResetCompletionLegacyScalarField: @NO,
        ARIDockResetCompletionTimestampField: @(NSDate.date.timeIntervalSince1970)
    };
    [preferences setObject:completion forKey:ARIDockResetCompletionKey(requestID)];

    // The immediately preceding Preferences build reads exact UUID entries
    // from this map. SpringBoard is its only writer, and all completions are
    // serialized on the main thread, so this compatibility RMW cannot lose a
    // concurrent client request.
    NSMutableDictionary *legacyCompletions = [[preferences
        dictionaryForKey:@"_dockResetCompletions"] mutableCopy] ?:
        [NSMutableDictionary dictionary];
    legacyCompletions[requestID] = completion;
    if(legacyCompletions.count > 32) {
        NSArray<NSString *> *keysByAge = [legacyCompletions.allKeys
            sortedArrayUsingComparator:^NSComparisonResult(NSString *leftKey,
                                                             NSString *rightKey) {
                NSDictionary *left = [legacyCompletions[leftKey]
                    isKindOfClass:[NSDictionary class]] ? legacyCompletions[leftKey] : @{};
                NSDictionary *right = [legacyCompletions[rightKey]
                    isKindOfClass:[NSDictionary class]] ? legacyCompletions[rightKey] : @{};
                NSNumber *leftValue = [left[ARIDockResetCompletionTimestampField]
                    isKindOfClass:[NSNumber class]] ?
                    left[ARIDockResetCompletionTimestampField] : nil;
                NSNumber *rightValue = [right[ARIDockResetCompletionTimestampField]
                    isKindOfClass:[NSNumber class]] ?
                    right[ARIDockResetCompletionTimestampField] : nil;
                double leftTime = leftValue.doubleValue;
                double rightTime = rightValue.doubleValue;
                if(!isfinite(leftTime)) leftTime = 0;
                if(!isfinite(rightTime)) rightTime = 0;
                if(leftTime < rightTime) return NSOrderedAscending;
                if(leftTime > rightTime) return NSOrderedDescending;
                return [leftKey compare:rightKey];
            }];
        NSUInteger removeCount = legacyCompletions.count - 32;
        for(NSUInteger index = 0; index < removeCount; index++)
            [legacyCompletions removeObjectForKey:keysByAge[index]];
    }
    [preferences setObject:legacyCompletions forKey:@"_dockResetCompletions"];

    // Compatibility for a PreferenceLoader process that was already hosting
    // the previous bundle while this SpringBoard binary was installed.
    // Publish the ID only after the scalar payload is durable, so an older
    // polling client can never combine one request ID with another result.
    [preferences removeObjectForKey:ARIDockResetCompletedIDKey];
    [preferences synchronize];
    [preferences setObject:terminalResult forKey:ARIDockResetResultKey];
    [preferences setInteger:(NSInteger)movedCount forKey:ARIDockResetMovedCountKey];
    [preferences synchronize];
    [preferences setObject:requestID forKey:ARIDockResetCompletedIDKey];
    [preferences removeObjectForKey:ARIDockResetRequestKey(requestID)];
    [preferences synchronize];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)ARIDockResetCompletionNotification,
        NULL,
        NULL,
        true
    );
}

static void ARIDockResetFinish(NSString *requestID,
                               NSString *result,
                               NSUInteger movedCount) {
    ARIDockResetRecordCompletion(requestID, result, movedCount);
    ARIDockResetInProgress = NO;
    // A second Preferences process may have posted while this request was in
    // flight. Scan the durable per-request keys instead of trusting Darwin
    // notification delivery/coalescing.
    dispatch_async(dispatch_get_main_queue(), ^{
        ARIDockResetDrainRequests();
    });
}

static void ARIDockResetAttempt(NSString *requestID, NSUInteger attempt) {
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    [preferences synchronize];
    NSDictionary *request = [preferences dictionaryForKey:ARIDockResetRequestKey(requestID)];
    if(!request) {
        ARIDockResetFinish(requestID, @"expired", 0);
        return;
    }
    NSNumber *deadlineValue = [request[ARIDockResetRequestDeadlineField]
        isKindOfClass:[NSNumber class]] ? request[ARIDockResetRequestDeadlineField] : nil;
    NSTimeInterval deadline = deadlineValue.doubleValue;
    if(!deadlineValue || !isfinite(deadline) || deadline <= 0) {
        ARIDockResetFinish(requestID, @"validationFailed", 0);
        return;
    }
    if(deadline > 0 && NSDate.date.timeIntervalSince1970 > deadline) {
        ARIDockResetFinish(requestID, @"expired", 0);
        return;
    }

    ARITweakManager *manager = [ARITweakManager sharedInstance];
    id iconController = ARIDockResetIconController();
    id iconManager = ARIDockResetObject(iconController, @selector(iconManager));
    id iconModel = ARIDockResetObject(iconManager, @selector(iconModel));
    SBIconListView *dockListView = [manager userDockListView];
    if(!dockListView) {
        id effectiveDock = ARIDockResetObject(iconManager,
            NSSelectorFromString(@"effectiveDockListView"));
        Class listViewClass = objc_getClass("SBIconListView");
        NSString *effectiveLocation = ARIDockResetObject(effectiveDock,
            @selector(iconLocation));
        BOOL exactDockLocation = [effectiveLocation isEqualToString:@"SBIconLocationDock"] ||
            [effectiveLocation isEqualToString:@"SBIconLocationFloatingDock"];
        if(listViewClass && [effectiveDock isKindOfClass:listViewClass] &&
           exactDockLocation) {
            dockListView = effectiveDock;
            [manager registerPersistentUserDockListView:dockListView];
        }
    }
    id dockModel = ARIDockResetObject(dockListView, @selector(model));
    NSString *location = ARIDockResetObject(dockListView, @selector(iconLocation));

    BOOL editing = [iconManager respondsToSelector:@selector(isEditing)] &&
                   [iconManager isEditing];
    SEL isIconDragging = NSSelectorFromString(@"isIconDragging");
    BOOL dragging = ARIDockResetCanCallBool(iconManager, isIconDragging) &&
                    ARIDockResetCallBool(iconManager, isIconDragging);
    if(editing || dragging) {
        if(attempt < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                ARIDockResetAttempt(requestID, attempt + 1);
            });
        } else {
            ARIDockResetFinish(requestID, @"busy", 0);
        }
        return;
    }

    Class listViewClass = objc_getClass("SBIconListView");
    BOOL dockLocationValid = [location isEqualToString:@"SBIconLocationDock"] ||
        [location isEqualToString:@"SBIconLocationFloatingDock"];
    if(!iconController || !iconManager || !iconModel ||
       !listViewClass || ![dockListView isKindOfClass:listViewClass] ||
       !dockModel || !dockLocationValid ||
       ![manager isPersistentUserDockModel:dockModel]) {
        if(attempt < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                ARIDockResetAttempt(requestID, attempt + 1);
            });
        } else {
            ARIDockResetFinish(requestID, @"unavailable", 0);
        }
        return;
    }

    NSArray *dockIcons = [ARIDockResetObject(dockModel, @selector(icons)) copy];
    if(![dockIcons isKindOfClass:[NSArray class]]) {
        ARIDockResetFinish(requestID, @"unsupported", 0);
        return;
    }
    if(dockIcons.count == 0) {
        ARIDockResetClearCachedIconState(manager);
        ARIDockResetFinish(requestID, @"alreadyEmpty", 0);
        return;
    }

    id rootFolder = ARIDockResetObject(iconModel, NSSelectorFromString(@"rootFolder")) ?:
                    ARIDockResetObject(iconModel, NSSelectorFromString(@"folder"));
    NSArray *rootIconsBefore = [ARIDockResetObject(rootFolder, @selector(icons)) copy];
    NSDictionary *rootCountsBefore = ARIDockResetIdentifierCounts(rootIconsBefore);
    NSDictionary *dockCountsBefore = ARIDockResetIdentifierCounts(dockIcons);
    NSDictionary *dockFoldersBefore = ARIDockResetFolderFingerprints(dockIcons);
    NSArray *rootListsBefore = ARIDockResetRootListFingerprint(rootFolder);
    NSArray *rootListSnapshotsBefore = ARIDockResetRootListSnapshots(rootFolder);

    SEL addIcons = NSSelectorFromString(@"addIcons:");
    SEL setIcons = NSSelectorFromString(@"setIcons:");
    SEL layoutIfNeeded = @selector(layoutIfNeeded);
    SEL saveIfNeeded = NSSelectorFromString(@"saveIconStateIfNeeded");
    if(!rootFolder || !rootCountsBefore || !dockCountsBefore || !dockFoldersBefore ||
       !rootListsBefore ||
       !rootListSnapshotsBefore ||
       rootListsBefore.count != rootListSnapshotsBefore.count ||
       rootIconsBefore.count < dockIcons.count ||
       !ARIDockResetCanCallObjectArgument(rootFolder, addIcons) ||
       !ARIDockResetCanCallObjectArgument(dockModel, addIcons) ||
       !ARIDockResetCanCallVoidObjectArgument(dockModel, setIcons) ||
       !ARIDockResetCanCallVoid(iconModel, layoutIfNeeded) ||
       !ARIDockResetCanCallBool(iconModel, saveIfNeeded)) {
        ARIDockResetFinish(requestID, @"unsupported", 0);
        return;
    }

    // The root model must already account for each Dock object.  This proves
    // that the before/after multiset comparison below covers the full hierarchy
    // rather than only the visible home pages.
    for(NSString *identifier in dockCountsBefore) {
        if([rootCountsBefore[identifier] unsignedIntegerValue] <
           [dockCountsBefore[identifier] unsignedIntegerValue]) {
            ARIDockResetFinish(requestID, @"unsupported", 0);
            return;
        }
    }

    // The request may have timed out while SpringBoard was waiting for its
    // hierarchy. Re-read the shared deadline immediately before the first
    // mutation so a late handler cannot surprise the user after Settings has
    // already reported a timeout.
    [preferences synchronize];
    NSDictionary *mutationRequest = [preferences
        dictionaryForKey:ARIDockResetRequestKey(requestID)];
    NSNumber *mutationDeadlineValue = [mutationRequest[ARIDockResetRequestDeadlineField]
        isKindOfClass:[NSNumber class]] ?
        mutationRequest[ARIDockResetRequestDeadlineField] : nil;
    NSTimeInterval mutationDeadline = mutationDeadlineValue.doubleValue;
    if(!mutationRequest || !mutationDeadlineValue ||
       !isfinite(mutationDeadline) || mutationDeadline <= 0 ||
       (mutationDeadline > 0 && NSDate.date.timeIntervalSince1970 > mutationDeadline)) {
        ARIDockResetFinish(requestID, @"expired", 0);
        return;
    }

    NSString *failureResult = @"validationFailed";
    BOOL mutationAttempted = NO;
    @try {
        mutationAttempted = YES;
        id rejectedIcons = ARIDockResetCallObjectArgument(rootFolder, addIcons, dockIcons);
        // On supported SpringBoard releases nil or an empty array means every
        // icon was accepted.  Any other object is an unknown contract, so fail
        // closed and restore the exact Dock instead of claiming success.
        BOOL addAcceptedAllIcons = !rejectedIcons ||
            ([rejectedIcons isKindOfClass:[NSArray class]] &&
             [rejectedIcons count] == 0);
        if(addAcceptedAllIcons) {
            // Preserve custom names and older serialized default-name metadata even
            // if SpringBoard normalizes them while changing the containing list.
            ARIDockResetRestoreFolderMetadata(dockIcons, dockFoldersBefore);
            ARIDockResetCallVoid(iconModel, layoutIfNeeded);

            BOOL valid = ARIDockResetMovedStateIsValid(
                rootFolder, dockModel, dockIcons, rootCountsBefore,
                rootListsBefore, dockFoldersBefore);
            if(valid) {
                BOOL saved = ARIDockResetCallBool(iconModel, saveIfNeeded);
                if(saved) {
                    // If Atria was disabled when the always-available reset handler
                    // ran, IconState.xm did not observe this save. Drop any stale
                    // cached state so re-enabling Atria cannot resurrect the Dock.
                    ARIDockResetClearCachedIconState(manager);

                    // Do not ask Atria to relayout after committing the model: on
                    // floating-Dock configurations that could repopulate one stale
                    // user icon. Let one main-queue turn settle SpringBoard's save,
                    // then verify the concrete page lists again before publishing
                    // success. Any late mutation takes the same exact rollback path.
                    dispatch_async(dispatch_get_main_queue(), ^{
                        BOOL postSaveValid = NO;
                        @try {
                            postSaveValid = ARIDockResetMovedStateIsValid(
                                rootFolder, dockModel, dockIcons, rootCountsBefore,
                                rootListsBefore, dockFoldersBefore);
                        } @catch(__unused NSException *exception) {
                            postSaveValid = NO;
                        }
                        if(postSaveValid) {
                            ARIDockResetClearCachedIconState(manager);
                            ARIDockResetFinish(requestID, @"success", dockIcons.count);
                            return;
                        }

                        ARIDockResetFinishAfterRollback(
                            requestID, @"validationFailed", iconModel, dockModel,
                            rootFolder, dockIcons, rootCountsBefore,
                            dockCountsBefore, dockFoldersBefore, rootListsBefore,
                            rootListSnapshotsBefore);
                    });
                    return;
                }
                failureResult = @"saveFailed";
            }
        }
    } @catch(__unused NSException *exception) {
        failureResult = @"validationFailed";
    }

    // A failed postcondition must never leave the user's Dock half-mutated.
    // addIcons: is hierarchy-aware in both directions. Only pass objects that
    // actually left the Dock; submitting an object still present in the Dock
    // can duplicate it. Exact postconditions below reject any order change.
    if(mutationAttempted) {
        ARIDockResetFinishAfterRollback(
            requestID, failureResult, iconModel, dockModel, rootFolder,
            dockIcons, rootCountsBefore, dockCountsBefore,
            dockFoldersBefore, rootListsBefore, rootListSnapshotsBefore);
    } else {
        ARIDockResetFinish(requestID, failureResult, 0);
    }
}

static void ARIDockResetDrainRequests(void) {
    if(ARIDockResetInProgress) return;

    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    [preferences synchronize];
    NSDictionary *domain = [preferences persistentDomainForName:ARIPreferenceDomain] ?: @{};
    NSString *legacyRequestID = [preferences stringForKey:ARIDockResetRequestIDKey];
    NSString *legacyCompletedID = [preferences stringForKey:ARIDockResetCompletedIDKey];
    BOOL promotedScalarOnlyCompletion = NO;

    // Development builds briefly used one shared completion dictionary. Treat
    // every correlated terminal entry as authoritative before scanning pending
    // request keys, so no already-finished request can be replayed after an
    // in-place update.
    NSDictionary *legacyCompletions = [domain[@"_dockResetCompletions"]
        isKindOfClass:[NSDictionary class]] ? domain[@"_dockResetCompletions"] : nil;
    BOOL migratedLegacyCompletions = NO;
    for(NSString *requestID in legacyCompletions) {
        if(!ARIDockResetValidRequestID(requestID)) continue;
        NSDictionary *completion = [legacyCompletions[requestID]
            isKindOfClass:[NSDictionary class]] ? legacyCompletions[requestID] : nil;
        if(!completion) continue;
        NSString *completedID = [completion[ARIDockResetCompletionRequestIDField]
            isKindOfClass:[NSString class]] ?
            completion[ARIDockResetCompletionRequestIDField] : nil;
        if(![completedID isEqualToString:requestID]) continue;
        NSMutableDictionary *promotedCompletion = [completion mutableCopy];
        NSString *requestKey = ARIDockResetRequestKey(requestID);
        NSDictionary *exactRequest = [domain[requestKey] isKindOfClass:[NSDictionary class]] ?
            domain[requestKey] : nil;
        NSDictionary *legacyRequestMap = [domain[@"_dockResetRequests"]
            isKindOfClass:[NSDictionary class]] ? domain[@"_dockResetRequests"] : nil;
        NSDictionary *mappedRequest = [legacyRequestMap[requestID]
            isKindOfClass:[NSDictionary class]] ?
            legacyRequestMap[requestID] : nil;
        NSNumber *requestTimestamp = [exactRequest[ARIDockResetRequestTimestampField]
            isKindOfClass:[NSNumber class]] ? exactRequest[ARIDockResetRequestTimestampField] :
            ([mappedRequest[ARIDockResetRequestTimestampField] isKindOfClass:[NSNumber class]] ?
                mappedRequest[ARIDockResetRequestTimestampField] : nil);
        if(requestTimestamp &&
           !promotedCompletion[ARIDockResetCompletionRequestTimestampField])
            promotedCompletion[ARIDockResetCompletionRequestTimestampField] = requestTimestamp;
        BOOL hasCurrentProvenance =
            [completion[ARIDockResetCompletionLegacyScalarField]
                isKindOfClass:[NSNumber class]];
        BOOL scalarCorrelatesLegacyMapRecord =
            [legacyCompletedID isEqualToString:requestID] && !hasCurrentProvenance;
        if(scalarCorrelatesLegacyMapRecord)
            promotedCompletion[ARIDockResetCompletionLegacyScalarField] = @YES;
        NSString *completionKey = ARIDockResetCompletionKey(requestID);
        NSDictionary *existingCompletion = [domain[completionKey]
            isKindOfClass:[NSDictionary class]] ? domain[completionKey] : nil;
        if(!existingCompletion) {
            [preferences setObject:promotedCompletion forKey:completionKey];
        } else if(scalarCorrelatesLegacyMapRecord &&
                  ![existingCompletion[ARIDockResetCompletionLegacyScalarField]
                    isEqual:@YES]) {
            NSMutableDictionary *mergedCompletion = [existingCompletion mutableCopy];
            mergedCompletion[ARIDockResetCompletionLegacyScalarField] = @YES;
            if(requestTimestamp &&
               !mergedCompletion[ARIDockResetCompletionRequestTimestampField])
                mergedCompletion[ARIDockResetCompletionRequestTimestampField] = requestTimestamp;
            [preferences setObject:mergedCompletion forKey:completionKey];
        }
        [preferences removeObjectForKey:requestKey];
        migratedLegacyCompletions = YES;
    }
    if(migratedLegacyCompletions) {
        [preferences synchronize];
        domain = [preferences persistentDomainForName:ARIPreferenceDomain] ?: @{};
    }

    // The same intermediate build stored requests in a shared map. Copy every
    // exact envelope; terminal UUIDs above take precedence. Keep the map while
    // mixed-version PreferenceLoader processes may still append to it—the
    // durable exact request/completion keys make repeated scans idempotent.
    NSDictionary *legacyRequests = [domain[@"_dockResetRequests"]
        isKindOfClass:[NSDictionary class]] ? domain[@"_dockResetRequests"] : nil;
    BOOL migratedLegacyRequests = NO;
    for(NSString *requestID in legacyRequests) {
        if(!ARIDockResetValidRequestID(requestID)) continue;
        NSDictionary *request = [legacyRequests[requestID]
            isKindOfClass:[NSDictionary class]] ? legacyRequests[requestID] : nil;
        NSNumber *timestampValue = [request[ARIDockResetRequestTimestampField]
            isKindOfClass:[NSNumber class]] ? request[ARIDockResetRequestTimestampField] : nil;
        NSNumber *deadlineValue = [request[ARIDockResetRequestDeadlineField]
            isKindOfClass:[NSNumber class]] ? request[ARIDockResetRequestDeadlineField] : nil;
        double timestamp = timestampValue.doubleValue;
        double deadline = deadlineValue.doubleValue;
        NSString *requestKey = ARIDockResetRequestKey(requestID);
        NSString *completionKey = ARIDockResetCompletionKey(requestID);
        if(!domain[requestKey] && !domain[completionKey]) {
            if(timestampValue && deadlineValue && isfinite(timestamp) &&
               isfinite(deadline) && timestamp > 0 && deadline > 0) {
                [preferences setObject:request forKey:requestKey];
            } else {
                [preferences setObject:@{
                    ARIDockResetCompletionRequestIDField: requestID,
                    ARIDockResetCompletionResultField: @"validationFailed",
                    ARIDockResetCompletionMovedCountField: @0,
                    ARIDockResetCompletionRequestTimestampField: @0,
                    ARIDockResetCompletionTimestampField:
                        @(NSDate.date.timeIntervalSince1970)
                } forKey:completionKey];
            }
        }
        migratedLegacyRequests = YES;
    }
    if(migratedLegacyRequests) {
        [preferences synchronize];
        domain = [preferences persistentDomainForName:ARIPreferenceDomain] ?: @{};
    }

    // Upgrade an old single-slot request into a durable per-request key. An
    // already-completed legacy request is intentionally not replayed.
    if(ARIDockResetValidRequestID(legacyRequestID) &&
       ![legacyCompletedID isEqualToString:legacyRequestID]) {
        NSString *requestKey = ARIDockResetRequestKey(legacyRequestID);
        NSString *completionKey = ARIDockResetCompletionKey(legacyRequestID);
        if(!domain[requestKey] && !domain[completionKey]) {
            NSTimeInterval deadline = [preferences doubleForKey:ARIDockResetDeadlineKey];
            NSTimeInterval timestamp = deadline > 0 ? deadline - 8.0 : 0;
            [preferences setObject:@{
                ARIDockResetRequestTimestampField: @(timestamp),
                ARIDockResetRequestDeadlineField: @(deadline)
            } forKey:requestKey];
            [preferences synchronize];
            domain = [preferences persistentDomainForName:ARIPreferenceDomain] ?: @{};
        }
    }

    // If a new Preferences bundle was handled by an older SpringBoard during
    // an in-place upgrade, convert the correlated scalar result and retire the
    // otherwise-stale per-request key without replaying the Dock mutation.
    if(ARIDockResetValidRequestID(legacyCompletedID)) {
        NSString *requestKey = ARIDockResetRequestKey(legacyCompletedID);
        NSString *completionKey = ARIDockResetCompletionKey(legacyCompletedID);
        if(domain[requestKey] && !domain[completionKey]) {
            ARIDockResetRecordCompletion(
                legacyCompletedID,
                [preferences stringForKey:ARIDockResetResultKey] ?: @"validationFailed",
                (NSUInteger)[preferences integerForKey:ARIDockResetMovedCountKey]
            );
            NSMutableDictionary *scalarCompletion = [[preferences
                dictionaryForKey:completionKey] mutableCopy];
            if(scalarCompletion) {
                scalarCompletion[ARIDockResetCompletionLegacyScalarField] = @YES;
                [preferences setObject:scalarCompletion forKey:completionKey];
            }
            promotedScalarOnlyCompletion = YES;
            [preferences synchronize];
            domain = [preferences persistentDomainForName:ARIPreferenceDomain] ?: @{};
        }
    }

    // Scalar-only SpringBoard versions can prove only the last completed UUID.
    // Any older request from the same client generation may already have been
    // completed before that scalar slot was overwritten. Fence those requests
    // as terminal instead of risking a duplicate destructive replay.
    NSDictionary *legacyTerminal = [domain[ARIDockResetCompletionKey(legacyCompletedID)]
        isKindOfClass:[NSDictionary class]] ?
        domain[ARIDockResetCompletionKey(legacyCompletedID)] : nil;
    BOOL terminalCameFromLegacyScalar =
        [legacyTerminal[ARIDockResetCompletionLegacyScalarField]
            isKindOfClass:[NSNumber class]] &&
        [legacyTerminal[ARIDockResetCompletionLegacyScalarField] boolValue];
    NSNumber *legacyRequestTimestampValue =
        [legacyTerminal[ARIDockResetCompletionRequestTimestampField]
            isKindOfClass:[NSNumber class]] ?
        legacyTerminal[ARIDockResetCompletionRequestTimestampField] : nil;
    double legacyRequestTimestamp = legacyRequestTimestampValue.doubleValue;
    if((promotedScalarOnlyCompletion || terminalCameFromLegacyScalar) &&
       legacyRequestTimestampValue &&
       isfinite(legacyRequestTimestamp) &&
       legacyRequestTimestamp > 0) {
        BOOL fencedOlderRequests = NO;
        for(NSString *key in domain) {
            if(![key isKindOfClass:[NSString class]] ||
               ![key hasPrefix:ARIDockResetRequestKeyPrefix]) continue;
            NSString *requestID = [key substringFromIndex:ARIDockResetRequestKeyPrefix.length];
            if(!ARIDockResetValidRequestID(requestID) ||
               [requestID isEqualToString:legacyCompletedID] ||
               domain[ARIDockResetCompletionKey(requestID)]) continue;
            NSDictionary *request = [domain[key] isKindOfClass:[NSDictionary class]] ?
                domain[key] : nil;
            NSNumber *timestampValue = [request[ARIDockResetRequestTimestampField]
                isKindOfClass:[NSNumber class]] ?
                request[ARIDockResetRequestTimestampField] : nil;
            double timestamp = timestampValue.doubleValue;
            if(!timestampValue || !isfinite(timestamp) || timestamp <= 0 ||
               timestamp > legacyRequestTimestamp) continue;
            [preferences setObject:@{
                ARIDockResetCompletionRequestIDField: requestID,
                ARIDockResetCompletionResultField: @"superseded",
                ARIDockResetCompletionMovedCountField: @0,
                ARIDockResetCompletionRequestTimestampField: timestampValue,
                ARIDockResetCompletionTimestampField:
                    @(NSDate.date.timeIntervalSince1970)
            } forKey:ARIDockResetCompletionKey(requestID)];
            [preferences removeObjectForKey:key];
            fencedOlderRequests = YES;
        }
        if(fencedOlderRequests) {
            [preferences synchronize];
            domain = [preferences persistentDomainForName:ARIPreferenceDomain] ?: @{};
        }
    }

    NSMutableArray<NSDictionary *> *pending = [NSMutableArray array];
    BOOL removedCompletedRequest = NO;
    for(NSString *key in domain) {
        if(![key isKindOfClass:[NSString class]] ||
           ![key hasPrefix:ARIDockResetRequestKeyPrefix]) continue;
        NSString *requestID = [key substringFromIndex:ARIDockResetRequestKeyPrefix.length];
        if(!ARIDockResetValidRequestID(requestID)) continue;

        if([domain[ARIDockResetCompletionKey(requestID)] isKindOfClass:[NSDictionary class]]) {
            [preferences removeObjectForKey:key];
            removedCompletedRequest = YES;
            continue;
        }

        NSDictionary *request = [domain[key] isKindOfClass:[NSDictionary class]] ?
            domain[key] : @{};
        NSNumber *timestamp = [request[ARIDockResetRequestTimestampField]
            isKindOfClass:[NSNumber class]] ? request[ARIDockResetRequestTimestampField] : @0;
        [pending addObject:@{
            @"requestID": requestID,
            @"timestamp": timestamp
        }];
    }
    if(removedCompletedRequest) [preferences synchronize];

    [pending sortUsingComparator:^NSComparisonResult(NSDictionary *left,
                                                       NSDictionary *right) {
        double leftTime = [left[@"timestamp"] doubleValue];
        double rightTime = [right[@"timestamp"] doubleValue];
        if(!isfinite(leftTime)) leftTime = 0;
        if(!isfinite(rightTime)) rightTime = 0;
        if(leftTime < rightTime) return NSOrderedAscending;
        if(leftTime > rightTime) return NSOrderedDescending;
        return [left[@"requestID"] compare:right[@"requestID"]];
    }];

    NSString *requestID = pending.firstObject[@"requestID"];
    if(requestID.length == 0) return;
    ARIDockResetInProgress = YES;
    ARIDockResetAttempt(requestID, 0);
}

static void ARIDockResetRequested(CFNotificationCenterRef center,
                                  void *observer,
                                  CFStringRef name,
                                  const void *object,
                                  CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        ARIDockResetDrainRequests();
    });
}

__attribute__((constructor))
static void ARIDockArrangementResetLoaded(void) {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        ARIDockResetRequested,
        (__bridge CFStringRef)ARIDockResetRequestNotification,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    // Keep preference inspection out of dyld initialization. This delayed
    // drain recovers a notification posted while SpringBoard was unavailable.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        ARIDockResetDrainRequests();
    });
}

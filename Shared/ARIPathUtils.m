#import "ARIPathUtils.h"

#include <dlfcn.h>

static NSString *ARIPathUtilsPreferenceBundlePathUncached(void);

static NSString *ARIPathUtilsJBRootPathForDirectory(NSString *directoryPath) {
    if(![directoryPath isKindOfClass:[NSString class]] || directoryPath.length == 0) return nil;

    NSString *jbrootPath = [directoryPath stringByAppendingPathComponent:@".jbroot"];
    return [[NSFileManager defaultManager] fileExistsAtPath:jbrootPath] ? jbrootPath : nil;
}

static NSArray<NSString *> *ARIPathUtilsPreferenceBundleCandidates(void) {
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    NSArray<NSString *> *classNames = @[
        @"ARIListController",
        @"ARIRootListController",
        @"ARIHeaderCell",
        @"ARITweakManager"
    ];

    for(NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        if(!cls) continue;

        NSBundle *bundle = [NSBundle bundleForClass:cls];
        if([bundle.bundlePath.lastPathComponent isEqualToString:@"AtriaPrefs.bundle"]) {
            [paths addObject:bundle.bundlePath];
        }
    }

    NSString *installPrefix = @THEOS_PACKAGE_INSTALL_PREFIX;
    if([installPrefix isKindOfClass:[NSString class]] && installPrefix.length > 0) {
        [paths addObject:[installPrefix stringByAppendingString:@"/Library/PreferenceBundles/AtriaPrefs.bundle"]];
    }

    [paths addObject:@"/var/jb/Library/PreferenceBundles/AtriaPrefs.bundle"];
    [paths addObject:@"/Library/PreferenceBundles/AtriaPrefs.bundle"];
    return paths.array;
}

static NSArray<NSString *> *ARIJBRootCandidatePaths(NSString *rootRelativePath) {
    if(![rootRelativePath isKindOfClass:[NSString class]] || rootRelativePath.length == 0) return @[];

    NSString *normalizedPath = [rootRelativePath hasPrefix:@"/"]
        ? rootRelativePath
        : [@"/" stringByAppendingString:rootRelativePath];
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    Dl_info info = {0};
    if(dladdr((const void *)&ARIExistingJBRootPath, &info) && info.dli_fname) {
        NSString *binaryDirectory = [@(info.dli_fname) stringByDeletingLastPathComponent];
        NSString *binaryJBRoot = ARIPathUtilsJBRootPathForDirectory(binaryDirectory);
        if(binaryJBRoot.length > 0) {
            [paths addObject:[binaryJBRoot stringByAppendingString:normalizedPath]];
        }
    }

    NSString *bundlePath = ARIPathUtilsPreferenceBundlePathUncached();
    if(bundlePath.length > 0) {
        NSString *bundleJBRoot = ARIPathUtilsJBRootPathForDirectory(bundlePath);
        if(bundleJBRoot.length > 0) {
            [paths addObject:[bundleJBRoot stringByAppendingString:normalizedPath]];
        }
    }

    NSString *installPrefix = @THEOS_PACKAGE_INSTALL_PREFIX;
    if([installPrefix isKindOfClass:[NSString class]] && installPrefix.length > 0) {
        [paths addObject:[installPrefix stringByAppendingString:normalizedPath]];
    }

    NSString *varJBPath = [@"/var/jb" stringByAppendingString:normalizedPath];
    [paths addObject:varJBPath];
    [paths addObject:normalizedPath];

    NSMutableArray<NSString *> *existingPaths = [NSMutableArray array];
    for(NSString *candidatePath in paths) {
        if([fileManager fileExistsAtPath:candidatePath]) {
            [existingPaths addObject:candidatePath];
        }
    }

    return existingPaths;
}

NSString *ARIExistingJBRootPath(NSString *rootRelativePath) {
    for(NSString *candidate in ARIJBRootCandidatePaths(rootRelativePath)) {
        return candidate;
    }
    return nil;
}

static NSString *ARIPathUtilsPreferenceBundlePathUncached(void) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for(NSString *candidatePath in ARIPathUtilsPreferenceBundleCandidates()) {
        BOOL isDirectory = NO;
        if([fileManager fileExistsAtPath:candidatePath isDirectory:&isDirectory] && isDirectory) {
            return candidatePath;
        }
    }
    return nil;
}

NSString *ARIPreferenceBundlePath(void) {
    static NSString *bundlePath;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundlePath = ARIPathUtilsPreferenceBundlePathUncached();
    });
    return bundlePath;
}

NSString *ARIPreferenceBundleResourcePath(NSString *name, NSString *extension, NSString *subdirectory) {
    if(![name isKindOfClass:[NSString class]] || name.length == 0) return nil;

    NSString *bundlePath = ARIPreferenceBundlePath();
    if(bundlePath.length == 0) return nil;

    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSArray<NSString *> *candidateNames = @[
        name,
        [name stringByReplacingOccurrencesOfString:@" " withString:@"_"]
    ];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    for(NSString *candidateName in candidateNames) {
        NSString *path = [bundle pathForResource:candidateName ofType:extension inDirectory:subdirectory];
        if(path.length > 0) {
            return path;
        }

        NSMutableArray<NSString *> *components = [NSMutableArray arrayWithObject:bundlePath];
        if([subdirectory isKindOfClass:[NSString class]] && subdirectory.length > 0) {
            [components addObject:subdirectory];
        }

        NSString *filename = extension.length > 0
            ? [candidateName stringByAppendingPathExtension:extension]
            : candidateName;
        [components addObject:filename];

        NSString *manualPath = [NSString pathWithComponents:components];
        if([fileManager fileExistsAtPath:manualPath]) {
            return manualPath;
        }
    }

    return nil;
}

NSString *ARIMobileSubstrateDylibPath(NSString *dylibName) {
    if(![dylibName isKindOfClass:[NSString class]] || dylibName.length == 0) return nil;

    NSString *normalizedName = [dylibName.pathExtension.lowercaseString isEqualToString:@"dylib"]
        ? dylibName
        : [dylibName stringByAppendingPathExtension:@"dylib"];
    NSString *relativePath = [@"/Library/MobileSubstrate/DynamicLibraries" stringByAppendingPathComponent:normalizedName];
    return ARIExistingJBRootPath(relativePath);
}

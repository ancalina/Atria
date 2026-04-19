//
// Created by ren7995 on 2023-05-25 21:53:27
// Copyright (c) 2023 ren7995. All rights reserved.
//

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../../Shared/ARISharedConstants.h"

#define kPrefTintColor kARIPrefTintColor

@interface ARIListController : PSListController
- (NSString *)atriaPathForResource:(NSString *)name ofType:(NSString *)ext inDirectory:(NSString *)directory;
- (void)atriaResolveIconPathsForSpecifiers:(NSArray<PSSpecifier *> *)specifiers;
- (void)promptRespring:(id)sender;
- (void)respringWithAnimation;
@end

@interface NSTask : NSObject
@property (copy) NSArray *arguments;
@property (copy) NSString *launchPath;
- (id)init;
- (void)waitUntilExit;
- (void)launch;
@end

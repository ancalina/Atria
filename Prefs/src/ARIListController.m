//
// Created by ren7995 on 2023-05-25 21:53:35
// Copyright (c) 2023 ren7995. All rights reserved.
//

#import "ARIListController.h"
#import "../../Shared/ARIPathUtils.h"

#include <spawn.h>

extern char **environ;

static BOOL ARILaunchBootstrapTool(NSString *toolPath, NSArray<NSString *> *arguments) {
    if(![toolPath isKindOfClass:[NSString class]] || toolPath.length == 0) return NO;

    const char *tool = toolPath.fileSystemRepresentation;
    NSUInteger extraCount = arguments.count;
    char *argv[extraCount + 2];
    argv[0] = (char *)tool;
    for(NSUInteger idx = 0; idx < extraCount; idx++) {
        argv[idx + 1] = (char *)[arguments[idx] UTF8String];
    }
    argv[extraCount + 1] = NULL;

    pid_t pid = 0;
    return posix_spawn(&pid, tool, NULL, NULL, argv, environ) == 0;
}

@implementation ARIListController

- (NSString *)atriaPathForResource:(NSString *)name ofType:(NSString *)ext inDirectory:(NSString *)directory {
    if(![name isKindOfClass:[NSString class]] || name.length == 0) return nil;

    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *path = [bundle pathForResource:name ofType:ext inDirectory:directory];
    if(path) return path;

    NSString *normalized = [name stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    if(![normalized isEqualToString:name]) {
        path = [bundle pathForResource:normalized ofType:ext inDirectory:directory];
        if(path) return path;
    }

    return nil;
}

- (void)atriaResolveIconPathsForSpecifiers:(NSArray<PSSpecifier *> *)specifiers {
    for(PSSpecifier *specifier in specifiers) {
        NSString *iconName = [specifier propertyForKey:@"icon"];
        if(![iconName isKindOfClass:[NSString class]] || iconName.length == 0) continue;

        NSString *path = nil;
        NSString *ext = iconName.pathExtension;
        if(ext.length > 0) {
            path = [self atriaPathForResource:[iconName stringByDeletingPathExtension] ofType:ext inDirectory:nil];
        } else {
            path = [self atriaPathForResource:iconName ofType:@"png" inDirectory:nil];
        }

        if(path) {
            [specifier setProperty:path forKey:@"icon"];
        }
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [[UISegmentedControl appearanceWhenContainedInInstancesOfClasses:@[ self.class ]] setTintColor:kPrefTintColor];
    [[UISwitch appearanceWhenContainedInInstancesOfClasses:@[ self.class ]] setOnTintColor:kPrefTintColor];
    [[UISlider appearanceWhenContainedInInstancesOfClasses:@[ self.class ]] setTintColor:kPrefTintColor];

    [super viewWillAppear:animated];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIBarButtonItem *respring = [[UIBarButtonItem alloc] initWithTitle:@"리스프링" style:UIBarButtonItemStylePlain target:self action:@selector(promptRespring:)];
    self.navigationItem.rightBarButtonItem = respring;
}

- (void)promptRespring:(id)sender {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"리스프링"
                         message:@"정말로 SpringBoard를 다시시작 하겠습니까?"
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"좀더 생각해 볼래요"
                  style:UIAlertActionStyleCancel
                handler:nil];

    UIAlertAction *yes = [UIAlertAction
        actionWithTitle:@"예"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    [self respringWithAnimation];
                }];

    [alert addAction:defaultAction];
    [alert addAction:yes];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)respringWithAnimation {
    self.view.userInteractionEnabled = NO;

    UIVisualEffectView *matEffect = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    matEffect.alpha = 0.0F;
    matEffect.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *view = [UIApplication sharedApplication].keyWindow.rootViewController.view;
    [view addSubview:matEffect];
    [NSLayoutConstraint activateConstraints:@[
        [matEffect.widthAnchor constraintEqualToAnchor:view.widthAnchor],
        [matEffect.heightAnchor constraintEqualToAnchor:view.heightAnchor],
        [matEffect.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [matEffect.centerYAnchor constraintEqualToAnchor:view.centerYAnchor]
    ]];

    [UIView animateWithDuration:1.0f
        delay:0.0f
        options:UIViewAnimationOptionCurveEaseIn
        animations:^{
            matEffect.alpha = 1.0F;
        }
        completion:^(BOOL finished) {
            BOOL launched = NO;
            NSString *sbreloadPath = ARIExistingJBRootPath(@"/usr/bin/sbreload");
            if(sbreloadPath.length > 0) {
                launched = ARILaunchBootstrapTool(sbreloadPath, @[]);
            }

            if(!launched) {
                NSString *killallPath = ARIExistingJBRootPath(@"/usr/bin/killall");
                if(killallPath.length > 0) {
                    launched = ARILaunchBootstrapTool(killallPath, @[ @"SpringBoard" ]);
                }
            }

            if(launched) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    exit(0);
                });
                return;
            }

            [UIView animateWithDuration:0.2f animations:^{
                matEffect.alpha = 0.0F;
            } completion:^(BOOL completed) {
                [matEffect removeFromSuperview];
                self.view.userInteractionEnabled = YES;

                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:@"리스프링 실패"
                                     message:@"리스프링 도구를 실행할 수 없습니다."
                              preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"확인"
                                                          style:UIAlertActionStyleDefault
                                                        handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }];
        }];
}

@end

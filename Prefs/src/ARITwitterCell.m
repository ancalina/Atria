//
// Created by ren7995 on 2021-04-27 22:17:01
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "ARITwitterCell.h"
#import "../../Shared/ARIPathUtils.h"

@implementation ARITwitterCell {
    UIImageView *_icon;
    UILabel *_userLabel;
    NSString *_username;
    NSString *_displayName;
    NSString *_imageName;
    NSString *_memorialTitle;
    NSString *_memorialMessage;
}

static UIViewController *ARIResponderViewController(UIResponder *responder) {
    UIResponder *current = responder;
    while(current) {
        if([current isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)current;
        }
        current = current.nextResponder;
    }
    return nil;
}

static UIImage *ARITwitterProfileImage(NSString *name) {
    if(![name isKindOfClass:[NSString class]] || name.length == 0) return nil;

    NSMutableOrderedSet<NSString *> *candidateNames = [NSMutableOrderedSet orderedSet];
    [candidateNames addObject:name];
    [candidateNames addObject:[name stringByReplacingOccurrencesOfString:@" " withString:@"_"]];
    [candidateNames addObject:name.lowercaseString];
    [candidateNames addObject:[[name stringByReplacingOccurrencesOfString:@" " withString:@"_"] lowercaseString]];
    NSArray<NSString *> *extensions = @[ @"jpg", @"png" ];

    for(NSString *candidateName in candidateNames) {
        for(NSString *extension in extensions) {
            NSString *path = ARIPreferenceBundleResourcePath(candidateName, extension, @"ProfilePictures");
            if(path.length > 0) {
                UIImage *image = [UIImage imageWithContentsOfFile:path];
                if(image) return image;
            }
        }
    }

    return nil;
}

- (id)initWithStyle:(UITableViewCellStyle)style
    reuseIdentifier:(NSString *)reuseIdentifier
          specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];

    if(self) {
        _icon = [[UIImageView alloc] initWithImage:nil];
        [self addSubview:_icon];
        _icon.layer.masksToBounds = YES;
        _icon.layer.cornerCurve = kCACornerCurveCircular;
        _icon.layer.cornerRadius = 25;
        _icon.translatesAutoresizingMaskIntoConstraints = NO;

        [NSLayoutConstraint activateConstraints:@[
            [_icon.widthAnchor constraintEqualToConstant:50],
            [_icon.heightAnchor constraintEqualToAnchor:_icon.widthAnchor],
            [_icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                constant:20],
            [_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];

        _username = specifier.properties[@"username"];
        _displayName = specifier.properties[@"displayName"];
        _imageName = specifier.properties[@"imageName"] ?: _displayName;
        _memorialTitle = specifier.properties[@"memorialTitle"];
        _memorialMessage = specifier.properties[@"memorialMessage"];

        _userLabel = [[UILabel alloc] init];
        _userLabel.text = [NSString stringWithFormat:@"%@ - %@", _displayName, specifier.properties[@"description"]];
        _userLabel.numberOfLines = 0;
        _userLabel.font = [UIFont systemFontOfSize:14];
        _userLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_userLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_userLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                      constant:-20],
            [_userLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_userLabel.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                                    constant:-10],
            [_userLabel.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor
                                                     constant:10],
        ]];
        [self loadImage];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    _username = specifier.properties[@"username"];
    _displayName = specifier.properties[@"displayName"];
    _imageName = specifier.properties[@"imageName"] ?: _displayName;
    _memorialTitle = specifier.properties[@"memorialTitle"];
    _memorialMessage = specifier.properties[@"memorialMessage"];
    _userLabel.text = [NSString stringWithFormat:@"%@ - %@", _displayName ?: @"", specifier.properties[@"description"] ?: @""];
    [self loadImage];
    [self.specifier setTarget:self];
    [self.specifier setButtonAction:@selector(openTwitter)];
}

- (void)loadImage {
    UIImage *profileImage = ARITwitterProfileImage(_imageName ?: _displayName);
    if(profileImage) {
        _icon.image = profileImage;
        _icon.contentMode = UIViewContentModeScaleAspectFill;
    } else {
        _icon.image = [UIImage systemImageNamed:@"person.circle"];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
    }
}

- (void)openTwitter {
    if(_memorialMessage.length > 0) {
        UIViewController *controller = ARIResponderViewController(self);
        if(controller) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:(_memorialTitle.length > 0 ? _memorialTitle : _displayName ?: @"알림")
                                                                           message:_memorialMessage
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"확인" style:UIAlertActionStyleCancel handler:nil]];
            [controller presentViewController:alert animated:YES completion:nil];
        }
        return;
    }
    if(!_username) return;
    UIApplication *application = [UIApplication sharedApplication];
    NSString *url = [@"https://twitter.com/" stringByAppendingString:_username];
    [application openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
}

@end

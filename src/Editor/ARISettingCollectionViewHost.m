//
// Created by ren7995 on 2021-05-02 00:44:58
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "ARISettingCollectionViewHost.h"
#import "ARIEditingMainView.h"
#import "../Manager/ARITweakManager.h"
#import "../../Shared/ARIPathUtils.h"
#import "ARISettingCell.h"
#import <QuartzCore/QuartzCore.h>

static NSString *ARIAEditorResourcePath(NSString *name) {
    if(![name isKindOfClass:[NSString class]] || name.length == 0) return nil;
    return ARIPreferenceBundleResourcePath(name, @"png", @"Editor");
}

@implementation ARISettingCollectionViewHost {
    __weak ARIEditingMainView *_editor;
    CAGradientLayer *_fadeLayer;
}

- (instancetype)initWithEditor:(ARIEditingMainView *)editor {
    // This class "hosts" a UICollectionView and handles a gradient fade effect on the edges
    self = [super init];
    if(self) {
        _editor = editor;
        UICollectionViewFlowLayout *flow = [[UICollectionViewFlowLayout alloc] init];
        flow.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        UICollectionView *coll = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:flow];
        coll.backgroundColor = [UIColor clearColor];
        [coll setShowsHorizontalScrollIndicator:YES];
        [coll setShowsVerticalScrollIndicator:NO];
        [coll registerClass:[ARISettingCell class] forCellWithReuseIdentifier:@"EditCell"];
        coll.delegate = self;
        coll.dataSource = self;

        _fadeLayer = [CAGradientLayer layer];
        _fadeLayer.startPoint = CGPointMake(0.0, 0.5);
        _fadeLayer.endPoint = CGPointMake(1.0, 0.5);
        _fadeLayer.colors = @[
            (id)UIColor.clearColor.CGColor,
            (id)UIColor.whiteColor.CGColor,
            (id)UIColor.whiteColor.CGColor,
            (id)UIColor.clearColor.CGColor,
        ];
        _fadeLayer.locations = @[ @0.0, @0.05, @0.9, @1.0 ];
        self.layer.mask = _fadeLayer;

        [self addSubview:coll];
        coll.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [coll.widthAnchor constraintEqualToAnchor:self.widthAnchor],
            [coll.heightAnchor constraintEqualToAnchor:self.heightAnchor],
            [coll.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [coll.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
    }
    return self;
}

- (ARISettingCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ARISettingCell *cell = (ARISettingCell *)[collectionView dequeueReusableCellWithReuseIdentifier:@"EditCell" forIndexPath:indexPath];
    NSArray<NSString *> *settings = _editor.validsettingsForTarget;
    if(indexPath.row >= settings.count) return cell;

    NSString *key = settings[indexPath.row];
    cell.opLabel.text = [[ARITweakManager sharedInstance] getSettingByKey:key].translation;

    NSRange separator = [key rangeOfString:@"_"];
    if(separator.location != NSNotFound && NSMaxRange(separator) < key.length)
        key = [key substringFromIndex:NSMaxRange(separator)];

    NSString *path = ARIAEditorResourcePath(key);
    cell.img.image = [[UIImage imageWithContentsOfFile:path] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
        ?: [UIImage systemImageNamed:@"gear"];
    return cell;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _editor.validsettingsForTarget.count;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    ARIEditingMainView *editor = _editor;
    NSArray<NSString *> *settings = editor.validsettingsForTarget;
    if(!editor || indexPath.row >= settings.count) return;

    [editor setupForSettingKey:settings[indexPath.row]];
    [editor toggleOptionsView:nil];
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)collectionViewLayout
   sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(65, 65);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView
                        layout:(UICollectionViewLayout *)collectionViewLayout
        insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(5, 10, 10, 10);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _fadeLayer.frame = self.bounds;
}

@end

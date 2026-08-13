//
// Created by ren7995 on 2021-05-02 00:44:39
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import <UIKit/UIKit.h>

@class ARIEditingMainView;

@interface ARISettingCollectionViewHost : UIView <UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
- (instancetype)initWithEditor:(ARIEditingMainView *)editor;
@end

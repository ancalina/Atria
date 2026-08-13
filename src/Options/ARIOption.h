//
// Created by ren7995 on 2022-05-16 13:30:44
// Copyright (c) 2022 ren7995. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ARIOption : NSObject
@property (nonatomic, readonly, strong) NSString *settingKey;
@property (nonatomic, readonly, strong) NSString *translation;
@property (nonatomic, readonly, strong) id defaultValue;
@property (nonatomic, readonly, assign) float lowerLimit;
@property (nonatomic, readonly, assign) float upperLimit;
@property (nonatomic, readonly, assign) double hardLowerLimit;
@property (nonatomic, readonly, assign) double hardUpperLimit;
@property (nonatomic, readonly, assign) BOOL accessibleWithEditor;
@property (nonatomic, readonly, assign, getter=isIntegralValue) BOOL integralValue;
- (instancetype)initWithKey:(NSString *)settingKey
                translation:(NSString *)settingTranslation
               defaultValue:(id)defaultValue
                 lowerLimit:(float)lowerLimit
                 upperLimit:(float)upperLimit;
@end

//
// Created by ren7995 on 2022-05-16 13:30:43
// Copyright (c) 2022 ren7995. All rights reserved.
//

#import "ARIOption.h"
#import "../../Shared/ARIEditorValuePolicy.h"

@implementation ARIOption {
    NSString *_settingKey;
    NSString *_translation;
    id _defaultValue;
    float _lowerLimit;
    float _upperLimit;
    double _hardLowerLimit;
    double _hardUpperLimit;
    BOOL _accessibleWithEditor;
    BOOL _integralValue;
}

@synthesize settingKey = _settingKey;
@synthesize translation = _translation;
@synthesize defaultValue = _defaultValue;
@synthesize lowerLimit = _lowerLimit;
@synthesize upperLimit = _upperLimit;
@synthesize hardLowerLimit = _hardLowerLimit;
@synthesize hardUpperLimit = _hardUpperLimit;
@synthesize accessibleWithEditor = _accessibleWithEditor;
@synthesize integralValue = _integralValue;

- (instancetype)initWithKey:(NSString *)settingKey
                translation:(NSString *)settingTranslation
               defaultValue:(id)defaultValue
                 lowerLimit:(float)lowerLimit
                 upperLimit:(float)upperLimit {
    self = [super init];
    if(self) {
        _settingKey = settingKey;
        _translation = settingTranslation;
        _defaultValue = defaultValue;
        _lowerLimit = lowerLimit;
        _upperLimit = upperLimit;
        _accessibleWithEditor = _translation != nil;
        BOOL policyIntegral = NO;
        if(!ARIEditorValuePolicyForKey(settingKey,
                                       &_hardLowerLimit,
                                       &_hardUpperLimit,
                                       &policyIntegral)) {
            _hardLowerLimit = lowerLimit;
            _hardUpperLimit = upperLimit;
        }
        _integralValue = policyIntegral;
    }
    return self;
}

@end

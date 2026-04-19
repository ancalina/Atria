//
// Shared label script parser/validator.
//

#import "ARILabelScriptCompiler.h"

NSString *const ARILabelScriptErrorDomain = @"me.lau.Atria.LabelScript";

typedef NS_ENUM(NSInteger, ARILabelScriptErrorCode) {
    ARILabelScriptErrorCodeParse = 1,
    ARILabelScriptErrorCodeValidation = 2,
};

@implementation ARILabelScriptCompiler

+ (NSError *)_errorWithCode:(ARILabelScriptErrorCode)code description:(NSString *)description {
    return [NSError errorWithDomain:ARILabelScriptErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: description ?: @"알 수 없는 오류" }];
}

+ (BOOL)_validateHourValue:(id)value path:(NSString *)path error:(NSError **)error {
    if(![value respondsToSelector:@selector(doubleValue)]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be a number.", path]];
        return NO;
    }

    double hour = [value doubleValue];
    if(hour < 0.0 || hour > 24.0) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be between 0 and 24.", path]];
        return NO;
    }

    return YES;
}

+ (BOOL)_validateNumericValue:(id)value path:(NSString *)path error:(NSError **)error {
    if(![value respondsToSelector:@selector(doubleValue)]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be a number.", path]];
        return NO;
    }

    return YES;
}

+ (BOOL)_validatePercentageValue:(id)value path:(NSString *)path error:(NSError **)error {
    if(![self _validateNumericValue:value path:path error:error]) {
        return NO;
    }

    double percentage = [value doubleValue];
    if(percentage < 0.0 || percentage > 100.0) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be between 0 and 100.", path]];
        return NO;
    }

    return YES;
}

+ (BOOL)_validateNonEmptyString:(id)value path:(NSString *)path error:(NSError **)error {
    if(![value isKindOfClass:[NSString class]] || [((NSString *)value) length] == 0) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be a non-empty string.", path]];
        return NO;
    }

    return YES;
}

+ (BOOL)_validateBlock:(NSDictionary *)block path:(NSString *)path error:(NSError **)error {
    if(![block isKindOfClass:[NSDictionary class]]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be a dictionary.", path]];
        return NO;
    }

    NSString *type = [block[@"type"] isKindOfClass:[NSString class]] ? block[@"type"] : nil;
    if(type.length == 0) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ is missing a string `type`.", path]];
        return NO;
    }

    if([type isEqualToString:@"set_text"]) {
        if(![block[@"text"] isKindOfClass:[NSString class]]) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.text must be a string.", path]];
            return NO;
        }
        return YES;
    }

    if([type isEqualToString:@"wait"]) {
        id seconds = block[@"seconds"];
        if(![seconds respondsToSelector:@selector(doubleValue)]) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.seconds must be a number.", path]];
            return NO;
        }

        if([seconds doubleValue] < 0.0) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.seconds cannot be negative.", path]];
            return NO;
        }
        return YES;
    }

    if([type isEqualToString:@"reload"]) {
        return YES;
    }

    if([type isEqualToString:@"if"]) {
        NSDictionary *condition = [block[@"condition"] isKindOfClass:[NSDictionary class]] ? block[@"condition"] : nil;
        NSArray *thenSteps = [block[@"then"] isKindOfClass:[NSArray class]] ? block[@"then"] : nil;
        NSArray *elseSteps = [block[@"else"] isKindOfClass:[NSArray class]] ? block[@"else"] : nil;
        if(!condition) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.condition must be a dictionary.", path]];
            return NO;
        }

        if(!thenSteps && !elseSteps) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@ must contain `then` or `else`.", path]];
            return NO;
        }

        if(![self _validateCondition:condition path:[path stringByAppendingString:@".condition"] error:error]) return NO;
        if(thenSteps && ![self _validateSteps:thenSteps path:[path stringByAppendingString:@".then"] error:error]) return NO;
        if(elseSteps && ![self _validateSteps:elseSteps path:[path stringByAppendingString:@".else"] error:error]) return NO;
        return YES;
    }

    if([type isEqualToString:@"repeat"]) {
        NSArray *steps = [block[@"steps"] isKindOfClass:[NSArray class]] ? block[@"steps"] : nil;
        if(!steps) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.steps must be an array.", path]];
            return NO;
        }

        id times = block[@"times"];
        if(times && ![times respondsToSelector:@selector(integerValue)]) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.times must be a number when provided.", path]];
            return NO;
        }

        return [self _validateSteps:steps path:[path stringByAppendingString:@".steps"] error:error];
    }

    if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                 description:[NSString stringWithFormat:@"%@ has unsupported type `%@`.", path, type]];
    return NO;
}

+ (BOOL)_validateSteps:(NSArray *)steps path:(NSString *)path error:(NSError **)error {
    if(![steps isKindOfClass:[NSArray class]]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be an array.", path]];
        return NO;
    }

    for(NSUInteger i = 0; i < steps.count; i++) {
        if(![self _validateBlock:steps[i] path:[NSString stringWithFormat:@"%@[%lu]", path, (unsigned long)i] error:error]) {
            return NO;
        }
    }

    return YES;
}

+ (BOOL)_validateCondition:(NSDictionary *)condition path:(NSString *)path error:(NSError **)error {
    if(![condition isKindOfClass:[NSDictionary class]]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be a dictionary.", path]];
        return NO;
    }

    NSString *type = [condition[@"type"] isKindOfClass:[NSString class]] ? condition[@"type"] : @"always";

    if([type isEqualToString:@"always"]) {
        return YES;
    }

    if([type isEqualToString:@"hour_between"]) {
        if(![self _validateHourValue:condition[@"start"] path:[path stringByAppendingString:@".start"] error:error]) return NO;
        if(![self _validateHourValue:condition[@"end"] path:[path stringByAppendingString:@".end"] error:error]) return NO;
        return YES;
    }

    if([type isEqualToString:@"weekday_is"]) {
        NSArray *days = [condition[@"days"] isKindOfClass:[NSArray class]] ? condition[@"days"] : nil;
        if(days.count == 0) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.days must be a non-empty array.", path]];
            return NO;
        }

        for(NSUInteger i = 0; i < days.count; i++) {
            id day = days[i];
            if(![day respondsToSelector:@selector(integerValue)]) {
                if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                             description:[NSString stringWithFormat:@"%@.days[%lu] must be a number.", path, (unsigned long)i]];
                return NO;
            }

            NSInteger value = [day integerValue];
            if(value < 1 || value > 7) {
                if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                             description:[NSString stringWithFormat:@"%@.days[%lu] must be between 1 and 7.", path, (unsigned long)i]];
                return NO;
            }
        }
        return YES;
    }

    if([type isEqualToString:@"location_contains"] || [type isEqualToString:@"weather_contains"]) {
        return [self _validateNonEmptyString:condition[@"query"] path:[path stringByAppendingString:@".query"] error:error];
    }

    if([type isEqualToString:@"temperature_above"] || [type isEqualToString:@"temperature_below"]) {
        return [self _validateNumericValue:condition[@"value"] path:[path stringByAppendingString:@".value"] error:error];
    }

    if([type isEqualToString:@"battery_above"] || [type isEqualToString:@"battery_below"]) {
        return [self _validatePercentageValue:condition[@"value"] path:[path stringByAppendingString:@".value"] error:error];
    }

    if([type isEqualToString:@"battery_charging"] || [type isEqualToString:@"battery_connected"]) {
        return YES;
    }

    if([type isEqualToString:@"and"] || [type isEqualToString:@"or"]) {
        NSArray *conditions = [condition[@"conditions"] isKindOfClass:[NSArray class]] ? condition[@"conditions"] : nil;
        if(conditions.count == 0) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.conditions must be a non-empty array.", path]];
            return NO;
        }

        for(NSUInteger i = 0; i < conditions.count; i++) {
            if(![self _validateCondition:conditions[i]
                                    path:[NSString stringWithFormat:@"%@.conditions[%lu]", path, (unsigned long)i]
                                   error:error]) {
                return NO;
            }
        }
        return YES;
    }

    if([type isEqualToString:@"not"]) {
        NSDictionary *nested = [condition[@"condition"] isKindOfClass:[NSDictionary class]] ? condition[@"condition"] : nil;
        if(!nested) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.condition must be a dictionary.", path]];
            return NO;
        }
        return [self _validateCondition:nested path:[path stringByAppendingString:@".condition"] error:error];
    }

    if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                 description:[NSString stringWithFormat:@"%@ has unsupported condition type `%@`.", path, type]];
    return NO;
}

+ (nullable NSDictionary *)scriptDictionaryFromSource:(NSString *)source error:(NSError **)error {
    NSString *normalizedSource = [source isKindOfClass:[NSString class]] ? source : @"";
    normalizedSource = [normalizedSource stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(normalizedSource.length == 0) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeParse description:@"Script source is empty."];
        return nil;
    }

    NSData *data = [normalizedSource dataUsingEncoding:NSUTF8StringEncoding];
    if(!data) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeParse description:@"Failed to encode script source as UTF-8."];
        return nil;
    }

    NSError *plistError = nil;
    NSPropertyListFormat format = NSPropertyListOpenStepFormat;
    id object = [NSPropertyListSerialization propertyListWithData:data
                                                          options:NSPropertyListMutableContainersAndLeaves
                                                           format:&format
                                                            error:&plistError];
    if(!object) {
        NSError *jsonError = nil;
        object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
        if(!object) {
            if(error) *error = plistError ?: jsonError ?: [self _errorWithCode:ARILabelScriptErrorCodeParse description:@"Failed to parse script source."];
            return nil;
        }
    }

    NSMutableDictionary *dictionary = nil;
    if([object isKindOfClass:[NSArray class]]) {
        dictionary = [@{ @"loop": @YES, @"steps": object } mutableCopy];
    } else if([object isKindOfClass:[NSDictionary class]]) {
        dictionary = [object mutableCopy];
    } else {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeParse description:@"Script root must be a dictionary or array."];
        return nil;
    }

    if(![dictionary[@"steps"] isKindOfClass:[NSArray class]] && [dictionary[@"actions"] isKindOfClass:[NSArray class]]) {
        dictionary[@"steps"] = dictionary[@"actions"];
    }

    if(!dictionary[@"loop"]) {
        dictionary[@"loop"] = @YES;
    }

    if(![self validateScriptDictionary:dictionary error:error]) {
        return nil;
    }

    return [dictionary copy];
}

+ (nullable NSMutableDictionary *)mutableScriptDictionaryFromSource:(NSString *)source error:(NSError **)error {
    NSDictionary *script = [self scriptDictionaryFromSource:source error:error];
    if(!script) {
        return nil;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:script options:0 error:error];
    if(!data) {
        return nil;
    }

    id mutableObject = [NSJSONSerialization JSONObjectWithData:data
                                                       options:NSJSONReadingMutableContainers
                                                         error:error];
    if(![mutableObject isKindOfClass:[NSMutableDictionary class]]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeParse description:@"Failed to create mutable script dictionary."];
        return nil;
    }

    return mutableObject;
}

+ (BOOL)validateScriptDictionary:(NSDictionary *)script error:(NSError **)error {
    if(![script isKindOfClass:[NSDictionary class]]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation description:@"Script root must be a dictionary."];
        return NO;
    }

    NSArray *steps = [script[@"steps"] isKindOfClass:[NSArray class]] ? script[@"steps"] : nil;
    if(!steps) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation description:@"Script root must contain an array `steps`."];
        return NO;
    }

    id loopValue = script[@"loop"];
    if(loopValue && ![loopValue respondsToSelector:@selector(boolValue)]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation description:@"`loop` must be a boolean or number."];
        return NO;
    }

    return [self _validateSteps:steps path:@"steps" error:error];
}

+ (nullable NSString *)sourceFromScriptDictionary:(NSDictionary *)script error:(NSError **)error {
    if(![self validateScriptDictionary:script error:error]) {
        return nil;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:script
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
    if(!data) {
        return nil;
    }

    NSString *source = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if(!source && error) {
        *error = [self _errorWithCode:ARILabelScriptErrorCodeParse description:@"Failed to encode script dictionary as UTF-8."];
    }
    return source;
}

+ (NSString *)defaultScriptSource {
    NSDictionary *(^setText)(NSString *) = ^NSDictionary *(NSString *text) {
        return @{
            @"type": @"set_text",
            @"text": text ?: @""
        };
    };

    NSDictionary *(^wait)(NSNumber *) = ^NSDictionary *(NSNumber *seconds) {
        return @{
            @"type": @"wait",
            @"seconds": seconds ?: @0
        };
    };

    NSDictionary *(^repeatBlock)(NSNumber *, NSArray<NSDictionary *> *) = ^NSDictionary *(NSNumber *times, NSArray<NSDictionary *> *steps) {
        return @{
            @"type": @"repeat",
            @"times": times ?: @1,
            @"steps": steps ?: @[]
        };
    };

    NSDictionary *(^ifBlock)(NSDictionary *, NSArray<NSDictionary *> *, NSArray<NSDictionary *> *) = ^NSDictionary *(NSDictionary *condition, NSArray<NSDictionary *> *thenSteps, NSArray<NSDictionary *> *elseSteps) {
        NSMutableDictionary *block = [@{
            @"type": @"if",
            @"condition": condition ?: @{ @"type": @"always" },
            @"then": thenSteps ?: @[]
        } mutableCopy];
        if(elseSteps) {
            block[@"else"] = elseSteps;
        }
        return [block copy];
    };

    NSDictionary *fallbackBranch = repeatBlock(@2, @[
        setText(@"%인삿말_한%"),
        wait(@1.8),
        setText(@"%DAY% | %TIME%"),
        wait(@1.8),
        setText(@"%LOCATION% | %TEMPERATURE%"),
        wait(@2.0)
    ]);

    NSDictionary *morningWorkBranch = ifBlock(@{
        @"type": @"and",
        @"conditions": @[
            @{ @"type": @"hour_between", @"start": @6, @"end": @10.5 },
            @{ @"type": @"weekday_is", @"days": @[ @2, @3, @4, @5, @6 ] }
        ]
    }, @[
        repeatBlock(@2, @[
            setText(@"%인삿말_한%"),
            wait(@1.8),
            setText(@"%DAY% | %TIME%"),
            wait(@1.8),
            setText(@"%LOCATION% | %TEMPERATURE%"),
            wait(@2.0)
        ])
    ], @[
        fallbackBranch
    ]);

    NSDictionary *rainBranch = ifBlock(@{
        @"type": @"or",
        @"conditions": @[
            @{ @"type": @"weather_contains", @"query": @"비" },
            @{ @"type": @"weather_contains", @"query": @"rain" }
        ]
    }, @[
        repeatBlock(@2, @[
            setText(@"%LOCATION% | %TEMPERATURE%"),
            wait(@1.8),
            setText(@"%DAY% | %TIME%"),
            wait(@2.0)
        ])
    ], @[
        morningWorkBranch
    ]);

    NSDictionary *chargingBranch = ifBlock(@{
        @"type": @"battery_charging"
    }, @[
        repeatBlock(@2, @[
            setText(@"%BATTERY% | 충전 중"),
            wait(@1.8),
            setText(@"%DAY% | %TIME%"),
            wait(@1.8),
            setText(@"%LOCATION% | %TEMPERATURE%"),
            wait(@2.0)
        ])
    ], @[
        rainBranch
    ]);

    NSDictionary *lowBatteryBranch = ifBlock(@{
        @"type": @"battery_below",
        @"value": @20
    }, @[
        repeatBlock(@2, @[
            setText(@"%TIME% | 배터리 %BATTERY%"),
            wait(@1.8),
            setText(@"%LOCATION% | %TEMPERATURE%"),
            wait(@2.0)
        ])
    ], @[
        chargingBranch
    ]);

    NSDictionary *script = @{
        @"loop": @YES,
        @"steps": @[
            lowBatteryBranch
        ]
    };

    return [self sourceFromScriptDictionary:script error:nil] ?: @"{\"loop\":true,\"steps\":[]}";
}

@end

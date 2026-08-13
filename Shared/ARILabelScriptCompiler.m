//
// Shared label script parser/validator.
//

#import "ARILabelScriptCompiler.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

NSString *const ARILabelScriptErrorDomain = @"me.lau.Atria.LabelScript";
NSUInteger const ARILabelScriptMaximumSourceBytes = 256 * 1024;
NSUInteger const ARILabelScriptMaximumBlocks = 2048;
NSUInteger const ARILabelScriptMaximumConditions = 1024;
NSUInteger const ARILabelScriptMaximumNestingDepth = 32;
NSUInteger const ARILabelScriptMaximumStepsPerContainer = 512;
NSUInteger const ARILabelScriptMaximumTextLength = 4096;
NSUInteger const ARILabelScriptMaximumQueryLength = 256;
NSTimeInterval const ARILabelScriptMaximumWaitSeconds = 24.0 * 60.0 * 60.0;
NSInteger const ARILabelScriptMaximumRepeatCount = 10000;

typedef NS_ENUM(NSInteger, ARILabelScriptErrorCode) {
    ARILabelScriptErrorCodeParse = 1,
    ARILabelScriptErrorCodeValidation = 2,
};

@interface ARILabelScriptValidationState : NSObject
@property (nonatomic, assign) NSUInteger blockCount;
@property (nonatomic, assign) NSUInteger conditionCount;
@end

@implementation ARILabelScriptValidationState
@end

@interface ARILabelScriptCompiler ()
+ (BOOL)_validateSteps:(NSArray *)steps
                  path:(NSString *)path
                 depth:(NSUInteger)depth
                 state:(ARILabelScriptValidationState *)state
                 error:(NSError **)error;
+ (BOOL)_validateCondition:(NSDictionary *)condition
                      path:(NSString *)path
                     depth:(NSUInteger)depth
                     state:(ARILabelScriptValidationState *)state
                     error:(NSError **)error;
@end

@implementation ARILabelScriptCompiler

+ (NSError *)_errorWithCode:(ARILabelScriptErrorCode)code description:(NSString *)description {
    return [NSError errorWithDomain:ARILabelScriptErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: description ?: @"알 수 없는 오류" }];
}

+ (BOOL)_readFiniteDouble:(id)value result:(double *)result {
    double number = 0.0;
    if([value isKindOfClass:[NSNumber class]]) {
        if(CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
            return NO;
        }
        number = [value doubleValue];
    } else if([value isKindOfClass:[NSString class]]) {
        // OpenStep property lists represent scalar values as strings. Accept those
        // for source compatibility, but reject partial values such as "12px".
        NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if(text.length == 0) return NO;
        NSScanner *scanner = [NSScanner scannerWithString:text];
        scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        if(![scanner scanDouble:&number] || ![scanner isAtEnd]) return NO;
    } else {
        return NO;
    }

    if(!isfinite(number)) return NO;
    if(result) *result = number;
    return YES;
}

+ (BOOL)_readInteger:(id)value result:(NSInteger *)result {
    double number = 0.0;
    if(![self _readFiniteDouble:value result:&number] || trunc(number) != number ||
       number < -1000000000.0 || number > 1000000000.0) {
        return NO;
    }
    if(result) *result = (NSInteger)number;
    return YES;
}

+ (BOOL)_readBoolean:(id)value result:(BOOL *)result {
    if([value isKindOfClass:[NSNumber class]]) {
        double number = [value doubleValue];
        if(!isfinite(number) || (number != 0.0 && number != 1.0)) return NO;
        if(result) *result = number != 0.0;
        return YES;
    }
    if([value isKindOfClass:[NSString class]]) {
        NSString *text = [[(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        if([text isEqualToString:@"yes"] || [text isEqualToString:@"true"] || [text isEqualToString:@"1"]) {
            if(result) *result = YES;
            return YES;
        }
        if([text isEqualToString:@"no"] || [text isEqualToString:@"false"] || [text isEqualToString:@"0"]) {
            if(result) *result = NO;
            return YES;
        }
    }
    return NO;
}

+ (BOOL)_validateDouble:(id)value
                    path:(NSString *)path
                 minimum:(double)minimum
                 maximum:(double)maximum
                   error:(NSError **)error {
    double number = 0.0;
    if(![self _readFiniteDouble:value result:&number]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be a finite number.", path]];
        return NO;
    }
    if(number < minimum || number > maximum) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be between %g and %g.", path, minimum, maximum]];
        return NO;
    }
    return YES;
}

+ (BOOL)_validateNonEmptyString:(id)value maximumLength:(NSUInteger)maximumLength path:(NSString *)path error:(NSError **)error {
    if(![value isKindOfClass:[NSString class]] || [((NSString *)value) length] == 0) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be a non-empty string.", path]];
        return NO;
    }
    if([((NSString *)value) length] > maximumLength) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ exceeds the %lu-character limit.", path, (unsigned long)maximumLength]];
        return NO;
    }
    return YES;
}

+ (BOOL)_validateBlock:(NSDictionary *)block
                   path:(NSString *)path
                  depth:(NSUInteger)depth
                  state:(ARILabelScriptValidationState *)state
                  error:(NSError **)error {
    if(![block isKindOfClass:[NSDictionary class]]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be a dictionary.", path]];
        return NO;
    }

    state.blockCount++;
    if(state.blockCount > ARILabelScriptMaximumBlocks) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"Script exceeds the %lu-block limit.", (unsigned long)ARILabelScriptMaximumBlocks]];
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
        if([block[@"text"] length] > ARILabelScriptMaximumTextLength) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.text exceeds the %lu-character limit.", path, (unsigned long)ARILabelScriptMaximumTextLength]];
            return NO;
        }
        return YES;
    }

    if([type isEqualToString:@"wait"]) {
        return [self _validateDouble:block[@"seconds"]
                                path:[path stringByAppendingString:@".seconds"]
                             minimum:0.0
                             maximum:ARILabelScriptMaximumWaitSeconds
                               error:error];
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

        if(![self _validateCondition:condition path:[path stringByAppendingString:@".condition"] depth:0 state:state error:error]) return NO;
        if(thenSteps && ![self _validateSteps:thenSteps path:[path stringByAppendingString:@".then"] depth:depth + 1 state:state error:error]) return NO;
        if(elseSteps && ![self _validateSteps:elseSteps path:[path stringByAppendingString:@".else"] depth:depth + 1 state:state error:error]) return NO;
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
        NSInteger repeatCount = 0;
        if(times && ![self _readInteger:times result:&repeatCount]) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.times must be an integer when provided.", path]];
            return NO;
        }
        if(repeatCount < 0 || repeatCount > ARILabelScriptMaximumRepeatCount) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.times must be 0 (infinite) or between 1 and %ld.", path, (long)ARILabelScriptMaximumRepeatCount]];
            return NO;
        }

        return [self _validateSteps:steps path:[path stringByAppendingString:@".steps"] depth:depth + 1 state:state error:error];
    }

    if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                 description:[NSString stringWithFormat:@"%@ has unsupported type `%@`.", path, type]];
    return NO;
}

+ (BOOL)_validateSteps:(NSArray *)steps
                  path:(NSString *)path
                 depth:(NSUInteger)depth
                 state:(ARILabelScriptValidationState *)state
                 error:(NSError **)error {
    if(![steps isKindOfClass:[NSArray class]]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be an array.", path]];
        return NO;
    }

    if(depth > ARILabelScriptMaximumNestingDepth) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ exceeds the maximum nesting depth of %lu.", path, (unsigned long)ARILabelScriptMaximumNestingDepth]];
        return NO;
    }
    if(steps.count > ARILabelScriptMaximumStepsPerContainer) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ exceeds the %lu-step container limit.", path, (unsigned long)ARILabelScriptMaximumStepsPerContainer]];
        return NO;
    }

    for(NSUInteger i = 0; i < steps.count; i++) {
        if(![self _validateBlock:steps[i]
                           path:[NSString stringWithFormat:@"%@[%lu]", path, (unsigned long)i]
                          depth:depth
                          state:state
                          error:error]) {
            return NO;
        }
    }

    return YES;
}

+ (BOOL)_validateCondition:(NSDictionary *)condition
                      path:(NSString *)path
                     depth:(NSUInteger)depth
                     state:(ARILabelScriptValidationState *)state
                     error:(NSError **)error {
    if(![condition isKindOfClass:[NSDictionary class]]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ must be a dictionary.", path]];
        return NO;
    }

    if(depth > ARILabelScriptMaximumNestingDepth) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"%@ exceeds the maximum condition depth of %lu.", path, (unsigned long)ARILabelScriptMaximumNestingDepth]];
        return NO;
    }
    state.conditionCount++;
    if(state.conditionCount > ARILabelScriptMaximumConditions) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                     description:[NSString stringWithFormat:@"Script exceeds the %lu-condition limit.", (unsigned long)ARILabelScriptMaximumConditions]];
        return NO;
    }

    NSString *type = [condition[@"type"] isKindOfClass:[NSString class]] ? condition[@"type"] : @"always";

    if([type isEqualToString:@"always"]) {
        return YES;
    }

    if([type isEqualToString:@"hour_between"]) {
        if(![self _validateDouble:condition[@"start"] path:[path stringByAppendingString:@".start"] minimum:0.0 maximum:24.0 error:error]) return NO;
        if(![self _validateDouble:condition[@"end"] path:[path stringByAppendingString:@".end"] minimum:0.0 maximum:24.0 error:error]) return NO;
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
            NSInteger value = 0;
            if(![self _readInteger:days[i] result:&value]) {
                if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                             description:[NSString stringWithFormat:@"%@.days[%lu] must be an integer.", path, (unsigned long)i]];
                return NO;
            }
            if(value < 1 || value > 7) {
                if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                             description:[NSString stringWithFormat:@"%@.days[%lu] must be between 1 and 7.", path, (unsigned long)i]];
                return NO;
            }
        }
        return YES;
    }

    if([type isEqualToString:@"location_contains"] || [type isEqualToString:@"weather_contains"]) {
        return [self _validateNonEmptyString:condition[@"query"] maximumLength:ARILabelScriptMaximumQueryLength path:[path stringByAppendingString:@".query"] error:error];
    }

    if([type isEqualToString:@"temperature_above"] || [type isEqualToString:@"temperature_below"]) {
        return [self _validateDouble:condition[@"value"] path:[path stringByAppendingString:@".value"] minimum:-273.15 maximum:1000.0 error:error];
    }

    if([type isEqualToString:@"battery_above"] || [type isEqualToString:@"battery_below"]) {
        return [self _validateDouble:condition[@"value"] path:[path stringByAppendingString:@".value"] minimum:0.0 maximum:100.0 error:error];
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
        if(conditions.count > ARILabelScriptMaximumStepsPerContainer) {
            if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation
                                         description:[NSString stringWithFormat:@"%@.conditions exceeds the %lu-item limit.", path, (unsigned long)ARILabelScriptMaximumStepsPerContainer]];
            return NO;
        }

        for(NSUInteger i = 0; i < conditions.count; i++) {
            if(![self _validateCondition:conditions[i]
                                    path:[NSString stringWithFormat:@"%@.conditions[%lu]", path, (unsigned long)i]
                                   depth:depth + 1
                                   state:state
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
        return [self _validateCondition:nested path:[path stringByAppendingString:@".condition"] depth:depth + 1 state:state error:error];
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
    if(data.length > ARILabelScriptMaximumSourceBytes) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeParse
                                     description:[NSString stringWithFormat:@"Script source exceeds the %lu-byte limit.", (unsigned long)ARILabelScriptMaximumSourceBytes]];
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

    BOOL loop = YES;
    [self _readBoolean:dictionary[@"loop"] result:&loop];
    dictionary[@"loop"] = @(loop);

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
    if(loopValue && ![self _readBoolean:loopValue result:nil]) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeValidation description:@"`loop` must be true/false (YES/NO and 1/0 are also accepted)."];
        return NO;
    }

    ARILabelScriptValidationState *state = [ARILabelScriptValidationState new];
    return [self _validateSteps:steps path:@"steps" depth:0 state:state error:error];
}

+ (BOOL)_stepsGuaranteeYield:(NSArray *)steps {
    for(NSDictionary *block in steps) {
        if(![block isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = [block[@"type"] isKindOfClass:[NSString class]] ? block[@"type"] : @"";
        if([type isEqualToString:@"wait"]) return YES;
        if([type isEqualToString:@"reload"]) return NO;
        if([type isEqualToString:@"repeat"] && [self _stepsGuaranteeYield:[block[@"steps"] isKindOfClass:[NSArray class]] ? block[@"steps"] : @[]]) return YES;
        if([type isEqualToString:@"if"]) {
            NSArray *thenSteps = [block[@"then"] isKindOfClass:[NSArray class]] ? block[@"then"] : @[];
            NSArray *elseSteps = [block[@"else"] isKindOfClass:[NSArray class]] ? block[@"else"] : nil;
            if(elseSteps && [self _stepsGuaranteeYield:thenSteps] && [self _stepsGuaranteeYield:elseSteps]) return YES;
        }
    }
    return NO;
}

+ (void)_appendDiagnosticsForSteps:(NSArray *)steps path:(NSString *)path warnings:(NSMutableArray<NSString *> *)warnings {
    for(NSUInteger index = 0; index < steps.count; index++) {
        NSDictionary *block = [steps[index] isKindOfClass:[NSDictionary class]] ? steps[index] : nil;
        if(!block) continue;
        NSString *blockPath = [NSString stringWithFormat:@"%@[%lu]", path, (unsigned long)index];
        NSString *type = [block[@"type"] isKindOfClass:[NSString class]] ? block[@"type"] : @"";

        if([type isEqualToString:@"repeat"]) {
            NSArray *nested = [block[@"steps"] isKindOfClass:[NSArray class]] ? block[@"steps"] : @[];
            NSInteger times = 0;
            [self _readInteger:block[@"times"] result:&times];
            if(nested.count == 0) {
                [warnings addObject:[NSString stringWithFormat:@"%@ 반복 내용이 비어 있습니다.", blockPath]];
            } else if(times == 0 && ![self _stepsGuaranteeYield:nested]) {
                [warnings addObject:[NSString stringWithFormat:@"%@ 무한 반복의 일부 경로에 wait가 없어 실행 예산에 의해 주기적으로 중단될 수 있습니다.", blockPath]];
            }
            [self _appendDiagnosticsForSteps:nested path:[blockPath stringByAppendingString:@".steps"] warnings:warnings];
        } else if([type isEqualToString:@"if"]) {
            NSArray *thenSteps = [block[@"then"] isKindOfClass:[NSArray class]] ? block[@"then"] : @[];
            NSArray *elseSteps = [block[@"else"] isKindOfClass:[NSArray class]] ? block[@"else"] : nil;
            if(thenSteps.count == 0) {
                [warnings addObject:[NSString stringWithFormat:@"%@ 참 분기가 비어 있습니다.", blockPath]];
            }
            if(elseSteps && elseSteps.count == 0) {
                [warnings addObject:[NSString stringWithFormat:@"%@ 거짓 분기가 비어 있습니다.", blockPath]];
            }
            [self _appendDiagnosticsForSteps:thenSteps path:[blockPath stringByAppendingString:@".then"] warnings:warnings];
            if(elseSteps) [self _appendDiagnosticsForSteps:elseSteps path:[blockPath stringByAppendingString:@".else"] warnings:warnings];
        }
    }
}

+ (NSArray<NSString *> *)diagnosticsForScriptDictionary:(NSDictionary *)script {
    NSError *error = nil;
    if(![self validateScriptDictionary:script error:&error]) {
        return @[ error.localizedDescription ?: @"스크립트가 유효하지 않습니다." ];
    }

    NSArray *steps = script[@"steps"];
    NSMutableArray<NSString *> *warnings = [NSMutableArray new];
    if(steps.count == 0) {
        [warnings addObject:@"실행할 액션이 없습니다."];
    }
    BOOL loop = YES;
    [self _readBoolean:script[@"loop"] ?: @YES result:&loop];
    if(loop && steps.count > 0 && ![self _stepsGuaranteeYield:steps]) {
        [warnings addObject:@"일부 실행 경로가 wait 없이 루프되어 SpringBoard 실행 예산을 계속 소모할 수 있습니다."];
    }
    [self _appendDiagnosticsForSteps:steps path:@"steps" warnings:warnings];
    return warnings;
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
    if(data.length > ARILabelScriptMaximumSourceBytes) {
        if(error) *error = [self _errorWithCode:ARILabelScriptErrorCodeParse
                                     description:[NSString stringWithFormat:@"Serialized script exceeds the %lu-byte limit.", (unsigned long)ARILabelScriptMaximumSourceBytes]];
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

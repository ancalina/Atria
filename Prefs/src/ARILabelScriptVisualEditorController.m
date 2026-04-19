//
// Visual editor for label scripts.
//

#include <math.h>

#import "ARILabelScriptVisualEditorController.h"
#import "../../Shared/ARILabelScriptCompiler.h"
#import "../../Shared/ARISharedConstants.h"

typedef void (^ARILabelScriptTimePickerCompletion)(double value);
typedef void (^ARILabelScriptWeekdayPickerCompletion)(NSArray<NSNumber *> *days);
typedef void (^ARILabelScriptConditionApplyHandler)(NSMutableDictionary *condition);
typedef void (^ARILabelScriptActionSelectionHandler)(NSString *type);
typedef void (^ARILabelScriptConditionSelectionHandler)(NSString *type);
typedef NSMutableDictionary * _Nonnull (^ARILabelScriptActionFactory)(void);
typedef NSMutableDictionary * _Nonnull (^ARILabelScriptConditionFactory)(void);
typedef NSString * _Nonnull (^ARILabelScriptConditionSummaryBuilder)(NSDictionary *condition);

static NSDictionary *ARILabelScriptInlineActionDefinition(NSString *type);
static NSMutableDictionary *ARILabelScriptInlineDefaultBlock(NSString *type);
static NSDictionary *ARILabelScriptInlineConditionDefinition(NSString *type);
static NSMutableDictionary *ARILabelScriptInlineDefaultCondition(NSString *type);
static NSString *ARILabelScriptInlineConditionSummary(NSDictionary *condition);

typedef NS_ENUM(NSInteger, ARILabelScriptVisualRowKind) {
    ARILabelScriptVisualRowKindAction = 0,
    ARILabelScriptVisualRowKindGroup,
    ARILabelScriptVisualRowKindInsert,
    ARILabelScriptVisualRowKindEnd,
    ARILabelScriptVisualRowKindEmpty,
};

typedef NS_ENUM(NSInteger, ARILabelScriptVisualAccessoryKind) {
    ARILabelScriptVisualAccessoryKindNone = 0,
    ARILabelScriptVisualAccessoryKindMenu,
    ARILabelScriptVisualAccessoryKindInsert,
};

typedef NS_ENUM(NSInteger, ARILabelScriptVisualRailMode) {
    ARILabelScriptVisualRailModeNone = 0,
    ARILabelScriptVisualRailModeStart,
    ARILabelScriptVisualRailModeEnd,
};

static CGFloat const kARILabelScriptIndentStep = 24.0;
static CGFloat const kARILabelScriptPanelLeadingBase = 18.0;
static CGFloat const kARILabelScriptRailLeadingBase = 6.0;

static NSString *ARILabelScriptInlineFormattedTimeValue(double value) {
    NSInteger totalMinutes = (NSInteger)llround(value * 60.0);
    if(totalMinutes < 0) totalMinutes = 0;
    if(totalMinutes > 24 * 60) totalMinutes = 24 * 60;

    NSInteger hours = totalMinutes / 60;
    NSInteger minutes = totalMinutes % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)hours, (long)minutes];
}

static NSDate *ARILabelScriptInlineDateFromTimeValue(double value) {
    NSInteger totalMinutes = (NSInteger)llround(value * 60.0);
    if(totalMinutes < 0) totalMinutes = 0;
    if(totalMinutes >= 24 * 60) totalMinutes = 0;

    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.hour = totalMinutes / 60;
    components.minute = totalMinutes % 60;
    return [[NSCalendar currentCalendar] dateFromComponents:components] ?: [NSDate date];
}

static double ARILabelScriptInlineTimeValueFromDate(NSDate *date) {
    NSDateComponents *components = [[NSCalendar currentCalendar] components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                                                   fromDate:date ?: [NSDate date]];
    return (double)components.hour + ((double)components.minute / 60.0);
}

static NSString *ARILabelScriptInlineFormattedMetricValue(double value, NSString *suffix) {
    double roundedValue = round(value);
    if(fabs(value - roundedValue) < 0.01) {
        return [NSString stringWithFormat:@"%ld%@", (long)roundedValue, suffix ?: @""];
    }
    return [NSString stringWithFormat:@"%.1f%@", value, suffix ?: @""];
}

static NSString *ARILabelScriptInlineWeekdayTitle(NSInteger weekday) {
    switch(weekday) {
        case 1: return @"일요일";
        case 2: return @"월요일";
        case 3: return @"화요일";
        case 4: return @"수요일";
        case 5: return @"목요일";
        case 6: return @"금요일";
        case 7: return @"토요일";
        default: return [NSString stringWithFormat:@"%ld", (long)weekday];
    }
}

static NSString *ARILabelScriptInlineWeekdayShortTitle(NSInteger weekday) {
    switch(weekday) {
        case 1: return @"일";
        case 2: return @"월";
        case 3: return @"화";
        case 4: return @"수";
        case 5: return @"목";
        case 6: return @"금";
        case 7: return @"토";
        default: return [NSString stringWithFormat:@"%ld", (long)weekday];
    }
}

static NSArray<NSNumber *> *ARILabelScriptInlineSortedDays(NSArray *days) {
    NSMutableOrderedSet<NSNumber *> *orderedSet = [NSMutableOrderedSet orderedSet];
    for(id value in days) {
        if([value respondsToSelector:@selector(integerValue)]) {
            NSInteger day = [value integerValue];
            if(day >= 1 && day <= 7) {
                [orderedSet addObject:@(day)];
            }
        }
    }
    return [[orderedSet array] sortedArrayUsingSelector:@selector(compare:)];
}

static NSString *ARILabelScriptInlineWeekdaySummary(NSArray *days) {
    NSArray<NSNumber *> *sortedDays = ARILabelScriptInlineSortedDays(days);
    if(sortedDays.count == 0) {
        return @"선택 안 함";
    }

    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:sortedDays.count];
    for(NSNumber *day in sortedDays) {
        [titles addObject:ARILabelScriptInlineWeekdayShortTitle(day.integerValue)];
    }
    return [titles componentsJoinedByString:@", "];
}

static NSMutableDictionary *ARILabelScriptInlineDefaultCondition(NSString *type) {
    NSDictionary *definition = ARILabelScriptInlineConditionDefinition(type);
    ARILabelScriptConditionFactory factory = definition[@"factory"];
    if(factory) {
        NSMutableDictionary *condition = factory();
        if([condition isKindOfClass:[NSMutableDictionary class]]) {
            return condition;
        }
        if([condition isKindOfClass:[NSDictionary class]]) {
            return [condition mutableCopy];
        }
    }
    return [@{ @"type": @"always" } mutableCopy];
}

static NSMutableDictionary *ARILabelScriptInlineDefaultBlock(NSString *type) {
    NSDictionary *definition = ARILabelScriptInlineActionDefinition(type);
    ARILabelScriptActionFactory factory = definition[@"factory"];
    if(factory) {
        NSMutableDictionary *block = factory();
        if([block isKindOfClass:[NSMutableDictionary class]]) {
            return block;
        }
        if([block isKindOfClass:[NSDictionary class]]) {
            return [block mutableCopy];
        }
    }
    return [@{ @"type": @"set_text", @"text": @"새 텍스트" } mutableCopy];
}

static NSMutableArray *ARILabelScriptInlineMutableArrayValue(id value) {
    if([value isKindOfClass:[NSMutableArray class]]) {
        return value;
    }
    if([value isKindOfClass:[NSArray class]]) {
        return [value mutableCopy];
    }
    return [NSMutableArray new];
}

static NSMutableDictionary *ARILabelScriptInlineMutableDictionaryValue(id value) {
    if([value isKindOfClass:[NSMutableDictionary class]]) {
        return value;
    }
    if([value isKindOfClass:[NSDictionary class]]) {
        return [value mutableCopy];
    }
    return [NSMutableDictionary new];
}

static NSMutableArray *ARILabelScriptInlineEnsureMutableArray(NSMutableDictionary *owner, NSString *key) {
    NSMutableArray *array = ARILabelScriptInlineMutableArrayValue(owner[key]);
    owner[key] = array;
    return array;
}

static NSMutableDictionary *ARILabelScriptInlineEnsureMutableDictionary(NSMutableDictionary *owner, NSString *key) {
    NSMutableDictionary *dictionary = ARILabelScriptInlineMutableDictionaryValue(owner[key]);
    owner[key] = dictionary;
    return dictionary;
}

static id ARILabelScriptInlineDeepMutableCopy(id value) {
    if(!value) {
        return nil;
    }

    if([NSJSONSerialization isValidJSONObject:value]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
        if(data) {
            id copiedObject = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
            if(copiedObject) {
                return copiedObject;
            }
        }
    }

    if([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *copy = [NSMutableDictionary dictionary];
        for(id key in [(NSDictionary *)value allKeys]) {
            copy[key] = ARILabelScriptInlineDeepMutableCopy(((NSDictionary *)value)[key]) ?: [NSNull null];
        }
        return copy;
    }

    if([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *copy = [NSMutableArray array];
        for(id item in (NSArray *)value) {
            [copy addObject:ARILabelScriptInlineDeepMutableCopy(item) ?: [NSNull null]];
        }
        return copy;
    }

    if([value conformsToProtocol:@protocol(NSCopying)]) {
        return [value copy];
    }

    return value;
}

static UIColor *ARILabelScriptInlineTintColorNamed(NSString *name) {
    if([name isEqualToString:@"blue"]) return [UIColor systemBlueColor];
    if([name isEqualToString:@"orange"]) return [UIColor systemOrangeColor];
    if([name isEqualToString:@"green"]) return [UIColor systemGreenColor];
    if([name isEqualToString:@"pink"]) return [UIColor systemPinkColor];
    if([name isEqualToString:@"teal"]) return [UIColor systemTealColor];
    if([name isEqualToString:@"red"]) return [UIColor systemRedColor];
    if([name isEqualToString:@"purple"]) return [UIColor systemPurpleColor];
    if([name isEqualToString:@"yellow"]) return [UIColor systemYellowColor];
    return kARIPrefTintColor;
}

static NSDictionary *ARILabelScriptInlineMakeContainerDefinition(NSString *key,
                                                                 NSString *title,
                                                                 NSString *symbol,
                                                                 NSString *tint) {
    return @{
        @"key": key ?: @"steps",
        @"title": title ?: @"내용",
        @"symbol": symbol ?: @"line.3.horizontal",
        @"tint": tint ?: @"default"
    };
}

static NSDictionary *ARILabelScriptInlineMakeActionDefinition(NSString *type,
                                                              NSString *title,
                                                              NSString *symbol,
                                                              NSString *tint,
                                                              NSString *summary,
                                                              BOOL collapsible,
                                                              NSArray<NSDictionary *> *containers,
                                                              NSString *endTitle,
                                                              ARILabelScriptActionFactory factory) {
    return @{
        @"type": type ?: @"",
        @"title": title ?: @"액션",
        @"symbol": symbol ?: @"square.on.square",
        @"tint": tint ?: @"default",
        @"summary": summary ?: @"",
        @"collapsible": @(collapsible),
        @"containers": containers ?: @[],
        @"endTitle": endTitle ?: @"끝",
        @"factory": [factory copy] ?: [^{
            return [@{ @"type": @"set_text", @"text": @"새 텍스트" } mutableCopy];
        } copy]
    };
}

static NSArray<NSDictionary *> *ARILabelScriptInlineActionDefinitions(void) {
    static NSArray<NSDictionary *> *definitions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        definitions = @[
            ARILabelScriptInlineMakeActionDefinition(@"set_text",
                                                     @"텍스트",
                                                     @"text.alignleft",
                                                     @"blue",
                                                     @"텍스트 표시",
                                                     NO,
                                                     @[],
                                                     @"",
                                                     ^NSMutableDictionary *{
                return [@{ @"type": @"set_text", @"text": @"새 텍스트" } mutableCopy];
            }),
            ARILabelScriptInlineMakeActionDefinition(@"wait",
                                                     @"대기",
                                                     @"timer",
                                                     @"orange",
                                                     @"잠시 멈춤",
                                                     NO,
                                                     @[],
                                                     @"",
                                                     ^NSMutableDictionary *{
                return [@{ @"type": @"wait", @"seconds": @2 } mutableCopy];
            }),
            ARILabelScriptInlineMakeActionDefinition(@"reload",
                                                     @"리로드",
                                                     @"arrow.clockwise.circle",
                                                     @"teal",
                                                     @"스크립트를 처음부터 다시 실행",
                                                     NO,
                                                     @[],
                                                     @"",
                                                     ^NSMutableDictionary *{
                return [@{ @"type": @"reload" } mutableCopy];
            }),
            ARILabelScriptInlineMakeActionDefinition(@"if",
                                                     @"조건",
                                                     @"arrow.triangle.branch",
                                                     @"green",
                                                     @"조건에 따라 분기",
                                                     YES,
                                                     @[
                                                         ARILabelScriptInlineMakeContainerDefinition(@"then", @"참일 때", @"arrow.turn.down.right", @"green"),
                                                         ARILabelScriptInlineMakeContainerDefinition(@"else", @"아니면", @"arrow.turn.down.left", @"teal")
                                                     ],
                                                     @"조건 끝",
                                                     ^NSMutableDictionary *{
                return [@{
                    @"type": @"if",
                    @"condition": ARILabelScriptInlineDefaultCondition(@"hour_between"),
                    @"then": [NSMutableArray arrayWithObject:ARILabelScriptInlineDefaultBlock(@"set_text")],
                    @"else": [NSMutableArray arrayWithObject:ARILabelScriptInlineDefaultBlock(@"set_text")]
                } mutableCopy];
            }),
            ARILabelScriptInlineMakeActionDefinition(@"repeat",
                                                     @"반복",
                                                     @"repeat",
                                                     @"pink",
                                                     @"여러 번 반복",
                                                     YES,
                                                     @[
                                                         ARILabelScriptInlineMakeContainerDefinition(@"steps", @"반복 내용", @"line.3.horizontal", @"pink")
                                                     ],
                                                     @"반복 끝",
                                                     ^NSMutableDictionary *{
                return [@{
                    @"type": @"repeat",
                    @"times": @0,
                    @"steps": [NSMutableArray arrayWithObjects:
                        ARILabelScriptInlineDefaultBlock(@"set_text"),
                        ARILabelScriptInlineDefaultBlock(@"wait"),
                        nil
                    ]
                } mutableCopy];
            })
        ];
    });
    return definitions;
}

static NSDictionary *ARILabelScriptInlineActionDefinition(NSString *type) {
    NSString *targetType = [type isKindOfClass:[NSString class]] ? type : @"";
    for(NSDictionary *definition in ARILabelScriptInlineActionDefinitions()) {
        if([definition[@"type"] isEqualToString:targetType]) {
            return definition;
        }
    }
    return nil;
}

static NSString *ARILabelScriptInlineBlockTitle(NSString *type) {
    NSDictionary *definition = ARILabelScriptInlineActionDefinition(type);
    if([definition[@"title"] isKindOfClass:[NSString class]]) {
        return definition[@"title"];
    }
    return type.length > 0 ? type : @"액션";
}

static NSString *ARILabelScriptInlineBlockSymbol(NSString *type) {
    NSDictionary *definition = ARILabelScriptInlineActionDefinition(type);
    if([definition[@"symbol"] isKindOfClass:[NSString class]]) {
        return definition[@"symbol"];
    }
    return @"square.on.square";
}

static UIColor *ARILabelScriptInlineBlockTint(NSString *type) {
    NSDictionary *definition = ARILabelScriptInlineActionDefinition(type);
    if([definition[@"tint"] isKindOfClass:[NSString class]]) {
        return ARILabelScriptInlineTintColorNamed(definition[@"tint"]);
    }
    return kARIPrefTintColor;
}

static BOOL ARILabelScriptInlineBlockIsCollapsible(NSString *type) {
    return [ARILabelScriptInlineActionDefinition(type)[@"collapsible"] boolValue];
}

static NSArray<NSDictionary *> *ARILabelScriptInlineBlockContainers(NSString *type) {
    NSDictionary *definition = ARILabelScriptInlineActionDefinition(type);
    if([definition[@"containers"] isKindOfClass:[NSArray class]]) {
        return definition[@"containers"];
    }
    return @[];
}

static NSString *ARILabelScriptInlineBlockEndTitle(NSString *type) {
    NSDictionary *definition = ARILabelScriptInlineActionDefinition(type);
    if([definition[@"endTitle"] isKindOfClass:[NSString class]]) {
        return definition[@"endTitle"];
    }
    return @"끝";
}

static NSDictionary *ARILabelScriptInlineMakeConditionDefinition(NSString *type,
                                                                 NSString *title,
                                                                 NSString *symbol,
                                                                 NSString *tint,
                                                                 NSString *summary,
                                                                 BOOL selectableAtRoot,
                                                                 BOOL selectableAsNested,
                                                                 ARILabelScriptConditionFactory factory,
                                                                 ARILabelScriptConditionSummaryBuilder summaryBuilder) {
    return @{
        @"type": type ?: @"",
        @"title": title ?: @"조건",
        @"symbol": symbol ?: @"line.3.horizontal.decrease.circle",
        @"tint": tint ?: @"default",
        @"summary": summary ?: @"",
        @"root": @(selectableAtRoot),
        @"nested": @(selectableAsNested),
        @"summaryBuilder": [summaryBuilder copy] ?: [^NSString *(NSDictionary *condition) {
            return condition ? (title ?: @"조건") : (title ?: @"조건");
        } copy],
        @"factory": [factory copy] ?: [^{
            return [@{ @"type": @"always" } mutableCopy];
        } copy]
    };
}

static NSArray<NSDictionary *> *ARILabelScriptInlineConditionDefinitions(void) {
    static NSArray<NSDictionary *> *definitions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        definitions = @[
            ARILabelScriptInlineMakeConditionDefinition(@"always", @"항상", @"checkmark.circle", @"green", @"항상 참", YES, YES, ^NSMutableDictionary *{
                return [@{ @"type": @"always" } mutableCopy];
            }, ^NSString *(__unused NSDictionary *condition) {
                return @"항상";
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"hour_between", @"시간대", @"clock", @"blue", @"시작과 종료 시간", YES, YES, ^NSMutableDictionary *{
                return [@{ @"type": @"hour_between", @"start": @20, @"end": @24 } mutableCopy];
            }, ^NSString *(NSDictionary *condition) {
                double start = [condition[@"start"] respondsToSelector:@selector(doubleValue)] ? [condition[@"start"] doubleValue] : 0.0;
                double end = [condition[@"end"] respondsToSelector:@selector(doubleValue)] ? [condition[@"end"] doubleValue] : 24.0;
                return [NSString stringWithFormat:@"시간 %@ ~ %@", ARILabelScriptInlineFormattedTimeValue(start), ARILabelScriptInlineFormattedTimeValue(end)];
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"weekday_is", @"요일", @"calendar", @"teal", @"선택한 요일", YES, YES, ^NSMutableDictionary *{
                return [@{ @"type": @"weekday_is", @"days": [NSMutableArray arrayWithObject:@1] } mutableCopy];
            }, ^NSString *(NSDictionary *condition) {
                NSArray *days = [condition[@"days"] isKindOfClass:[NSArray class]] ? condition[@"days"] : @[];
                return [NSString stringWithFormat:@"요일 %@", ARILabelScriptInlineWeekdaySummary(days)];
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"location_contains", @"지역 포함", @"location", @"blue", @"지역 이름 비교", YES, YES, ^NSMutableDictionary *{
                return [@{ @"type": @"location_contains", @"query": @"서울" } mutableCopy];
            }, ^NSString *(NSDictionary *condition) {
                NSString *query = [condition[@"query"] isKindOfClass:[NSString class]] ? condition[@"query"] : @"";
                return [NSString stringWithFormat:@"지역에 %@ 포함", query.length > 0 ? query : @"키워드"];
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"weather_contains", @"날씨 포함", @"cloud.sun", @"teal", @"날씨 키워드 비교", YES, YES, ^NSMutableDictionary *{
                return [@{ @"type": @"weather_contains", @"query": @"비" } mutableCopy];
            }, ^NSString *(NSDictionary *condition) {
                NSString *query = [condition[@"query"] isKindOfClass:[NSString class]] ? condition[@"query"] : @"";
                return [NSString stringWithFormat:@"날씨에 %@ 포함", query.length > 0 ? query : @"키워드"];
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"temperature_above", @"온도 이상", @"thermometer.high", @"red", @"기준 온도 이상", YES, YES, ^NSMutableDictionary *{
                return [@{ @"type": @"temperature_above", @"value": @25 } mutableCopy];
            }, ^NSString *(NSDictionary *condition) {
                double value = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
                return [NSString stringWithFormat:@"온도 %@ 이상", ARILabelScriptInlineFormattedMetricValue(value, @"°")];
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"temperature_below", @"온도 미만", @"thermometer.low", @"blue", @"기준 온도 미만", YES, YES, ^NSMutableDictionary *{
                return [@{ @"type": @"temperature_below", @"value": @10 } mutableCopy];
            }, ^NSString *(NSDictionary *condition) {
                double value = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
                return [NSString stringWithFormat:@"온도 %@ 미만", ARILabelScriptInlineFormattedMetricValue(value, @"°")];
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"battery_above", @"배터리 이상", @"battery.75", @"green", @"기준 배터리 이상", YES, YES, ^NSMutableDictionary *{
                return [@{ @"type": @"battery_above", @"value": @80 } mutableCopy];
            }, ^NSString *(NSDictionary *condition) {
                double value = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
                return [NSString stringWithFormat:@"배터리 %@ 이상", ARILabelScriptInlineFormattedMetricValue(value, @"%")];
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"battery_below", @"배터리 미만", @"battery.25", @"orange", @"기준 배터리 미만", YES, YES, ^NSMutableDictionary *{
                return [@{ @"type": @"battery_below", @"value": @20 } mutableCopy];
            }, ^NSString *(NSDictionary *condition) {
                double value = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
                return [NSString stringWithFormat:@"배터리 %@ 미만", ARILabelScriptInlineFormattedMetricValue(value, @"%")];
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"battery_charging", @"충전 중", @"battery.100.bolt", @"green", @"충전 상태", YES, YES, ^NSMutableDictionary *{
                return [@{ @"type": @"battery_charging" } mutableCopy];
            }, ^NSString *(__unused NSDictionary *condition) {
                return @"충전 중";
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"battery_connected", @"충전기 연결됨", @"powerplug", @"teal", @"충전기 연결 상태", NO, NO, ^NSMutableDictionary *{
                return [@{ @"type": @"battery_connected" } mutableCopy];
            }, ^NSString *(__unused NSDictionary *condition) {
                return @"충전기 연결됨";
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"and", @"그리고", @"list.bullet.indent", @"purple", @"모든 하위 조건", YES, YES, ^NSMutableDictionary *{
                return [@{
                    @"type": @"and",
                    @"conditions": [NSMutableArray arrayWithObject:ARILabelScriptInlineDefaultCondition(@"hour_between")]
                } mutableCopy];
            }, ^NSString *(NSDictionary *condition) {
                NSArray *conditions = [condition[@"conditions"] isKindOfClass:[NSArray class]] ? condition[@"conditions"] : @[];
                NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:conditions.count];
                for(NSDictionary *item in conditions) {
                    [parts addObject:ARILabelScriptInlineConditionSummary(item)];
                }
                return parts.count > 0 ? [parts componentsJoinedByString:@" 그리고 "] : @"그리고";
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"or", @"또는", @"square.stack.3d.up", @"purple", @"하나 이상 만족", YES, YES, ^NSMutableDictionary *{
                return [@{
                    @"type": @"or",
                    @"conditions": [NSMutableArray arrayWithObject:ARILabelScriptInlineDefaultCondition(@"weather_contains")]
                } mutableCopy];
            }, ^NSString *(NSDictionary *condition) {
                NSArray *conditions = [condition[@"conditions"] isKindOfClass:[NSArray class]] ? condition[@"conditions"] : @[];
                NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:conditions.count];
                for(NSDictionary *item in conditions) {
                    [parts addObject:ARILabelScriptInlineConditionSummary(item)];
                }
                return parts.count > 0 ? [parts componentsJoinedByString:@" 또는 "] : @"또는";
            }),
            ARILabelScriptInlineMakeConditionDefinition(@"not", @"아님", @"minus.circle", @"orange", @"하위 조건 부정", YES, YES, ^NSMutableDictionary *{
                return [@{
                    @"type": @"not",
                    @"condition": ARILabelScriptInlineDefaultCondition(@"battery_charging")
                } mutableCopy];
            }, ^NSString *(NSDictionary *condition) {
                NSDictionary *nested = [condition[@"condition"] isKindOfClass:[NSDictionary class]] ? condition[@"condition"] : @{};
                return [NSString stringWithFormat:@"아님 (%@)", ARILabelScriptInlineConditionSummary(nested)];
            })
        ];
    });
    return definitions;
}

static NSDictionary *ARILabelScriptInlineConditionDefinition(NSString *type) {
    NSString *targetType = [type isKindOfClass:[NSString class]] ? type : @"";
    for(NSDictionary *definition in ARILabelScriptInlineConditionDefinitions()) {
        if([definition[@"type"] isEqualToString:targetType]) {
            return definition;
        }
    }
    return nil;
}

static NSArray<NSDictionary *> *ARILabelScriptInlineFilteredConditionDefinitions(BOOL nestedOnly) {
    NSString *key = nestedOnly ? @"nested" : @"root";
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *definition, __unused NSDictionary<NSString *,id> *bindings) {
        return [definition[key] boolValue];
    }];
    return [ARILabelScriptInlineConditionDefinitions() filteredArrayUsingPredicate:predicate];
}

static NSString *ARILabelScriptInlineConditionSymbol(NSString *type) {
    NSDictionary *definition = ARILabelScriptInlineConditionDefinition(type);
    if([definition[@"symbol"] isKindOfClass:[NSString class]]) {
        return definition[@"symbol"];
    }
    return @"line.3.horizontal.decrease.circle";
}

static UIColor *ARILabelScriptInlineConditionTint(NSString *type) {
    NSDictionary *definition = ARILabelScriptInlineConditionDefinition(type);
    if([definition[@"tint"] isKindOfClass:[NSString class]]) {
        return ARILabelScriptInlineTintColorNamed(definition[@"tint"]);
    }
    return kARIPrefTintColor;
}

static NSString *ARILabelScriptInlineConditionTitle(NSString *type) {
    NSDictionary *definition = ARILabelScriptInlineConditionDefinition(type);
    if([definition[@"title"] isKindOfClass:[NSString class]]) {
        return definition[@"title"];
    }
    return type.length > 0 ? type : @"조건";
}

static NSString *ARILabelScriptInlineConditionSummary(NSDictionary *condition) {
    NSString *type = [condition[@"type"] isKindOfClass:[NSString class]] ? condition[@"type"] : @"always";
    NSDictionary *definition = ARILabelScriptInlineConditionDefinition(type);
    ARILabelScriptConditionSummaryBuilder summaryBuilder = definition[@"summaryBuilder"];
    if(summaryBuilder) {
        return summaryBuilder(condition ?: @{});
    }
    return ARILabelScriptInlineConditionTitle(type);
}

static NSString *ARILabelScriptInlineConditionEditorKind(NSString *type) {
    NSString *resolvedType = [type isKindOfClass:[NSString class]] ? type : @"always";
    if([resolvedType isEqualToString:@"hour_between"]) return @"time";
    if([resolvedType isEqualToString:@"weekday_is"]) return @"weekday";
    if([resolvedType isEqualToString:@"location_contains"] || [resolvedType isEqualToString:@"weather_contains"]) return @"query";
    if([resolvedType isEqualToString:@"temperature_above"] || [resolvedType isEqualToString:@"temperature_below"]) return @"temperature";
    if([resolvedType isEqualToString:@"battery_above"] || [resolvedType isEqualToString:@"battery_below"]) return @"battery";
    if([resolvedType isEqualToString:@"and"] || [resolvedType isEqualToString:@"or"]) return @"group";
    if([resolvedType isEqualToString:@"not"]) return @"nested";
    if([resolvedType isEqualToString:@"always"] || [resolvedType isEqualToString:@"battery_charging"] || [resolvedType isEqualToString:@"battery_connected"]) return @"none";
    return @"summary";
}

static NSString *ARILabelScriptInlinePreviewValue(id value) {
    if([value isKindOfClass:[NSString class]]) {
        NSString *text = (NSString *)value;
        if(text.length > 24) {
            return [[text substringToIndex:24] stringByAppendingString:@"…"];
        }
        return text;
    }
    if([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    }
    if([value isKindOfClass:[NSArray class]]) {
        return [NSString stringWithFormat:@"%ld개", (long)[(NSArray *)value count]];
    }
    if([value isKindOfClass:[NSDictionary class]]) {
        return [NSString stringWithFormat:@"%ld개", (long)[(NSDictionary *)value count]];
    }
    return @"값";
}

static NSString *ARILabelScriptInlineUnknownBlockSummary(NSDictionary *block) {
    NSArray<NSString *> *sortedKeys = [[[block allKeys] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *key, __unused NSDictionary<NSString *,id> *bindings) {
        return ![key isEqualToString:@"type"];
    }]] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    if(sortedKeys.count == 0) {
        return @"값 없음";
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for(NSString *key in sortedKeys) {
        NSString *preview = ARILabelScriptInlinePreviewValue(block[key]);
        if(preview.length == 0) {
            continue;
        }
        [parts addObject:[NSString stringWithFormat:@"%@ %@", key, preview]];
        if(parts.count >= 3) {
            break;
        }
    }
    return parts.count > 0 ? [parts componentsJoinedByString:@" · "] : @"값 없음";
}

@interface ARILabelScriptVisualPart : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *tokenIdentifier;
+ (instancetype)partWithText:(NSString *)text;
+ (instancetype)tokenWithText:(NSString *)text identifier:(NSString *)identifier;
@end

@implementation ARILabelScriptVisualPart
+ (instancetype)partWithText:(NSString *)text {
    ARILabelScriptVisualPart *part = [ARILabelScriptVisualPart new];
    part.text = text ?: @"";
    return part;
}

+ (instancetype)tokenWithText:(NSString *)text identifier:(NSString *)identifier {
    ARILabelScriptVisualPart *part = [ARILabelScriptVisualPart new];
    part.text = text ?: @"";
    part.tokenIdentifier = identifier ?: @"";
    return part;
}
@end

@interface ARILabelScriptVisualRow : NSObject
@property (nonatomic, assign) ARILabelScriptVisualRowKind kind;
@property (nonatomic, assign) ARILabelScriptVisualAccessoryKind accessoryKind;
@property (nonatomic, assign) NSInteger depth;
@property (nonatomic, strong) NSMutableDictionary *block;
@property (nonatomic, strong) NSMutableArray *container;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, strong) NSMutableArray *insertionContainer;
@property (nonatomic, assign) NSInteger insertionIndex;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, strong) UIColor *tintColor;
@property (nonatomic, copy) NSArray<NSNumber *> *railDepths;
@property (nonatomic, assign) NSInteger scopeRailDepth;
@property (nonatomic, assign) ARILabelScriptVisualRailMode scopeRailMode;
@property (nonatomic, assign) BOOL collapsible;
@property (nonatomic, assign) BOOL collapsed;
@end

@implementation ARILabelScriptVisualRow
@end

static NSString *ARILabelScriptInlineConditionQueryLabel(NSString *type) {
    return [type isEqualToString:@"location_contains"] ? @"지역" : @"날씨";
}

static NSString *ARILabelScriptInlineConditionQueryInputTitle(NSString *type) {
    return [type isEqualToString:@"location_contains"] ? @"지역 키워드" : @"날씨 키워드";
}

static NSString *ARILabelScriptInlineConditionQueryPlaceholder(NSString *type) {
    return [type isEqualToString:@"location_contains"] ? @"예: 서울" : @"예: 비";
}

static NSString *ARILabelScriptInlineConditionMetricSuffix(NSString *type) {
    return [type hasPrefix:@"battery_"] ? @"%" : @"°";
}

static NSString *ARILabelScriptInlineConditionMetricInputTitle(NSString *type) {
    return [type hasPrefix:@"battery_"] ? @"배터리 값" : @"기준 온도";
}

static NSString *ARILabelScriptInlineConditionMetricPlaceholder(NSString *type) {
    return [type hasPrefix:@"battery_"] ? @"예: 50" : @"예: 20";
}

static NSArray<ARILabelScriptVisualPart *> *ARILabelScriptInlineConditionParts(NSDictionary *condition) {
    NSMutableArray<ARILabelScriptVisualPart *> *parts = [NSMutableArray new];
    NSString *conditionType = [condition[@"type"] isKindOfClass:[NSString class]] ? condition[@"type"] : @"always";
    NSString *kind = ARILabelScriptInlineConditionEditorKind(conditionType);

    if([kind isEqualToString:@"time"]) {
        double start = [condition[@"start"] respondsToSelector:@selector(doubleValue)] ? [condition[@"start"] doubleValue] : 0.0;
        double end = [condition[@"end"] respondsToSelector:@selector(doubleValue)] ? [condition[@"end"] doubleValue] : 24.0;
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:ARILabelScriptInlineConditionTitle(conditionType) identifier:@"condition_type"]];
        [parts addObject:[ARILabelScriptVisualPart partWithText:@" "]];
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:ARILabelScriptInlineFormattedTimeValue(start) identifier:@"condition_start"]];
        [parts addObject:[ARILabelScriptVisualPart partWithText:@" ~ "]];
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:ARILabelScriptInlineFormattedTimeValue(end) identifier:@"condition_end"]];
        return parts;
    }

    if([kind isEqualToString:@"weekday"]) {
        NSArray *days = [condition[@"days"] isKindOfClass:[NSArray class]] ? condition[@"days"] : @[];
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:ARILabelScriptInlineConditionTitle(conditionType) identifier:@"condition_type"]];
        [parts addObject:[ARILabelScriptVisualPart partWithText:@" "]];
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:ARILabelScriptInlineWeekdaySummary(days) identifier:@"condition_days"]];
        return parts;
    }

    if([kind isEqualToString:@"query"]) {
        NSString *query = [condition[@"query"] isKindOfClass:[NSString class]] ? condition[@"query"] : @"";
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:ARILabelScriptInlineConditionQueryLabel(conditionType) identifier:@"condition_type"]];
        [parts addObject:[ARILabelScriptVisualPart partWithText:@" "]];
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:(query.length > 0 ? query : @"키워드") identifier:@"condition_query"]];
        return parts;
    }

    if([kind isEqualToString:@"temperature"] || [kind isEqualToString:@"battery"]) {
        double value = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:ARILabelScriptInlineConditionTitle(conditionType) identifier:@"condition_type"]];
        [parts addObject:[ARILabelScriptVisualPart partWithText:@" "]];
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:ARILabelScriptInlineFormattedMetricValue(value, ARILabelScriptInlineConditionMetricSuffix(conditionType))
                                                     identifier:@"condition_value"]];
        return parts;
    }

    if([kind isEqualToString:@"none"]) {
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:ARILabelScriptInlineConditionTitle(conditionType) identifier:@"condition_type"]];
        return parts;
    }

    [parts addObject:[ARILabelScriptVisualPart tokenWithText:ARILabelScriptInlineConditionSummary(condition) identifier:@"condition"]];
    return parts;
}

@interface ARILabelScriptInlineTokenButton : UIButton
@property (nonatomic, copy) NSString *tokenIdentifier;
@end

@implementation ARILabelScriptInlineTokenButton
@end

@interface ARILabelScriptInlinePartsView : UIView
@property (nonatomic, copy) void (^tokenHandler)(NSString *tokenIdentifier);
@property (nonatomic, assign) CGFloat preferredLayoutWidth;
- (void)configureWithParts:(NSArray<ARILabelScriptVisualPart *> *)parts tokenColor:(UIColor *)tokenColor;
@end

@implementation ARILabelScriptInlinePartsView {
    NSMutableArray<UIView *> *_partViews;
    CGFloat _lastLaidOutWidth;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if(self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _partViews = [NSMutableArray new];
        _lastLaidOutWidth = -1.0;
        _preferredLayoutWidth = 0.0;
    }
    return self;
}

- (void)_clearPartViews {
    for(UIView *view in _partViews) {
        [view removeFromSuperview];
    }
    [_partViews removeAllObjects];
}

- (UILabel *)_labelForText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text ?: @"";
    label.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
    label.textColor = [UIColor labelColor];
    label.numberOfLines = 0;
    return label;
}

- (ARILabelScriptInlineTokenButton *)_tokenButtonForPart:(ARILabelScriptVisualPart *)part color:(UIColor *)tokenColor {
    ARILabelScriptInlineTokenButton *button = [ARILabelScriptInlineTokenButton buttonWithType:UIButtonTypeSystem];
    button.tokenIdentifier = part.tokenIdentifier ?: @"";
    button.tintColor = tokenColor ?: [UIColor systemBlueColor];
    [button setTitle:(part.text ?: @"") forState:UIControlStateNormal];
    [button setTitleColor:button.tintColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(6.0, 10.0, 6.0, 10.0);
    button.layer.cornerRadius = 11.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [button.tintColor colorWithAlphaComponent:0.18].CGColor;
    button.backgroundColor = [button.tintColor colorWithAlphaComponent:0.12];
    [button addTarget:self action:@selector(tokenTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)configureWithParts:(NSArray<ARILabelScriptVisualPart *> *)parts tokenColor:(UIColor *)tokenColor {
    [self _clearPartViews];
    UIColor *resolvedTokenColor = tokenColor ?: [UIColor systemBlueColor];
    for(ARILabelScriptVisualPart *part in parts) {
        UIView *view = nil;
        if(part.tokenIdentifier.length > 0) {
            view = [self _tokenButtonForPart:part color:resolvedTokenColor];
        } else {
            view = [self _labelForText:part.text];
        }
        [self addSubview:view];
        [_partViews addObject:view];
    }
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}

- (CGSize)_sizeForPartView:(UIView *)view maxWidth:(CGFloat)maxWidth {
    CGFloat availableWidth = MAX(44.0, maxWidth);
    CGSize targetSize = CGSizeMake(availableWidth, CGFLOAT_MAX);
    CGSize fittedSize = [view sizeThatFits:targetSize];
    if([view isKindOfClass:[ARILabelScriptInlineTokenButton class]]) {
        fittedSize.width = MIN(MAX(44.0, fittedSize.width), availableWidth);
        fittedSize.height = MAX(32.0, fittedSize.height);
    } else {
        fittedSize.width = MIN(availableWidth, fittedSize.width);
    }
    return fittedSize;
}

- (CGSize)_layoutPartsForWidth:(CGFloat)maxWidth applyingFrames:(BOOL)applyingFrames {
    CGFloat lineSpacing = 6.0;
    CGFloat itemSpacing = 6.0;
    __block CGFloat x = 0.0;
    __block CGFloat y = 0.0;
    __block CGFloat lineHeight = 0.0;
    __block CGFloat contentWidth = 0.0;
    CGFloat resolvedWidth = MAX(120.0, maxWidth);
    NSMutableArray<UIView *> *lineViews = [NSMutableArray new];
    NSMutableArray<NSValue *> *lineSizes = [NSMutableArray new];

    void (^flushLine)(void) = ^{
        if(lineViews.count == 0) {
            return;
        }

        CGFloat lineX = 0.0;
        for(NSUInteger index = 0; index < lineViews.count; index++) {
            UIView *view = lineViews[index];
            CGSize size = [lineSizes[index] CGSizeValue];
            CGFloat centeredY = y + floor((lineHeight - size.height) * 0.5);
            if(applyingFrames) {
                view.frame = CGRectMake(lineX, centeredY, size.width, size.height);
            }
            lineX += size.width + itemSpacing;
        }

        contentWidth = MAX(contentWidth, lineX - itemSpacing);
        y += lineHeight + lineSpacing;
        x = 0.0;
        lineHeight = 0.0;
        [lineViews removeAllObjects];
        [lineSizes removeAllObjects];
    };

    for(UIView *view in _partViews) {
        CGSize size = [self _sizeForPartView:view maxWidth:resolvedWidth];
        if(x > 0.0 && (x + size.width) > resolvedWidth) {
            flushLine();
        }

        [lineViews addObject:view];
        [lineSizes addObject:[NSValue valueWithCGSize:size]];
        x += size.width + itemSpacing;
        lineHeight = MAX(lineHeight, size.height);
    }

    flushLine();
    if(y > 0.0) {
        y -= lineSpacing;
    }

    return CGSizeMake(contentWidth, y);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    if(fabs(width - _lastLaidOutWidth) > 0.5) {
        _lastLaidOutWidth = width;
        [self invalidateIntrinsicContentSize];
    }
    [self _layoutPartsForWidth:width applyingFrames:YES];
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat width = size.width;
    if(width <= 0.0) {
        width = CGRectGetWidth(self.bounds);
    }
    if(width <= 0.0) {
        width = self.preferredLayoutWidth;
    }
    if(width <= 0.0) {
        width = UIScreen.mainScreen.bounds.size.width - 220.0;
    }
    return [self _layoutPartsForWidth:width applyingFrames:NO];
}

- (CGSize)intrinsicContentSize {
    CGSize fittedSize = [self sizeThatFits:CGSizeMake(CGRectGetWidth(self.bounds), CGFLOAT_MAX)];
    return CGSizeMake(UIViewNoIntrinsicMetric, fittedSize.height);
}

- (void)tokenTapped:(ARILabelScriptInlineTokenButton *)sender {
    if(sender.tokenIdentifier.length > 0 && self.tokenHandler) {
        self.tokenHandler(sender.tokenIdentifier);
    }
}

@end

@interface ARILabelScriptInlineCell : UITableViewCell <UIGestureRecognizerDelegate>
@property (nonatomic, copy) void (^tokenHandler)(NSString *tokenIdentifier);
@property (nonatomic, copy) void (^accessoryHandler)(void);
@property (nonatomic, copy) void (^tapHandler)(void);
- (void)configureWithParts:(NSArray<ARILabelScriptVisualPart *> *)parts
                  iconName:(NSString *)iconName
                 tintColor:(UIColor *)tintColor
                   rowKind:(ARILabelScriptVisualRowKind)rowKind
                     depth:(NSInteger)depth
                railDepths:(NSArray<NSNumber *> *)railDepths
            scopeRailDepth:(NSInteger)scopeRailDepth
             scopeRailMode:(ARILabelScriptVisualRailMode)scopeRailMode
                  selected:(BOOL)selected
             accessoryKind:(ARILabelScriptVisualAccessoryKind)accessoryKind;
@end

@implementation ARILabelScriptInlineCell {
    UIView *_panelView;
    UIView *_railView;
    UIView *_iconContainer;
    UIImageView *_iconView;
    ARILabelScriptInlinePartsView *_partsView;
    UIButton *_accessoryButton;
    UIView *_insertLeadingLineView;
    UIView *_insertTrailingLineView;
    UILabel *_insertTitleLabel;
    NSLayoutConstraint *_panelLeadingConstraint;
    NSMutableArray<UIView *> *_flowRails;
}

- (CGFloat)_preferredPartsWidthForContentWidth:(CGFloat)contentWidth {
    CGFloat panelWidth = contentWidth - _panelLeadingConstraint.constant - 16.0;
    CGFloat partsWidth = panelWidth - 116.0;
    return MAX(120.0, partsWidth);
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if(self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _panelView = [[UIView alloc] init];
        _panelView.translatesAutoresizingMaskIntoConstraints = NO;
        _panelView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        _panelView.layer.cornerRadius = 18.0;
        _panelView.layer.cornerCurve = kCACornerCurveContinuous;
        _panelView.layer.borderWidth = 1.0;
        _panelView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.06].CGColor;
        [self.contentView addSubview:_panelView];

        _railView = [[UIView alloc] init];
        _railView.translatesAutoresizingMaskIntoConstraints = NO;
        _railView.backgroundColor = [UIColor systemFillColor];
        _railView.layer.cornerRadius = 1.0;
        [_panelView addSubview:_railView];

        _iconContainer = [[UIView alloc] init];
        _iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
        _iconContainer.layer.cornerRadius = 14.0;
        _iconContainer.layer.cornerCurve = kCACornerCurveContinuous;
        [_panelView addSubview:_iconContainer];

        _iconView = [[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconContainer addSubview:_iconView];

        _partsView = [[ARILabelScriptInlinePartsView alloc] init];
        [_panelView addSubview:_partsView];

        _accessoryButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _accessoryButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_accessoryButton addTarget:self action:@selector(accessoryTapped) forControlEvents:UIControlEventTouchUpInside];
        [_panelView addSubview:_accessoryButton];

        _insertLeadingLineView = [[UIView alloc] init];
        _insertLeadingLineView.translatesAutoresizingMaskIntoConstraints = NO;
        _insertLeadingLineView.hidden = YES;
        [_panelView addSubview:_insertLeadingLineView];

        _insertTrailingLineView = [[UIView alloc] init];
        _insertTrailingLineView.translatesAutoresizingMaskIntoConstraints = NO;
        _insertTrailingLineView.hidden = YES;
        [_panelView addSubview:_insertTrailingLineView];

        _insertTitleLabel = [[UILabel alloc] init];
        _insertTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _insertTitleLabel.hidden = YES;
        _insertTitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        _insertTitleLabel.textAlignment = NSTextAlignmentCenter;
        _insertTitleLabel.numberOfLines = 1;
        _insertTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_panelView addSubview:_insertTitleLabel];

        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(panelTapped:)];
        tapGesture.cancelsTouchesInView = NO;
        tapGesture.delegate = self;
        [_panelView addGestureRecognizer:tapGesture];

        _flowRails = [NSMutableArray new];

        _panelLeadingConstraint = [_panelView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0];
        [NSLayoutConstraint activateConstraints:@[
            _panelLeadingConstraint,
            [_panelView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_panelView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_panelView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

            [_railView.leadingAnchor constraintEqualToAnchor:_panelView.leadingAnchor constant:12.0],
            [_railView.topAnchor constraintEqualToAnchor:_panelView.topAnchor constant:10.0],
            [_railView.bottomAnchor constraintEqualToAnchor:_panelView.bottomAnchor constant:-10.0],
            [_railView.widthAnchor constraintEqualToConstant:2.0],

            [_iconContainer.leadingAnchor constraintEqualToAnchor:_railView.trailingAnchor constant:12.0],
            [_iconContainer.centerYAnchor constraintEqualToAnchor:_panelView.centerYAnchor],
            [_iconContainer.widthAnchor constraintEqualToConstant:28.0],
            [_iconContainer.heightAnchor constraintEqualToConstant:28.0],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconContainer.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconContainer.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:15.0],
            [_iconView.heightAnchor constraintEqualToConstant:15.0],

            [_accessoryButton.trailingAnchor constraintEqualToAnchor:_panelView.trailingAnchor constant:-10.0],
            [_accessoryButton.centerYAnchor constraintEqualToAnchor:_panelView.centerYAnchor],
            [_accessoryButton.widthAnchor constraintEqualToConstant:30.0],
            [_accessoryButton.heightAnchor constraintEqualToConstant:30.0],

            [_partsView.leadingAnchor constraintEqualToAnchor:_iconContainer.trailingAnchor constant:12.0],
            [_partsView.topAnchor constraintEqualToAnchor:_panelView.topAnchor constant:12.0],
            [_partsView.bottomAnchor constraintEqualToAnchor:_panelView.bottomAnchor constant:-12.0],
            [_partsView.trailingAnchor constraintEqualToAnchor:_accessoryButton.leadingAnchor constant:-10.0],

            [_insertTitleLabel.centerXAnchor constraintEqualToAnchor:_panelView.centerXAnchor],
            [_insertTitleLabel.centerYAnchor constraintEqualToAnchor:_panelView.centerYAnchor],
            [_insertTitleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_panelView.leadingAnchor constant:52.0],
            [_insertTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_panelView.trailingAnchor constant:-52.0],

            [_insertLeadingLineView.leadingAnchor constraintEqualToAnchor:_panelView.leadingAnchor constant:12.0],
            [_insertLeadingLineView.trailingAnchor constraintEqualToAnchor:_insertTitleLabel.leadingAnchor constant:-12.0],
            [_insertLeadingLineView.centerYAnchor constraintEqualToAnchor:_insertTitleLabel.centerYAnchor],
            [_insertLeadingLineView.heightAnchor constraintEqualToConstant:1.0],

            [_insertTrailingLineView.leadingAnchor constraintEqualToAnchor:_insertTitleLabel.trailingAnchor constant:12.0],
            [_insertTrailingLineView.trailingAnchor constraintEqualToAnchor:_panelView.trailingAnchor constant:-12.0],
            [_insertTrailingLineView.centerYAnchor constraintEqualToAnchor:_insertTitleLabel.centerYAnchor],
            [_insertTrailingLineView.heightAnchor constraintEqualToConstant:1.0]
        ]];
    }
    return self;
}

- (void)_clearFlowRails {
    for(UIView *rail in _flowRails) {
        [rail removeFromSuperview];
    }
    [_flowRails removeAllObjects];
}

- (void)_addFlowRailAtDepth:(NSInteger)depth mode:(ARILabelScriptVisualRailMode)mode color:(UIColor *)color {
    if(depth <= 0) {
        return;
    }

    UIView *rail = [[UIView alloc] init];
    rail.translatesAutoresizingMaskIntoConstraints = NO;
    rail.backgroundColor = color ?: [UIColor systemFillColor];
    rail.layer.cornerRadius = 1.0;
    [self.contentView insertSubview:rail belowSubview:_panelView];
    [_flowRails addObject:rail];

    NSLayoutYAxisAnchor *topAnchor = self.contentView.topAnchor;
    NSLayoutYAxisAnchor *bottomAnchor = self.contentView.bottomAnchor;
    CGFloat topConstant = 0.0;
    CGFloat bottomConstant = 0.0;

    if(mode == ARILabelScriptVisualRailModeStart) {
        topAnchor = _panelView.centerYAnchor;
        topConstant = 2.0;
    } else if(mode == ARILabelScriptVisualRailModeEnd) {
        bottomAnchor = _panelView.centerYAnchor;
        bottomConstant = -2.0;
    }

    CGFloat leading = kARILabelScriptRailLeadingBase + ((CGFloat)depth * kARILabelScriptIndentStep);
    [NSLayoutConstraint activateConstraints:@[
        [rail.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:leading],
        [rail.widthAnchor constraintEqualToConstant:2.0],
        [rail.topAnchor constraintEqualToAnchor:topAnchor constant:topConstant],
        [rail.bottomAnchor constraintEqualToAnchor:bottomAnchor constant:bottomConstant]
    ]];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *view = touch.view;
    while(view && view != _panelView) {
        if([view isKindOfClass:[UIControl class]]) {
            return NO;
        }
        view = view.superview;
    }
    return YES;
}

- (void)panelTapped:(UITapGestureRecognizer *)gestureRecognizer {
    if(gestureRecognizer.state != UIGestureRecognizerStateEnded) {
        return;
    }
    if(self.tapHandler) {
        self.tapHandler();
    }
}

- (void)accessoryTapped {
    if(self.accessoryHandler) {
        self.accessoryHandler();
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.tokenHandler = nil;
    self.accessoryHandler = nil;
    self.tapHandler = nil;
    _partsView.tokenHandler = nil;
    _partsView.preferredLayoutWidth = 0.0;
    [self _clearFlowRails];
}

- (void)configureWithParts:(NSArray<ARILabelScriptVisualPart *> *)parts
                  iconName:(NSString *)iconName
                 tintColor:(UIColor *)tintColor
                   rowKind:(ARILabelScriptVisualRowKind)rowKind
                     depth:(NSInteger)depth
                railDepths:(NSArray<NSNumber *> *)railDepths
            scopeRailDepth:(NSInteger)scopeRailDepth
             scopeRailMode:(ARILabelScriptVisualRailMode)scopeRailMode
                  selected:(BOOL)selected
             accessoryKind:(ARILabelScriptVisualAccessoryKind)accessoryKind {
    _panelLeadingConstraint.constant = kARILabelScriptPanelLeadingBase + (MAX(depth, 0) * kARILabelScriptIndentStep);
    _railView.hidden = YES;

    BOOL isInsertRow = (rowKind == ARILabelScriptVisualRowKindInsert || rowKind == ARILabelScriptVisualRowKindEmpty);
    UIColor *baseTint = tintColor ?: kARIPrefTintColor;
    UIColor *panelBackgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    UIColor *borderColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    UIColor *iconBackgroundColor = [baseTint colorWithAlphaComponent:0.14];
    UIColor *iconTintColor = baseTint;

    if(rowKind == ARILabelScriptVisualRowKindGroup) {
        panelBackgroundColor = [baseTint colorWithAlphaComponent:0.07];
        borderColor = [baseTint colorWithAlphaComponent:0.10];
        iconBackgroundColor = [baseTint colorWithAlphaComponent:0.10];
        iconTintColor = [baseTint colorWithAlphaComponent:0.9];
    } else if(isInsertRow) {
        panelBackgroundColor = [UIColor clearColor];
        borderColor = [UIColor clearColor];
        iconBackgroundColor = [UIColor clearColor];
        iconTintColor = [UIColor clearColor];
    } else if(rowKind == ARILabelScriptVisualRowKindEnd) {
        panelBackgroundColor = [[UIColor tertiarySystemGroupedBackgroundColor] colorWithAlphaComponent:0.72];
        borderColor = [[UIColor tertiaryLabelColor] colorWithAlphaComponent:0.08];
        iconBackgroundColor = [[UIColor tertiaryLabelColor] colorWithAlphaComponent:0.08];
        iconTintColor = [UIColor tertiaryLabelColor];
    }

    _iconContainer.hidden = isInsertRow;
    _partsView.hidden = isInsertRow;
    _accessoryButton.hidden = isInsertRow || accessoryKind == ARILabelScriptVisualAccessoryKindNone;
    _insertLeadingLineView.hidden = !isInsertRow;
    _insertTrailingLineView.hidden = !isInsertRow;
    _insertTitleLabel.hidden = !isInsertRow;

    _iconContainer.backgroundColor = iconBackgroundColor;
    _iconView.image = iconName.length > 0 ? [[UIImage systemImageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
    _iconView.tintColor = iconTintColor;

    _panelView.backgroundColor = selected ? [baseTint colorWithAlphaComponent:0.12] : panelBackgroundColor;
    _panelView.layer.borderColor = (selected ? [baseTint colorWithAlphaComponent:0.45] : borderColor).CGColor;
    _panelView.layer.borderWidth = isInsertRow ? 0.0 : 1.0;
    _panelView.layer.cornerRadius = isInsertRow ? 0.0 : 18.0;

    UIColor *insertTint = selected ? [baseTint colorWithAlphaComponent:0.95] : [UIColor systemBlueColor];
    _insertTitleLabel.text = [[parts valueForKey:@"text"] componentsJoinedByString:@""];
    _insertTitleLabel.textColor = insertTint;
    _insertLeadingLineView.backgroundColor = [insertTint colorWithAlphaComponent:selected ? 0.38 : 0.24];
    _insertTrailingLineView.backgroundColor = _insertLeadingLineView.backgroundColor;

    [self _clearFlowRails];
    UIColor *quietRailColor = selected ? [baseTint colorWithAlphaComponent:0.24] : [[UIColor tertiaryLabelColor] colorWithAlphaComponent:0.18];
    for(NSNumber *railDepth in railDepths) {
        [self _addFlowRailAtDepth:railDepth.integerValue mode:ARILabelScriptVisualRailModeNone color:quietRailColor];
    }
    if(scopeRailDepth > 0 && scopeRailMode != ARILabelScriptVisualRailModeNone) {
        [self _addFlowRailAtDepth:scopeRailDepth mode:scopeRailMode color:[baseTint colorWithAlphaComponent:selected ? 0.82 : 0.62]];
    }

    NSString *accessorySymbol = nil;
    if(!isInsertRow && accessoryKind == ARILabelScriptVisualAccessoryKindMenu) {
        accessorySymbol = @"ellipsis.circle";
    } else if(!isInsertRow && accessoryKind == ARILabelScriptVisualAccessoryKindInsert) {
        accessorySymbol = @"plus.circle.fill";
    }

    [_accessoryButton setImage:accessorySymbol.length > 0 ? [UIImage systemImageNamed:accessorySymbol] : nil
                      forState:UIControlStateNormal];
    _accessoryButton.tintColor = accessoryKind == ARILabelScriptVisualAccessoryKindInsert ? [UIColor systemBlueColor] : [UIColor secondaryLabelColor];
    _partsView.tokenHandler = self.tokenHandler;
    _partsView.preferredLayoutWidth = [self _preferredPartsWidthForContentWidth:CGRectGetWidth(self.contentView.bounds)];
    if(!isInsertRow) {
        [_partsView configureWithParts:parts tokenColor:(rowKind == ARILabelScriptVisualRowKindAction ? baseTint : [UIColor systemBlueColor])];
    } else {
        [_partsView configureWithParts:@[] tokenColor:[UIColor systemBlueColor]];
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat preferredWidth = [self _preferredPartsWidthForContentWidth:CGRectGetWidth(self.contentView.bounds)];
    if(fabs(_partsView.preferredLayoutWidth - preferredWidth) > 0.5) {
        _partsView.preferredLayoutWidth = preferredWidth;
        [_partsView invalidateIntrinsicContentSize];
    }
}

- (CGSize)systemLayoutSizeFittingSize:(CGSize)targetSize
         withHorizontalFittingPriority:(UILayoutPriority)horizontalFittingPriority
               verticalFittingPriority:(UILayoutPriority)verticalFittingPriority {
    CGFloat referenceWidth = targetSize.width;
    if(referenceWidth <= 0.0) {
        referenceWidth = CGRectGetWidth(self.contentView.bounds);
    }
    if(referenceWidth > 0.0) {
        _partsView.preferredLayoutWidth = [self _preferredPartsWidthForContentWidth:referenceWidth];
    }
    [_partsView invalidateIntrinsicContentSize];
    return [super systemLayoutSizeFittingSize:targetSize
                 withHorizontalFittingPriority:horizontalFittingPriority
                       verticalFittingPriority:verticalFittingPriority];
}

@end

@interface ARILabelScriptInlineTimePickerController : UIViewController
- (instancetype)initWithTitle:(NSString *)title
                        value:(double)value
              allowsEndOfDay:(BOOL)allowsEndOfDay
                   completion:(ARILabelScriptTimePickerCompletion)completion;
@end

@implementation ARILabelScriptInlineTimePickerController {
    UIDatePicker *_timePicker;
    double _value;
    BOOL _allowsEndOfDay;
    ARILabelScriptTimePickerCompletion _completion;
}

- (instancetype)initWithTitle:(NSString *)title
                        value:(double)value
              allowsEndOfDay:(BOOL)allowsEndOfDay
                   completion:(ARILabelScriptTimePickerCompletion)completion {
    self = [super init];
    if(self) {
        self.title = title;
        _value = value;
        _allowsEndOfDay = allowsEndOfDay;
        _completion = [completion copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.view.tintColor = kARIPrefTintColor;
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                target:self
                                                                                action:@selector(saveSelection)];
    if(_allowsEndOfDay) {
        UIBarButtonItem *endOfDayButton = [[UIBarButtonItem alloc] initWithTitle:@"24:00"
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(selectEndOfDay)];
        self.navigationItem.rightBarButtonItems = @[ doneButton, endOfDayButton ];
    } else {
        self.navigationItem.rightBarButtonItem = doneButton;
    }

    _timePicker = [[UIDatePicker alloc] init];
    _timePicker.translatesAutoresizingMaskIntoConstraints = NO;
    _timePicker.datePickerMode = UIDatePickerModeTime;
    if(@available(iOS 13.4, *)) {
        _timePicker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    }
    _timePicker.minuteInterval = 1;
    if(_allowsEndOfDay && _value >= 24.0) {
        self.navigationItem.prompt = @"24:00";
        _timePicker.date = ARILabelScriptInlineDateFromTimeValue((23.0 + (59.0 / 60.0)));
    } else {
        _timePicker.date = ARILabelScriptInlineDateFromTimeValue(_value);
    }
    [_timePicker addTarget:self action:@selector(timeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_timePicker];

    [NSLayoutConstraint activateConstraints:@[
        [_timePicker.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_timePicker.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24.0]
    ]];
}

- (void)timeChanged:(UIDatePicker *)sender {
    self.navigationItem.prompt = nil;
    _value = ARILabelScriptInlineTimeValueFromDate(sender.date);
}

- (void)selectEndOfDay {
    _value = 24.0;
    self.navigationItem.prompt = @"24:00";
}

- (void)saveSelection {
    if(_completion) {
        _completion(_value);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end

@interface ARILabelScriptInlineWeekdayPickerController : UITableViewController
- (instancetype)initWithDays:(NSArray<NSNumber *> *)days completion:(ARILabelScriptWeekdayPickerCompletion)completion;
@end

@implementation ARILabelScriptInlineWeekdayPickerController {
    NSMutableOrderedSet<NSNumber *> *_selectedDays;
    ARILabelScriptWeekdayPickerCompletion _completion;
}

- (instancetype)initWithDays:(NSArray<NSNumber *> *)days completion:(ARILabelScriptWeekdayPickerCompletion)completion {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        self.title = @"요일";
        _selectedDays = [NSMutableOrderedSet orderedSetWithArray:ARILabelScriptInlineSortedDays(days)];
        if(_selectedDays.count == 0) {
            [_selectedDays addObject:@1];
        }
        _completion = [completion copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = kARIPrefTintColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                            target:self
                                                                                            action:@selector(saveSelection)];
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
    return 7;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"Weekday";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if(!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }

    NSInteger weekday = indexPath.row + 1;
    cell.textLabel.text = ARILabelScriptInlineWeekdayTitle(weekday);
    cell.accessoryType = [_selectedDays containsObject:@(weekday)] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSNumber *weekday = @(indexPath.row + 1);
    if([_selectedDays containsObject:weekday]) {
        if(_selectedDays.count > 1) {
            [_selectedDays removeObject:weekday];
        }
    } else {
        [_selectedDays addObject:weekday];
    }
    [tableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)saveSelection {
    if(_completion) {
        _completion(ARILabelScriptInlineSortedDays(_selectedDays.array));
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end

@interface ARILabelScriptActionCatalogController : UITableViewController <UISearchResultsUpdating>
- (instancetype)initWithInitialQuery:(NSString *)initialQuery selectionHandler:(ARILabelScriptActionSelectionHandler)selectionHandler;
@end

@implementation ARILabelScriptActionCatalogController {
    NSArray<NSDictionary *> *_definitions;
    NSArray<NSDictionary *> *_filteredDefinitions;
    UISearchController *_searchController;
    NSString *_initialQuery;
    ARILabelScriptActionSelectionHandler _selectionHandler;
}

- (instancetype)initWithInitialQuery:(NSString *)initialQuery selectionHandler:(ARILabelScriptActionSelectionHandler)selectionHandler {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        _definitions = ARILabelScriptInlineActionDefinitions();
        _filteredDefinitions = _definitions;
        _initialQuery = [initialQuery copy] ?: @"";
        _selectionHandler = [selectionHandler copy];
        self.title = @"액션 추가";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = kARIPrefTintColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           target:self
                                                                                           action:@selector(closeCatalog)];

    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchResultsUpdater = self;
    _searchController.searchBar.placeholder = @"액션 검색";
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    if(_initialQuery.length > 0) {
        _searchController.searchBar.text = _initialQuery;
    }
    [self _reloadFilteredDefinitions];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)closeCatalog {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)_reloadFilteredDefinitions {
    NSString *query = [[_searchController.searchBar.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if(query.length == 0) {
        _filteredDefinitions = _definitions;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *definition, __unused NSDictionary<NSString *,id> *bindings) {
            NSString *type = [definition[@"type"] lowercaseString];
            NSString *title = [definition[@"title"] lowercaseString];
            NSString *summary = [definition[@"summary"] lowercaseString];
            return [type containsString:query] || [title containsString:query] || [summary containsString:query];
        }];
        _filteredDefinitions = [_definitions filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(__unused UISearchController *)searchController {
    [self _reloadFilteredDefinitions];
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
    return MAX((NSInteger)_filteredDefinitions.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if(_filteredDefinitions.count == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = @"검색 결과 없음";
        cell.detailTextLabel.text = @"다른 이름으로 찾아보세요.";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    static NSString *identifier = @"ActionDefinition";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if(!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    NSDictionary *definition = _filteredDefinitions[indexPath.row];
    NSString *type = definition[@"type"];
    UIColor *tintColor = ARILabelScriptInlineBlockTint(type);
    cell.textLabel.text = definition[@"title"];
    cell.detailTextLabel.text = definition[@"summary"];
    cell.imageView.image = [[[UIImage systemImageNamed:definition[@"symbol"]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] copy];
    cell.imageView.tintColor = tintColor;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.row >= _filteredDefinitions.count) {
        return;
    }

    NSString *type = _filteredDefinitions[indexPath.row][@"type"];
    if(_selectionHandler) {
        _selectionHandler(type);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface ARILabelScriptConditionCatalogController : UITableViewController <UISearchResultsUpdating>
- (instancetype)initWithTitle:(NSString *)title
               nestedOnly:(BOOL)nestedOnly
             initialQuery:(NSString *)initialQuery
         selectionHandler:(ARILabelScriptConditionSelectionHandler)selectionHandler;
@end

@implementation ARILabelScriptConditionCatalogController {
    NSArray<NSDictionary *> *_definitions;
    NSArray<NSDictionary *> *_filteredDefinitions;
    UISearchController *_searchController;
    NSString *_initialQuery;
    BOOL _nestedOnly;
    ARILabelScriptConditionSelectionHandler _selectionHandler;
}

- (instancetype)initWithTitle:(NSString *)title
                   nestedOnly:(BOOL)nestedOnly
                 initialQuery:(NSString *)initialQuery
             selectionHandler:(ARILabelScriptConditionSelectionHandler)selectionHandler {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        self.title = title.length > 0 ? title : @"조건 선택";
        _nestedOnly = nestedOnly;
        _definitions = ARILabelScriptInlineFilteredConditionDefinitions(nestedOnly);
        _filteredDefinitions = _definitions;
        _initialQuery = [initialQuery copy] ?: @"";
        _selectionHandler = [selectionHandler copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = kARIPrefTintColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           target:self
                                                                                           action:@selector(closeCatalog)];

    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchResultsUpdater = self;
    _searchController.searchBar.placeholder = _nestedOnly ? @"하위 조건 검색" : @"조건 검색";
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    if(_initialQuery.length > 0) {
        _searchController.searchBar.text = _initialQuery;
    }
    [self _reloadFilteredDefinitions];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)closeCatalog {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)_reloadFilteredDefinitions {
    NSString *query = [[_searchController.searchBar.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if(query.length == 0) {
        _filteredDefinitions = _definitions;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *definition, __unused NSDictionary<NSString *,id> *bindings) {
            NSString *type = [definition[@"type"] lowercaseString];
            NSString *title = [definition[@"title"] lowercaseString];
            NSString *summary = [definition[@"summary"] lowercaseString];
            return [type containsString:query] || [title containsString:query] || [summary containsString:query];
        }];
        _filteredDefinitions = [_definitions filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(__unused UISearchController *)searchController {
    [self _reloadFilteredDefinitions];
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
    return MAX((NSInteger)_filteredDefinitions.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if(_filteredDefinitions.count == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = @"검색 결과 없음";
        cell.detailTextLabel.text = @"다른 이름으로 찾아보세요.";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    static NSString *identifier = @"ConditionDefinition";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if(!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    NSDictionary *definition = _filteredDefinitions[indexPath.row];
    NSString *type = definition[@"type"];
    UIColor *tintColor = ARILabelScriptInlineConditionTint(type);
    cell.textLabel.text = definition[@"title"];
    cell.detailTextLabel.text = definition[@"summary"];
    cell.imageView.image = [[[UIImage systemImageNamed:ARILabelScriptInlineConditionSymbol(type)] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] copy];
    cell.imageView.tintColor = tintColor;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.row >= _filteredDefinitions.count) {
        return;
    }

    NSString *type = _filteredDefinitions[indexPath.row][@"type"];
    if(_selectionHandler) {
        _selectionHandler(type);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface ARILabelScriptConditionEditorController : UITableViewController
- (instancetype)initWithCondition:(NSMutableDictionary *)condition title:(NSString *)title applyHandler:(ARILabelScriptConditionApplyHandler)applyHandler;
@end

@implementation ARILabelScriptConditionEditorController {
    NSMutableDictionary *_condition;
    ARILabelScriptConditionApplyHandler _applyHandler;
}

- (instancetype)initWithCondition:(NSMutableDictionary *)condition title:(NSString *)title applyHandler:(ARILabelScriptConditionApplyHandler)applyHandler {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        id copiedCondition = ARILabelScriptInlineDeepMutableCopy(condition ?: ARILabelScriptInlineDefaultCondition(@"always"));
        _condition = ARILabelScriptInlineMutableDictionaryValue(copiedCondition);
        self.title = title.length > 0 ? title : @"조건";
        _applyHandler = [applyHandler copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = kARIPrefTintColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           target:self
                                                                                           action:@selector(cancelEditing)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                            target:self
                                                                                            action:@selector(applyEditing)];
}

- (NSString *)_type {
    return [_condition[@"type"] isKindOfClass:[NSString class]] ? _condition[@"type"] : @"always";
}

- (void)cancelEditing {
    if(self.navigationController.presentingViewController && self.navigationController.viewControllers.firstObject == self) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)applyEditing {
    if(_applyHandler) {
        _applyHandler(ARILabelScriptInlineMutableDictionaryValue(ARILabelScriptInlineDeepMutableCopy(_condition)));
    }
    if(self.navigationController.presentingViewController && self.navigationController.viewControllers.firstObject == self) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)_showTextInputWithTitle:(NSString *)title
                    placeholder:(NSString *)placeholder
                    initialText:(NSString *)initialText
                   keyboardType:(UIKeyboardType)keyboardType
                     completion:(void (^)(NSString *text))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = placeholder;
        textField.text = initialText;
        textField.keyboardType = keyboardType;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"완료"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        if(completion) {
            completion(alert.textFields.firstObject.text ?: @"");
        }
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)_pushTimePickerWithTitle:(NSString *)title
                           value:(double)value
                 allowsEndOfDay:(BOOL)allowsEndOfDay
                      completion:(ARILabelScriptTimePickerCompletion)completion {
    ARILabelScriptInlineTimePickerController *controller = [[ARILabelScriptInlineTimePickerController alloc] initWithTitle:title
                                                                                                                       value:value
                                                                                                              allowsEndOfDay:allowsEndOfDay
                                                                                                                  completion:^(double selectedValue) {
        if(completion) {
            completion(selectedValue);
        }
        [self.tableView reloadData];
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)_pushWeekdayPickerWithDays:(NSArray<NSNumber *> *)days completion:(ARILabelScriptWeekdayPickerCompletion)completion {
    ARILabelScriptInlineWeekdayPickerController *controller = [[ARILabelScriptInlineWeekdayPickerController alloc] initWithDays:days
                                                                                                                        completion:^(NSArray<NSNumber *> *selectedDays) {
        if(completion) {
            completion(selectedDays);
        }
        [self.tableView reloadData];
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)_resetForConditionType:(NSString *)type {
    [_condition removeAllObjects];
    [_condition addEntriesFromDictionary:ARILabelScriptInlineDefaultCondition(type)];
    [self.tableView reloadData];
}

- (void)_presentConditionCatalogWithTitle:(NSString *)title nestedOnly:(BOOL)nestedOnly selection:(ARILabelScriptConditionSelectionHandler)selection {
    ARILabelScriptConditionCatalogController *controller = [[ARILabelScriptConditionCatalogController alloc] initWithTitle:title
                                                                                                                  nestedOnly:nestedOnly
                                                                                                                initialQuery:@""
                                                                                                            selectionHandler:selection];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)_presentConditionTypeSheet {
    [self _presentConditionCatalogWithTitle:@"조건 종류"
                                 nestedOnly:NO
                                  selection:^(NSString *type) {
        [self _resetForConditionType:type];
    }];
}

- (NSString *)_editorKind {
    return ARILabelScriptInlineConditionEditorKind([self _type]);
}

- (NSMutableArray *)_conditionList {
    return ARILabelScriptInlineEnsureMutableArray(_condition, @"conditions");
}

- (NSMutableDictionary *)_nestedConditionDictionary {
    NSMutableDictionary *nested = ARILabelScriptInlineEnsureMutableDictionary(_condition, @"condition");
    if(nested.count == 0) {
        nested = ARILabelScriptInlineDefaultCondition(@"battery_charging");
        _condition[@"condition"] = nested;
    }
    return nested;
}

- (void)_pushNestedConditionEditorWithCondition:(NSMutableDictionary *)nested
                                          title:(NSString *)title
                                          apply:(void (^)(NSMutableDictionary *condition))apply {
    __weak typeof(self) weakSelf = self;
    ARILabelScriptConditionEditorController *controller = [[ARILabelScriptConditionEditorController alloc] initWithCondition:nested
                                                                                                                    title:title
                                                                                                             applyHandler:^(NSMutableDictionary *condition) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if(!strongSelf) return;
        if(apply) {
            apply(condition);
        }
        [strongSelf.tableView reloadData];
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(section == 0) {
        return 1;
    }

    NSString *kind = [self _editorKind];
    if([kind isEqualToString:@"time"]) return 2;
    if([kind isEqualToString:@"weekday"] ||
       [kind isEqualToString:@"query"] ||
       [kind isEqualToString:@"temperature"] ||
       [kind isEqualToString:@"battery"] ||
       [kind isEqualToString:@"nested"]) {
        return 1;
    }
    if([kind isEqualToString:@"group"]) {
        return [self _conditionList].count + 1;
    }
    return 0;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if(section == 0) {
        return @"종류";
    }

    NSString *kind = [self _editorKind];
    if([kind isEqualToString:@"group"]) {
        return @"하위 조건";
    }
    if([kind isEqualToString:@"nested"]) {
        return @"대상";
    }
    if([kind isEqualToString:@"none"] || [kind isEqualToString:@"summary"]) {
        return nil;
    }
    return @"값";
}

- (UITableViewCell *)_valueCellWithTitle:(NSString *)title value:(NSString *)value accessory:(UITableViewCellAccessoryType)accessory {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = value;
    cell.accessoryType = accessory;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *type = [self _type];
    NSString *kind = [self _editorKind];
    if(indexPath.section == 0) {
        return [self _valueCellWithTitle:@"조건" value:ARILabelScriptInlineConditionTitle(type) accessory:UITableViewCellAccessoryDisclosureIndicator];
    }

    if([kind isEqualToString:@"time"]) {
        if(indexPath.row == 0) {
            double start = [_condition[@"start"] respondsToSelector:@selector(doubleValue)] ? [_condition[@"start"] doubleValue] : 0.0;
            return [self _valueCellWithTitle:@"시작" value:ARILabelScriptInlineFormattedTimeValue(start) accessory:UITableViewCellAccessoryDisclosureIndicator];
        }
        double end = [_condition[@"end"] respondsToSelector:@selector(doubleValue)] ? [_condition[@"end"] doubleValue] : 24.0;
        return [self _valueCellWithTitle:@"종료" value:ARILabelScriptInlineFormattedTimeValue(end) accessory:UITableViewCellAccessoryDisclosureIndicator];
    }

    if([kind isEqualToString:@"weekday"]) {
        NSArray *days = [_condition[@"days"] isKindOfClass:[NSArray class]] ? _condition[@"days"] : @[];
        return [self _valueCellWithTitle:@"요일" value:ARILabelScriptInlineWeekdaySummary(days) accessory:UITableViewCellAccessoryDisclosureIndicator];
    }

    if([kind isEqualToString:@"query"]) {
        NSString *query = [_condition[@"query"] isKindOfClass:[NSString class]] ? _condition[@"query"] : @"";
        return [self _valueCellWithTitle:@"키워드" value:(query.length > 0 ? query : @"입력") accessory:UITableViewCellAccessoryDisclosureIndicator];
    }

    if([kind isEqualToString:@"temperature"]) {
        double value = [_condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [_condition[@"value"] doubleValue] : 0.0;
        return [self _valueCellWithTitle:@"온도" value:ARILabelScriptInlineFormattedMetricValue(value, @"°") accessory:UITableViewCellAccessoryDisclosureIndicator];
    }

    if([kind isEqualToString:@"battery"]) {
        double value = [_condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [_condition[@"value"] doubleValue] : 0.0;
        return [self _valueCellWithTitle:@"배터리" value:ARILabelScriptInlineFormattedMetricValue(value, @"%") accessory:UITableViewCellAccessoryDisclosureIndicator];
    }

    if([kind isEqualToString:@"group"]) {
        NSMutableArray *conditions = [self _conditionList];
        if(indexPath.row >= conditions.count) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.textLabel.text = @"조건 추가";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.imageView.image = [[UIImage systemImageNamed:@"plus.circle.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            cell.imageView.tintColor = [UIColor systemBlueColor];
            return cell;
        }
        NSDictionary *nested = [conditions[indexPath.row] isKindOfClass:[NSDictionary class]] ? conditions[indexPath.row] : @{};
        return [self _valueCellWithTitle:[NSString stringWithFormat:@"조건 %ld", (long)indexPath.row + 1]
                                    value:ARILabelScriptInlineConditionSummary(nested)
                                accessory:UITableViewCellAccessoryDisclosureIndicator];
    }

    if([kind isEqualToString:@"nested"]) {
        NSMutableDictionary *nested = [self _nestedConditionDictionary];
        NSString *summary = nested.count > 0 ? ARILabelScriptInlineConditionSummary(nested) : @"설정";
        return [self _valueCellWithTitle:@"조건" value:summary accessory:UITableViewCellAccessoryDisclosureIndicator];
    }

    return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSString *type = [self _type];
    NSString *kind = [self _editorKind];
    if(indexPath.section == 0) {
        [self _presentConditionTypeSheet];
        return;
    }

    if([kind isEqualToString:@"time"]) {
        if(indexPath.row == 0) {
            double value = [_condition[@"start"] respondsToSelector:@selector(doubleValue)] ? [_condition[@"start"] doubleValue] : 0.0;
            [self _pushTimePickerWithTitle:@"시작" value:value allowsEndOfDay:NO completion:^(double selectedValue) {
                _condition[@"start"] = @(selectedValue);
            }];
        } else {
            double value = [_condition[@"end"] respondsToSelector:@selector(doubleValue)] ? [_condition[@"end"] doubleValue] : 24.0;
            [self _pushTimePickerWithTitle:@"종료" value:value allowsEndOfDay:YES completion:^(double selectedValue) {
                _condition[@"end"] = @(selectedValue);
            }];
        }
        return;
    }

    if([kind isEqualToString:@"weekday"]) {
        NSArray *days = [_condition[@"days"] isKindOfClass:[NSArray class]] ? _condition[@"days"] : @[];
        [self _pushWeekdayPickerWithDays:days completion:^(NSArray<NSNumber *> *selectedDays) {
            _condition[@"days"] = [selectedDays mutableCopy];
        }];
        return;
    }

    if([kind isEqualToString:@"query"]) {
        NSString *title = [type isEqualToString:@"location_contains"] ? @"지역 키워드" : @"날씨 키워드";
        NSString *placeholder = [type isEqualToString:@"location_contains"] ? @"예: 서울" : @"예: 비";
        NSString *query = [_condition[@"query"] isKindOfClass:[NSString class]] ? _condition[@"query"] : @"";
        [self _showTextInputWithTitle:title
                          placeholder:placeholder
                          initialText:query
                         keyboardType:UIKeyboardTypeDefault
                           completion:^(NSString *text) {
            _condition[@"query"] = text ?: @"";
        }];
        return;
    }

    if([kind isEqualToString:@"temperature"]) {
        NSString *value = [_condition[@"value"] respondsToSelector:@selector(stringValue)] ? [_condition[@"value"] stringValue] : @"0";
        [self _showTextInputWithTitle:@"기준 온도"
                          placeholder:@"예: 20"
                          initialText:value
                         keyboardType:UIKeyboardTypeDecimalPad
                           completion:^(NSString *text) {
            _condition[@"value"] = @([text doubleValue]);
        }];
        return;
    }

    if([kind isEqualToString:@"battery"]) {
        NSString *value = [_condition[@"value"] respondsToSelector:@selector(stringValue)] ? [_condition[@"value"] stringValue] : @"50";
        [self _showTextInputWithTitle:@"배터리 값"
                          placeholder:@"예: 50"
                          initialText:value
                         keyboardType:UIKeyboardTypeDecimalPad
                           completion:^(NSString *text) {
            _condition[@"value"] = @(MAX(0.0, MIN(100.0, [text doubleValue])));
        }];
        return;
    }

    if([kind isEqualToString:@"group"]) {
        NSMutableArray *conditions = [self _conditionList];
        if(indexPath.row >= conditions.count) {
            [self _presentConditionCatalogWithTitle:@"하위 조건 추가"
                                         nestedOnly:YES
                                          selection:^(NSString *simpleType) {
                NSMutableDictionary *nested = ARILabelScriptInlineDefaultCondition(simpleType);
                [self _pushNestedConditionEditorWithCondition:nested
                                                        title:@"하위 조건"
                                                        apply:^(NSMutableDictionary *condition) {
                    [conditions addObject:ARILabelScriptInlineMutableDictionaryValue(condition)];
                }];
            }];
            return;
        }

        NSMutableDictionary *nested = ARILabelScriptInlineMutableDictionaryValue(conditions[indexPath.row]);
        conditions[indexPath.row] = nested;
        [self _pushNestedConditionEditorWithCondition:nested
                                                title:[NSString stringWithFormat:@"조건 %ld", (long)indexPath.row + 1]
                                                apply:^(NSMutableDictionary *condition) {
            conditions[indexPath.row] = ARILabelScriptInlineMutableDictionaryValue(condition);
        }];
        return;
    }

    if([kind isEqualToString:@"nested"]) {
        NSMutableDictionary *nested = [self _nestedConditionDictionary];
        [self _pushNestedConditionEditorWithCondition:nested
                                                title:@"하위 조건"
                                                apply:^(NSMutableDictionary *condition) {
            _condition[@"condition"] = ARILabelScriptInlineMutableDictionaryValue(condition);
        }];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if(indexPath.section != 1) {
        return NO;
    }
    if([[self _editorKind] isEqualToString:@"group"]) {
        return indexPath.row < [self _conditionList].count;
    }
    return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if(editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    if([[self _editorKind] isEqualToString:@"group"]) {
        NSMutableArray *conditions = [self _conditionList];
        if(indexPath.row < conditions.count) {
            [conditions removeObjectAtIndex:indexPath.row];
            [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }
}

@end

@implementation ARILabelScriptVisualEditorController {
    NSMutableDictionary *_rootScript;
    NSMutableArray *_steps;
    BOOL _isRootController;
    NSUserDefaults *_preferences;
    NSMutableArray<ARILabelScriptVisualRow *> *_rows;
    UIVisualEffectView *_dockView;
    UILabel *_dockHintLabel;
    UIButton *_addButton;
    UIButton *_undoButton;
    UIButton *_redoButton;
    NSMutableArray<NSString *> *_undoStack;
    NSMutableArray<NSString *> *_redoStack;
    NSMutableArray *_selectedInsertionContainer;
    NSInteger _selectedInsertionIndex;
    NSMutableSet<NSValue *> *_collapsedBlockPointers;
    NSString *_savedSource;
}

- (instancetype)initRootControllerWithScript:(NSMutableDictionary *)script {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        _rootScript = ARILabelScriptInlineMutableDictionaryValue(script);
        _steps = ARILabelScriptInlineMutableArrayValue(_rootScript[@"steps"]);
        _rootScript[@"steps"] = _steps;
        _rootScript[@"loop"] = _rootScript[@"loop"] ?: @YES;
        _isRootController = YES;
        self.title = @"스크립트 에디터";
        _preferences = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
        _undoStack = [NSMutableArray new];
        _redoStack = [NSMutableArray new];
        _collapsedBlockPointers = [NSMutableSet new];
        _savedSource = [[ARILabelScriptCompiler sourceFromScriptDictionary:_rootScript error:nil] copy] ?: @"";
    }
    return self;
}

- (instancetype)initWithSteps:(NSMutableArray *)steps title:(NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        _steps = ARILabelScriptInlineMutableArrayValue(steps);
        _isRootController = NO;
        self.title = title.length > 0 ? title : @"스크립트 에디터";
        _collapsedBlockPointers = [NSMutableSet new];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = kARIPrefTintColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 78.0;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:_isRootController ? @"완료" : @"저장"
                                                                   style:UIBarButtonItemStyleDone
                                                                  target:self
                                                                  action:@selector(saveScript)];
    self.navigationItem.rightBarButtonItem = doneButton;

    UIImageView *titleIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"curlybraces.square"]];
    titleIcon.tintColor = [UIColor secondaryLabelColor];
    titleIcon.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = self.title;
    titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[ titleIcon, titleLabel ]];
    titleStack.axis = UILayoutConstraintAxisHorizontal;
    titleStack.spacing = 8.0;
    titleStack.alignment = UIStackViewAlignmentCenter;
    self.navigationItem.titleView = titleStack;

    [NSLayoutConstraint activateConstraints:@[
        [titleIcon.widthAnchor constraintEqualToConstant:16.0],
        [titleIcon.heightAnchor constraintEqualToConstant:16.0]
    ]];

    [self _configureDock];
    [self _rebuildRows];
    [self _refreshDockState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if(_isRootController) {
        BOOL presentedModally = self.navigationController.presentingViewController && self.navigationController.viewControllers.firstObject == self;
        self.navigationItem.hidesBackButton = !presentedModally;
        if(presentedModally) {
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                                   target:self
                                                                                                   action:@selector(closeEditor)];
        } else {
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"뒤로"
                                                                                      style:UIBarButtonItemStylePlain
                                                                                     target:self
                                                                                     action:@selector(closeEditor)];
        }
    }
    [self _rebuildRows];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat dockHeight = 84.0;
    self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, dockHeight + self.view.safeAreaInsets.bottom + 20.0, 0.0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
}

- (void)_configureDock {
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
    _dockView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _dockView.translatesAutoresizingMaskIntoConstraints = NO;
    _dockView.layer.cornerRadius = 24.0;
    _dockView.layer.cornerCurve = kCACornerCurveContinuous;
    if(@available(iOS 11.0, *)) {
        _dockView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    _dockView.clipsToBounds = YES;
    [self.view addSubview:_dockView];

    _addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _addButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_addButton setImage:[UIImage systemImageNamed:@"plus.circle.fill"] forState:UIControlStateNormal];
    [_addButton setTitle:@"액션 추가" forState:UIControlStateNormal];
    _addButton.tintColor = [UIColor systemBlueColor];
    [_addButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    _addButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    _addButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    _addButton.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    _addButton.imageEdgeInsets = UIEdgeInsetsMake(0.0, -4.0, 0.0, 4.0);
    [_addButton addTarget:self action:@selector(addButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_dockView.contentView addSubview:_addButton];

    _undoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _undoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_undoButton setImage:[UIImage systemImageNamed:@"arrow.uturn.backward.circle"] forState:UIControlStateNormal];
    [_undoButton addTarget:self action:@selector(undoButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_dockView.contentView addSubview:_undoButton];

    _redoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _redoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_redoButton setImage:[UIImage systemImageNamed:@"arrow.uturn.forward.circle"] forState:UIControlStateNormal];
    [_redoButton addTarget:self action:@selector(redoButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_dockView.contentView addSubview:_redoButton];

    [NSLayoutConstraint activateConstraints:@[
        [_dockView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [_dockView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [_dockView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_dockView.heightAnchor constraintEqualToConstant:74.0],

        [_addButton.centerXAnchor constraintEqualToAnchor:_dockView.contentView.centerXAnchor],
        [_addButton.topAnchor constraintEqualToAnchor:_dockView.contentView.topAnchor constant:12.0],
        [_addButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12.0],

        [_undoButton.centerYAnchor constraintEqualToAnchor:_addButton.centerYAnchor],
        [_redoButton.centerYAnchor constraintEqualToAnchor:_addButton.centerYAnchor],
        [_undoButton.trailingAnchor constraintEqualToAnchor:_addButton.leadingAnchor constant:-20.0],
        [_redoButton.leadingAnchor constraintEqualToAnchor:_addButton.trailingAnchor constant:20.0],

        [_addButton.widthAnchor constraintGreaterThanOrEqualToConstant:112.0],
        [_addButton.heightAnchor constraintEqualToConstant:34.0],
        [_undoButton.widthAnchor constraintEqualToConstant:34.0],
        [_undoButton.heightAnchor constraintEqualToConstant:34.0],
        [_redoButton.widthAnchor constraintEqualToConstant:34.0],
        [_redoButton.heightAnchor constraintEqualToConstant:34.0]
    ]];
}

- (NSString *)_dockPlaceholderText {
    if(!_selectedInsertionContainer) {
        return @"추가할 위치를 고르고 액션을 넣습니다.";
    }

    NSInteger count = (NSInteger)_selectedInsertionContainer.count;
    if(_selectedInsertionIndex <= 0) {
        return @"맨 앞에 액션 추가";
    }
    if(_selectedInsertionIndex >= count) {
        return @"맨 뒤에 액션 추가";
    }
    return @"여기에 액션 추가";
}

- (void)_refreshDockState {
    BOOL canUndo = _isRootController && _undoStack.count > 0;
    BOOL canRedo = _isRootController && _redoStack.count > 0;
    _undoButton.enabled = canUndo;
    _redoButton.enabled = canRedo;
    _undoButton.alpha = canUndo ? 1.0 : 0.4;
    _redoButton.alpha = canRedo ? 1.0 : 0.4;
}

- (void)_postReloadNotification {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("me.lau.Atria/ReloadPrefs"),
                                         NULL,
                                         NULL,
                                         YES);
}

- (void)_showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"확인" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)_currentSourceForUndo {
    NSDictionary *script = _isRootController ? _rootScript : @{ @"loop": @YES, @"steps": _steps ?: @[] };
    return [ARILabelScriptCompiler sourceFromScriptDictionary:script error:nil];
}

- (void)_recordUndoSnapshotIfNeeded {
    if(!_isRootController) {
        return;
    }
    NSString *source = [self _currentSourceForUndo];
    if(source.length == 0) {
        return;
    }
    [_undoStack addObject:source];
    if(_undoStack.count > 40) {
        [_undoStack removeObjectAtIndex:0];
    }
    [_redoStack removeAllObjects];
    [self _refreshDockState];
}

- (void)_mutateScript:(void (^)(void))mutation {
    if(!mutation) {
        return;
    }
    [self _recordUndoSnapshotIfNeeded];
    mutation();
    [self _rebuildRows];
}

- (void)_restoreRootScriptFromSource:(NSString *)source {
    if(!_isRootController || source.length == 0) {
        return;
    }
    NSError *error = nil;
    NSMutableDictionary *script = [ARILabelScriptCompiler mutableScriptDictionaryFromSource:source error:&error];
    if(!script) {
        [self _showAlertWithTitle:@"복원 실패" message:error.localizedDescription ?: @"스크립트를 읽을 수 없습니다."];
        return;
    }

    _rootScript = ARILabelScriptInlineMutableDictionaryValue(script);
    _steps = ARILabelScriptInlineMutableArrayValue(_rootScript[@"steps"]);
    _rootScript[@"steps"] = _steps;
    _rootScript[@"loop"] = _rootScript[@"loop"] ?: @YES;
    _selectedInsertionContainer = nil;
    _selectedInsertionIndex = 0;
    [_collapsedBlockPointers removeAllObjects];
    [self _rebuildRows];
}

- (BOOL)_container:(NSMutableArray *)target existsInSteps:(NSArray *)steps {
    if(!target || ![steps isKindOfClass:[NSArray class]]) {
        return NO;
    }
    if(target == steps) {
        return YES;
    }

    for(id item in steps) {
        NSDictionary *block = [item isKindOfClass:[NSDictionary class]] ? item : nil;
        NSString *type = [block[@"type"] isKindOfClass:[NSString class]] ? block[@"type"] : @"";
        for(NSDictionary *containerDefinition in ARILabelScriptInlineBlockContainers(type)) {
            NSString *key = [containerDefinition[@"key"] isKindOfClass:[NSString class]] ? containerDefinition[@"key"] : @"steps";
            NSArray *nestedSteps = [block[key] isKindOfClass:[NSArray class]] ? block[key] : nil;
            if([self _container:target existsInSteps:nestedSteps]) {
                return YES;
            }
        }
    }

    return NO;
}

- (void)_normalizeSelectedInsertionAnchor {
    if(!_selectedInsertionContainer) {
        _selectedInsertionIndex = 0;
        return;
    }
    if(![self _container:_selectedInsertionContainer existsInSteps:_steps]) {
        _selectedInsertionContainer = nil;
        _selectedInsertionIndex = 0;
        return;
    }
    _selectedInsertionIndex = MAX(0, MIN(_selectedInsertionIndex, (NSInteger)_selectedInsertionContainer.count));
}

- (BOOL)_hasUnsavedChanges {
    if(!_isRootController) {
        return NO;
    }
    NSString *currentSource = [self _currentSourceForUndo] ?: @"";
    NSString *savedSource = _savedSource ?: @"";
    return ![currentSource isEqualToString:savedSource];
}

- (void)_finishClosingEditor {
    if(self.navigationController.presentingViewController && self.navigationController.viewControllers.firstObject == self) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (NSValue *)_collapseKeyForBlock:(NSMutableDictionary *)block {
    return [NSValue valueWithPointer:(__bridge const void *)block];
}

- (BOOL)_isBlockCollapsed:(NSMutableDictionary *)block {
    if(!block) {
        return NO;
    }
    return [_collapsedBlockPointers containsObject:[self _collapseKeyForBlock:block]];
}

- (void)_setBlockCollapsed:(BOOL)collapsed forBlock:(NSMutableDictionary *)block {
    if(!block) {
        return;
    }
    NSValue *key = [self _collapseKeyForBlock:block];
    if(collapsed) {
        [_collapsedBlockPointers addObject:key];
    } else {
        [_collapsedBlockPointers removeObject:key];
    }
}

- (NSInteger)_hiddenDescendantCountForBlock:(NSDictionary *)block {
    NSString *type = [block[@"type"] isKindOfClass:[NSString class]] ? block[@"type"] : @"";
    NSArray<NSDictionary *> *containers = ARILabelScriptInlineBlockContainers(type);
    if(containers.count == 0) {
        return 0;
    }

    NSInteger total = 1;
    for(NSDictionary *containerDefinition in containers) {
        NSString *key = [containerDefinition[@"key"] isKindOfClass:[NSString class]] ? containerDefinition[@"key"] : @"steps";
        NSArray *steps = [block[key] isKindOfClass:[NSArray class]] ? block[key] : @[];
        total += 2;
        total += steps.count;
        for(NSDictionary *item in steps) {
            total += [self _hiddenDescendantCountForBlock:item];
        }
    }
    return total;
}

- (void)undoButtonTapped {
    if(!_isRootController || _undoStack.count == 0) {
        return;
    }
    NSString *currentSource = [self _currentSourceForUndo];
    if(currentSource.length > 0) {
        [_redoStack addObject:currentSource];
    }
    NSString *source = _undoStack.lastObject;
    [_undoStack removeLastObject];
    [self _restoreRootScriptFromSource:source];
    [self _refreshDockState];
}

- (void)redoButtonTapped {
    if(!_isRootController || _redoStack.count == 0) {
        return;
    }
    NSString *currentSource = [self _currentSourceForUndo];
    if(currentSource.length > 0) {
        [_undoStack addObject:currentSource];
    }
    NSString *source = _redoStack.lastObject;
    [_redoStack removeLastObject];
    [self _restoreRootScriptFromSource:source];
    [self _refreshDockState];
}

- (void)_selectInsertionContainer:(NSMutableArray *)container index:(NSInteger)index {
    _selectedInsertionContainer = container;
    _selectedInsertionIndex = index;
    [self _refreshDockState];
    [self.tableView reloadData];
}

- (BOOL)_rowIsSelectedAnchor:(ARILabelScriptVisualRow *)row {
    if(row.kind != ARILabelScriptVisualRowKindInsert && row.kind != ARILabelScriptVisualRowKindEmpty) {
        return NO;
    }
    return row.insertionContainer == _selectedInsertionContainer && row.insertionIndex == _selectedInsertionIndex;
}

- (void)_activateRow:(ARILabelScriptVisualRow *)row sourceView:(UIView *)sourceView {
    if(!row) {
        return;
    }

    UIView *resolvedSourceView = sourceView ?: self.view;
    CGRect resolvedRect = sourceView ? sourceView.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    if((row.kind == ARILabelScriptVisualRowKindInsert || row.kind == ARILabelScriptVisualRowKindEmpty) && row.insertionContainer) {
        [self _selectInsertionContainer:row.insertionContainer index:row.insertionIndex];
        [self _presentAddActionSheetFromView:resolvedSourceView rect:resolvedRect container:row.insertionContainer index:row.insertionIndex];
        return;
    }

    if(row.kind == ARILabelScriptVisualRowKindAction) {
        [self _presentRowMenuForRow:row sourceView:resolvedSourceView];
    }
}

- (void)_appendInsertRowWithTitle:(NSString *)title
                            depth:(NSInteger)depth
                        container:(NSMutableArray *)container
                            index:(NSInteger)index
                        railDepths:(NSArray<NSNumber *> *)railDepths
                             rows:(NSMutableArray<ARILabelScriptVisualRow *> *)rows {
    ARILabelScriptVisualRow *row = [ARILabelScriptVisualRow new];
    row.kind = ARILabelScriptVisualRowKindInsert;
    row.accessoryKind = ARILabelScriptVisualAccessoryKindInsert;
    row.depth = depth;
    row.title = title.length > 0 ? title : @"액션 추가";
    row.symbolName = @"plus.circle";
    row.tintColor = [UIColor systemBlueColor];
    row.insertionContainer = container;
    row.insertionIndex = index;
    row.railDepths = railDepths;
    [rows addObject:row];
}

- (void)_appendContainerRowsForBlock:(NSMutableDictionary *)block
                                type:(NSString *)type
                               depth:(NSInteger)depth
                         activeRails:(NSArray<NSNumber *> *)activeRails
                                rows:(NSMutableArray<ARILabelScriptVisualRow *> *)rows {
    NSArray<NSDictionary *> *containers = ARILabelScriptInlineBlockContainers(type);
    if(containers.count == 0) {
        return;
    }

    NSArray<NSNumber *> *nestedRails = [activeRails arrayByAddingObject:@(depth + 1)];
    for(NSDictionary *containerDefinition in containers) {
        NSString *key = [containerDefinition[@"key"] isKindOfClass:[NSString class]] ? containerDefinition[@"key"] : @"steps";
        NSString *title = [containerDefinition[@"title"] isKindOfClass:[NSString class]] ? containerDefinition[@"title"] : @"내용";
        NSString *symbol = [containerDefinition[@"symbol"] isKindOfClass:[NSString class]] ? containerDefinition[@"symbol"] : @"line.3.horizontal";
        UIColor *tintColor = [containerDefinition[@"tint"] isKindOfClass:[NSString class]] ? ARILabelScriptInlineTintColorNamed(containerDefinition[@"tint"]) : kARIPrefTintColor;
        NSMutableArray *containerSteps = ARILabelScriptInlineEnsureMutableArray(block, key);

        ARILabelScriptVisualRow *groupRow = [ARILabelScriptVisualRow new];
        groupRow.kind = ARILabelScriptVisualRowKindGroup;
        groupRow.accessoryKind = ARILabelScriptVisualAccessoryKindNone;
        groupRow.depth = depth;
        groupRow.title = title;
        groupRow.symbolName = symbol;
        groupRow.tintColor = tintColor;
        groupRow.railDepths = nestedRails;
        [rows addObject:groupRow];

        [self _appendInsertRowWithTitle:(containerSteps.count == 0 ? @"액션 추가" : @"맨 앞에 추가")
                                 depth:depth + 1
                             container:containerSteps
                                 index:0
                             railDepths:nestedRails
                                  rows:rows];

        [self _appendRowsForSteps:containerSteps depth:depth + 1 activeRails:nestedRails rows:rows];

        if(containerSteps.count > 0) {
            [self _appendInsertRowWithTitle:@"맨 뒤에 추가"
                                     depth:depth + 1
                                 container:containerSteps
                                     index:containerSteps.count
                                 railDepths:nestedRails
                                      rows:rows];
        }
    }

    ARILabelScriptVisualRow *endRow = [ARILabelScriptVisualRow new];
    endRow.kind = ARILabelScriptVisualRowKindEnd;
    endRow.accessoryKind = ARILabelScriptVisualAccessoryKindNone;
    endRow.depth = depth;
    endRow.title = ARILabelScriptInlineBlockEndTitle(type);
    endRow.symbolName = @"chevron.up";
    endRow.tintColor = [UIColor tertiaryLabelColor];
    endRow.railDepths = activeRails;
    endRow.scopeRailDepth = depth + 1;
    endRow.scopeRailMode = ARILabelScriptVisualRailModeEnd;
    [rows addObject:endRow];
}

- (void)_appendRowsForSteps:(NSMutableArray *)steps
                      depth:(NSInteger)depth
                activeRails:(NSArray<NSNumber *> *)activeRails
                       rows:(NSMutableArray<ARILabelScriptVisualRow *> *)rows {
    for(NSInteger index = 0; index < (NSInteger)steps.count; index++) {
        NSMutableDictionary *block = ARILabelScriptInlineMutableDictionaryValue(steps[index]);
        steps[index] = block;

        NSString *type = [block[@"type"] isKindOfClass:[NSString class]] ? block[@"type"] : @"set_text";
        BOOL collapsible = ARILabelScriptInlineBlockIsCollapsible(type);
        BOOL collapsed = collapsible && [self _isBlockCollapsed:block];

        ARILabelScriptVisualRow *row = [ARILabelScriptVisualRow new];
        row.kind = ARILabelScriptVisualRowKindAction;
        row.accessoryKind = ARILabelScriptVisualAccessoryKindMenu;
        row.depth = depth;
        row.block = block;
        row.container = steps;
        row.index = index;
        row.insertionContainer = steps;
        row.insertionIndex = index + 1;
        row.title = ARILabelScriptInlineBlockTitle(type);
        row.symbolName = ARILabelScriptInlineBlockSymbol(type);
        row.tintColor = ARILabelScriptInlineBlockTint(type);
        row.railDepths = activeRails;
        row.collapsible = collapsible;
        row.collapsed = collapsed;
        [rows addObject:row];

        if(ARILabelScriptInlineBlockContainers(type).count > 0) {
            if(collapsed) {
                continue;
            }
            row.scopeRailDepth = depth + 1;
            row.scopeRailMode = ARILabelScriptVisualRailModeStart;
            [self _appendContainerRowsForBlock:block type:type depth:depth activeRails:activeRails rows:rows];
        }
    }
}

- (void)_rebuildRows {
    NSMutableArray<ARILabelScriptVisualRow *> *rows = [NSMutableArray new];
    if(_steps.count > 0) {
        [self _appendInsertRowWithTitle:@"맨 앞에 추가"
                                 depth:0
                             container:_steps
                                 index:0
                             railDepths:@[]
                                  rows:rows];
    }
    [self _appendRowsForSteps:_steps depth:0 activeRails:@[] rows:rows];
    if(_steps.count > 0) {
        [self _appendInsertRowWithTitle:@"맨 뒤에 추가"
                                 depth:0
                             container:_steps
                                 index:_steps.count
                             railDepths:@[]
                                  rows:rows];
    }
    if(rows.count == 0) {
        ARILabelScriptVisualRow *row = [ARILabelScriptVisualRow new];
        row.kind = ARILabelScriptVisualRowKindEmpty;
        row.accessoryKind = ARILabelScriptVisualAccessoryKindInsert;
        row.depth = 0;
        row.title = @"액션이 없습니다";
        row.symbolName = @"plus.circle";
        row.tintColor = [UIColor secondaryLabelColor];
        row.insertionContainer = _steps;
        row.insertionIndex = _steps.count;
        [rows addObject:row];
    }
    _rows = rows;
    [self _normalizeSelectedInsertionAnchor];
    [self _refreshDockState];
    [self.tableView reloadData];
}

- (NSArray<ARILabelScriptVisualPart *> *)_partsForRow:(ARILabelScriptVisualRow *)row {
    NSMutableArray<ARILabelScriptVisualPart *> *parts = [NSMutableArray new];
    if(row.kind == ARILabelScriptVisualRowKindGroup ||
       row.kind == ARILabelScriptVisualRowKindInsert ||
       row.kind == ARILabelScriptVisualRowKindEnd ||
       row.kind == ARILabelScriptVisualRowKindEmpty) {
        [parts addObject:[ARILabelScriptVisualPart partWithText:row.title ?: @""]];
        return parts;
    }

    NSString *type = [row.block[@"type"] isKindOfClass:[NSString class]] ? row.block[@"type"] : @"set_text";
    if([type isEqualToString:@"set_text"]) {
        NSString *text = [row.block[@"text"] isKindOfClass:[NSString class]] ? row.block[@"text"] : @"";
        [parts addObject:[ARILabelScriptVisualPart partWithText:@"표시 "]];
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:(text.length > 0 ? text : @"텍스트") identifier:@"text"]];
        return parts;
    }

    if([type isEqualToString:@"wait"]) {
        double seconds = [row.block[@"seconds"] respondsToSelector:@selector(doubleValue)] ? [row.block[@"seconds"] doubleValue] : 0.0;
        [parts addObject:[ARILabelScriptVisualPart partWithText:@"대기 "]];
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:[NSString stringWithFormat:@"%.1f초", seconds] identifier:@"seconds"]];
        return parts;
    }

    if([type isEqualToString:@"reload"]) {
        [parts addObject:[ARILabelScriptVisualPart partWithText:@"처음부터 다시 실행"]];
        return parts;
    }

    if([type isEqualToString:@"repeat"]) {
        NSInteger times = [row.block[@"times"] respondsToSelector:@selector(integerValue)] ? [row.block[@"times"] integerValue] : 0;
        NSString *title = times <= 0 ? @"무한" : [NSString stringWithFormat:@"%ld회", (long)times];
        [parts addObject:[ARILabelScriptVisualPart partWithText:@"반복 "]];
        [parts addObject:[ARILabelScriptVisualPart tokenWithText:title identifier:@"times"]];
        if(row.collapsed) {
            NSInteger hiddenCount = [self _hiddenDescendantCountForBlock:row.block];
            [parts addObject:[ARILabelScriptVisualPart partWithText:[NSString stringWithFormat:@" · %ld개 접힘", (long)hiddenCount]]];
        }
        return parts;
    }

    if([type isEqualToString:@"if"]) {
        NSMutableDictionary *condition = ARILabelScriptInlineEnsureMutableDictionary(row.block, @"condition");
        [parts addObject:[ARILabelScriptVisualPart partWithText:@"만약 "]];
        [parts addObjectsFromArray:ARILabelScriptInlineConditionParts(condition)];
        if(row.collapsed) {
            NSInteger hiddenCount = [self _hiddenDescendantCountForBlock:row.block];
            [parts addObject:[ARILabelScriptVisualPart partWithText:[NSString stringWithFormat:@" · %ld개 접힘", (long)hiddenCount]]];
        }
        return parts;
    }

    [parts addObject:[ARILabelScriptVisualPart partWithText:ARILabelScriptInlineBlockTitle(type)]];
    NSString *summary = ARILabelScriptInlineUnknownBlockSummary(row.block);
    if(summary.length > 0) {
        [parts addObject:[ARILabelScriptVisualPart partWithText:@" · "]];
        [parts addObject:[ARILabelScriptVisualPart partWithText:summary]];
    }
    return parts;
}

- (void)_showTextInputWithTitle:(NSString *)title
                    placeholder:(NSString *)placeholder
                    initialText:(NSString *)initialText
                   keyboardType:(UIKeyboardType)keyboardType
                     completion:(void (^)(NSString *text))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = placeholder;
        textField.text = initialText;
        textField.keyboardType = keyboardType;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"완료"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        if(completion) {
            completion(alert.textFields.firstObject.text ?: @"");
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)_presentModalTimePickerWithTitle:(NSString *)title
                                   value:(double)value
                         allowsEndOfDay:(BOOL)allowsEndOfDay
                              completion:(ARILabelScriptTimePickerCompletion)completion {
    ARILabelScriptInlineTimePickerController *controller = [[ARILabelScriptInlineTimePickerController alloc] initWithTitle:title
                                                                                                                       value:value
                                                                                                             allowsEndOfDay:allowsEndOfDay
                                                                                                                  completion:completion];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)_presentModalWeekdayPickerWithDays:(NSArray<NSNumber *> *)days completion:(ARILabelScriptWeekdayPickerCompletion)completion {
    ARILabelScriptInlineWeekdayPickerController *controller = [[ARILabelScriptInlineWeekdayPickerController alloc] initWithDays:days completion:completion];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)_presentConditionCatalogWithTitle:(NSString *)title
                               nestedOnly:(BOOL)nestedOnly
                                selection:(ARILabelScriptConditionSelectionHandler)selection {
    ARILabelScriptConditionCatalogController *controller = [[ARILabelScriptConditionCatalogController alloc] initWithTitle:title
                                                                                                                  nestedOnly:nestedOnly
                                                                                                                initialQuery:@""
                                                                                                            selectionHandler:selection];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)_presentInlineConditionTypeSheetForBlock:(NSMutableDictionary *)block {
    [self _presentConditionCatalogWithTitle:@"조건 종류"
                                 nestedOnly:NO
                                  selection:^(NSString *type) {
            [self _mutateScript:^{
                block[@"condition"] = ARILabelScriptInlineDefaultCondition(type);
            }];
    }];
}

- (void)_presentConditionEditorForBlock:(NSMutableDictionary *)block {
    NSMutableDictionary *condition = ARILabelScriptInlineEnsureMutableDictionary(block, @"condition");
    ARILabelScriptConditionEditorController *controller = [[ARILabelScriptConditionEditorController alloc] initWithCondition:condition
                                                                                                                      title:@"조건"
                                                                                                               applyHandler:^(NSMutableDictionary *updatedCondition) {
        [self _mutateScript:^{
            block[@"condition"] = ARILabelScriptInlineMutableDictionaryValue(updatedCondition);
        }];
    }];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)_presentConditionQueryInputForCondition:(NSMutableDictionary *)condition type:(NSString *)conditionType {
    NSString *query = [condition[@"query"] isKindOfClass:[NSString class]] ? condition[@"query"] : @"";
    [self _showTextInputWithTitle:ARILabelScriptInlineConditionQueryInputTitle(conditionType)
                      placeholder:ARILabelScriptInlineConditionQueryPlaceholder(conditionType)
                      initialText:query
                     keyboardType:UIKeyboardTypeDefault
                       completion:^(NSString *input) {
        [self _mutateScript:^{
            condition[@"query"] = input ?: @"";
        }];
    }];
}

- (void)_presentConditionValueInputForCondition:(NSMutableDictionary *)condition type:(NSString *)conditionType {
    NSString *initialValue = [condition[@"value"] respondsToSelector:@selector(stringValue)] ? [condition[@"value"] stringValue] : @"0";
    [self _showTextInputWithTitle:ARILabelScriptInlineConditionMetricInputTitle(conditionType)
                      placeholder:ARILabelScriptInlineConditionMetricPlaceholder(conditionType)
                      initialText:initialValue
                     keyboardType:UIKeyboardTypeDecimalPad
                       completion:^(NSString *input) {
        [self _mutateScript:^{
            double value = [input doubleValue];
            if([conditionType hasPrefix:@"battery_"]) {
                value = MAX(0.0, MIN(100.0, value));
            }
            condition[@"value"] = @(value);
        }];
    }];
}

- (BOOL)_handleConditionTokenTap:(NSString *)tokenIdentifier forBlock:(NSMutableDictionary *)block {
    if(tokenIdentifier.length == 0 || !block) {
        return NO;
    }

    NSMutableDictionary *condition = ARILabelScriptInlineEnsureMutableDictionary(block, @"condition");
    NSString *conditionType = [condition[@"type"] isKindOfClass:[NSString class]] ? condition[@"type"] : @"always";

    if([tokenIdentifier isEqualToString:@"condition"]) {
        [self _presentConditionEditorForBlock:block];
        return YES;
    }

    if([tokenIdentifier isEqualToString:@"condition_type"]) {
        [self _presentInlineConditionTypeSheetForBlock:block];
        return YES;
    }

    if([tokenIdentifier isEqualToString:@"condition_start"]) {
        double value = [condition[@"start"] respondsToSelector:@selector(doubleValue)] ? [condition[@"start"] doubleValue] : 0.0;
        [self _presentModalTimePickerWithTitle:@"시작" value:value allowsEndOfDay:NO completion:^(double selectedValue) {
            [self _mutateScript:^{
                condition[@"start"] = @(selectedValue);
            }];
        }];
        return YES;
    }

    if([tokenIdentifier isEqualToString:@"condition_end"]) {
        double value = [condition[@"end"] respondsToSelector:@selector(doubleValue)] ? [condition[@"end"] doubleValue] : 24.0;
        [self _presentModalTimePickerWithTitle:@"종료" value:value allowsEndOfDay:YES completion:^(double selectedValue) {
            [self _mutateScript:^{
                condition[@"end"] = @(selectedValue);
            }];
        }];
        return YES;
    }

    if([tokenIdentifier isEqualToString:@"condition_days"]) {
        NSArray *days = [condition[@"days"] isKindOfClass:[NSArray class]] ? condition[@"days"] : @[];
        [self _presentModalWeekdayPickerWithDays:days completion:^(NSArray<NSNumber *> *selectedDays) {
            [self _mutateScript:^{
                condition[@"days"] = [selectedDays mutableCopy];
            }];
        }];
        return YES;
    }

    if([tokenIdentifier isEqualToString:@"condition_query"]) {
        [self _presentConditionQueryInputForCondition:condition type:conditionType];
        return YES;
    }

    if([tokenIdentifier isEqualToString:@"condition_value"]) {
        [self _presentConditionValueInputForCondition:condition type:conditionType];
        return YES;
    }

    return NO;
}

- (void)_handleTokenTap:(NSString *)tokenIdentifier forRow:(ARILabelScriptVisualRow *)row {
    if(row.kind != ARILabelScriptVisualRowKindAction || tokenIdentifier.length == 0) {
        return;
    }

    NSString *type = [row.block[@"type"] isKindOfClass:[NSString class]] ? row.block[@"type"] : @"set_text";
    if([type isEqualToString:@"set_text"] && [tokenIdentifier isEqualToString:@"text"]) {
        NSString *text = [row.block[@"text"] isKindOfClass:[NSString class]] ? row.block[@"text"] : @"";
        [self _showTextInputWithTitle:@"텍스트"
                          placeholder:@"표시할 텍스트"
                          initialText:text
                         keyboardType:UIKeyboardTypeDefault
                           completion:^(NSString *input) {
            [self _mutateScript:^{
                row.block[@"text"] = input ?: @"";
            }];
        }];
        return;
    }

    if([type isEqualToString:@"wait"] && [tokenIdentifier isEqualToString:@"seconds"]) {
        NSString *seconds = [row.block[@"seconds"] respondsToSelector:@selector(stringValue)] ? [row.block[@"seconds"] stringValue] : @"2";
        [self _showTextInputWithTitle:@"대기 시간"
                          placeholder:@"예: 2 또는 0.5"
                          initialText:seconds
                         keyboardType:UIKeyboardTypeDecimalPad
                           completion:^(NSString *input) {
            [self _mutateScript:^{
                row.block[@"seconds"] = @(MAX(0.0, [input doubleValue]));
            }];
        }];
        return;
    }

    if([type isEqualToString:@"repeat"] && [tokenIdentifier isEqualToString:@"times"]) {
        NSString *times = [row.block[@"times"] respondsToSelector:@selector(stringValue)] ? [row.block[@"times"] stringValue] : @"0";
        [self _showTextInputWithTitle:@"반복 횟수"
                          placeholder:@"0이면 무한"
                          initialText:times
                         keyboardType:UIKeyboardTypeNumberPad
                           completion:^(NSString *input) {
            [self _mutateScript:^{
                row.block[@"times"] = @(MAX(0, [input integerValue]));
            }];
        }];
        return;
    }

    if([type isEqualToString:@"if"] && [self _handleConditionTokenTap:tokenIdentifier forBlock:row.block]) {
        return;
    }
}

- (void)_insertBlockOfType:(NSString *)type intoContainer:(NSMutableArray *)container atIndex:(NSInteger)index {
    NSMutableArray *targetContainer = container ?: _steps;
    NSInteger insertionIndex = MAX(0, MIN(index, (NSInteger)targetContainer.count));
    NSMutableDictionary *block = ARILabelScriptInlineDefaultBlock(type);

    [self _mutateScript:^{
        [targetContainer insertObject:block atIndex:insertionIndex];
        _selectedInsertionContainer = nil;
        _selectedInsertionIndex = 0;
    }];
}

- (void)_presentAddActionSheetFromView:(UIView *)sourceView rect:(CGRect)rect container:(NSMutableArray *)container index:(NSInteger)index {
    ARILabelScriptActionCatalogController *controller = [[ARILabelScriptActionCatalogController alloc] initWithInitialQuery:@""
                                                                                                            selectionHandler:^(NSString *type) {
        [self _insertBlockOfType:type intoContainer:container atIndex:index];
    }];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    if(navigationController.popoverPresentationController) {
        navigationController.popoverPresentationController.sourceView = sourceView ?: self.view;
        navigationController.popoverPresentationController.sourceRect = sourceView ? rect : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    }
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)addButtonTapped {
    NSMutableArray *container = _selectedInsertionContainer ?: _steps;
    NSInteger index = _selectedInsertionContainer ? _selectedInsertionIndex : _steps.count;
    [self _presentAddActionSheetFromView:_addButton rect:_addButton.bounds container:container index:index];
}

- (void)_presentBlockTypeSheetForRow:(ARILabelScriptVisualRow *)row sourceView:(UIView *)sourceView {
    ARILabelScriptActionCatalogController *controller = [[ARILabelScriptActionCatalogController alloc] initWithInitialQuery:@""
                                                                                                            selectionHandler:^(NSString *type) {
            [self _mutateScript:^{
                [row.block removeAllObjects];
                [row.block addEntriesFromDictionary:ARILabelScriptInlineDefaultBlock(type)];
            }];
    }];
    controller.title = @"유형 변경";
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    if(navigationController.popoverPresentationController) {
        navigationController.popoverPresentationController.sourceView = sourceView ?: self.view;
        navigationController.popoverPresentationController.sourceRect = sourceView ? sourceView.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    }
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)_presentRowMenuForRow:(ARILabelScriptVisualRow *)row sourceView:(UIView *)sourceView {
    if(row.kind != ARILabelScriptVisualRowKindAction || !row.container) {
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row.title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"삽입 아래"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self _presentAddActionSheetFromView:sourceView rect:sourceView.bounds container:row.insertionContainer index:row.insertionIndex];
        }]];

    if(row.collapsible) {
        [sheet addAction:[UIAlertAction actionWithTitle:(row.collapsed ? @"펼치기" : @"접기")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            [self _setBlockCollapsed:!row.collapsed forBlock:row.block];
            [self _rebuildRows];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"복제"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self _mutateScript:^{
            NSMutableDictionary *copy = ARILabelScriptInlineMutableDictionaryValue(row.block);
            NSData *data = [NSJSONSerialization dataWithJSONObject:copy options:0 error:nil];
            id copiedObject = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
            NSMutableDictionary *duplicated = [copiedObject isKindOfClass:[NSDictionary class]] ? [copiedObject mutableCopy] : [copy mutableCopy];
            [row.container insertObject:duplicated atIndex:MIN(row.index + 1, row.container.count)];
            _selectedInsertionContainer = nil;
            _selectedInsertionIndex = 0;
        }];
    }]];

    if(row.index > 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"위로 이동"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            [self _mutateScript:^{
                id block = row.container[row.index];
                [row.container removeObjectAtIndex:row.index];
                [row.container insertObject:block atIndex:row.index - 1];
            }];
        }]];
    }

    if(row.index < (NSInteger)row.container.count - 1) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"아래로 이동"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            [self _mutateScript:^{
                id block = row.container[row.index];
                [row.container removeObjectAtIndex:row.index];
                [row.container insertObject:block atIndex:row.index + 1];
            }];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"유형 변경"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self _presentBlockTypeSheetForRow:row sourceView:sourceView];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"삭제"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        [self _mutateScript:^{
            if(row.index < row.container.count) {
                [row.container removeObjectAtIndex:row.index];
            }
        }];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
    if(sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = sourceView ?: self.view;
        sheet.popoverPresentationController.sourceRect = sourceView ? sourceView.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)closeEditor {
    if(![self _hasUnsavedChanges]) {
        [self _finishClosingEditor];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"저장되지 않은 변경사항"
                                                                   message:@"저장하거나 버릴 수 있습니다."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"계속 편집" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"버리기"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        [self _finishClosingEditor];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"저장"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self saveScript];
    }]];
    if(alert.popoverPresentationController) {
        alert.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveScript {
    NSDictionary *script = _isRootController ? _rootScript : @{ @"loop": @YES, @"steps": _steps ?: @[] };
    NSError *error = nil;
    NSString *source = [ARILabelScriptCompiler sourceFromScriptDictionary:script error:&error];
    if(!source) {
        [self _showAlertWithTitle:@"저장 실패" message:error.localizedDescription ?: @"스크립트를 저장할 수 없습니다."];
        return;
    }

    if(_isRootController) {
        [_preferences setObject:source forKey:@"labelScriptSource"];
        [_preferences synchronize];
        _savedSource = [source copy] ?: @"";
        [self _postReloadNotification];
    }
    [self _finishClosingEditor];
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return _isRootController ? 2 : 1;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(_isRootController && section == 0) {
        return 1;
    }
    return _rows.count;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if(_isRootController && section == 0) {
        return @"옵션";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if(_isRootController && indexPath.section == 0) {
        static NSString *switchIdentifier = @"LoopSwitch";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:switchIdentifier];
        if(!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:switchIdentifier];
            UISwitch *toggle = [[UISwitch alloc] init];
            [toggle addTarget:self action:@selector(loopSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        }
        cell.textLabel.text = @"루프";
        ((UISwitch *)cell.accessoryView).on = [_rootScript[@"loop"] boolValue];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    ARILabelScriptVisualRow *row = _rows[indexPath.row];
    static NSString *identifier = @"InlineAction";
    ARILabelScriptInlineCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if(!cell) {
        cell = [[ARILabelScriptInlineCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }

    __weak typeof(self) weakSelf = self;
    __weak typeof(cell) weakCell = cell;
    cell.tapHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakCell) strongCell = weakCell;
        if(!strongSelf || !strongCell) return;
        [strongSelf _activateRow:row sourceView:strongCell];
    };
    void (^tokenHandler)(NSString *) = ^(NSString *tokenIdentifier) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if(!strongSelf) return;
        [strongSelf _handleTokenTap:tokenIdentifier forRow:row];
    };
    cell.tokenHandler = tokenHandler;
    cell.accessoryHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakCell) strongCell = weakCell;
        if(!strongSelf || !strongCell) return;
        if(row.accessoryKind == ARILabelScriptVisualAccessoryKindInsert) {
            [strongSelf _activateRow:row sourceView:strongCell];
        } else if(row.accessoryKind == ARILabelScriptVisualAccessoryKindMenu) {
            [strongSelf _presentRowMenuForRow:row sourceView:strongCell];
        }
    };
    [cell configureWithParts:[self _partsForRow:row]
                    iconName:row.symbolName
                   tintColor:row.tintColor
                     rowKind:row.kind
                       depth:row.depth
                  railDepths:row.railDepths
              scopeRailDepth:row.scopeRailDepth
               scopeRailMode:row.scopeRailMode
                    selected:[self _rowIsSelectedAnchor:row]
               accessoryKind:row.accessoryKind];
    return cell;
}

- (void)loopSwitchChanged:(UISwitch *)sender {
    [self _mutateScript:^{
        _rootScript[@"loop"] = @(sender.isOn);
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end

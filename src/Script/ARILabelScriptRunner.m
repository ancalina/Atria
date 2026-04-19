//
// Label script runtime.
//

#include <math.h>

#import "ARILabelScriptRunner.h"
#import "../../Shared/ARILabelScriptCompiler.h"

@interface ARILabelScriptFrame : NSObject
@property (nonatomic, copy) NSArray<NSDictionary *> *steps;
@property (nonatomic, assign) NSUInteger index;
@property (nonatomic, assign) BOOL infinite;
@property (nonatomic, assign) NSInteger remainingCount;
@end

@implementation ARILabelScriptFrame
@end

@implementation ARILabelScriptRunner {
    NSArray<NSDictionary *> *_rootSteps;
    BOOL _rootLoops;
    NSMutableArray<ARILabelScriptFrame *> *_frames;
    BOOL _valid;
    BOOL _started;
    NSString *_currentTextTemplate;
    NSString *_lastError;
    NSDictionary<NSString *, id> *_context;
}

@synthesize valid = _valid;
@synthesize started = _started;
@synthesize currentTextTemplate = _currentTextTemplate;
@synthesize lastError = _lastError;
@synthesize context = _context;

- (instancetype)init {
    self = [super init];
    if(self) {
        _frames = [NSMutableArray new];
        _currentTextTemplate = @"";
        _lastError = @"";
        _context = @{};
    }
    return self;
}

- (NSString *)_contextStringForKey:(NSString *)key {
    id value = _context[key];
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

- (double)_contextNumberForKey:(NSString *)key fallback:(double)fallback {
    id value = _context[key];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

- (BOOL)_contextBoolForKey:(NSString *)key fallback:(BOOL)fallback {
    id value = _context[key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

- (BOOL)_contextStringForKey:(NSString *)key containsQuery:(NSString *)query {
    if(query.length == 0) {
        return NO;
    }

    NSString *value = [self _contextStringForKey:key];
    return [value rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
}

- (void)_pushFrameWithSteps:(NSArray<NSDictionary *> *)steps repeatCount:(NSInteger)repeatCount infinite:(BOOL)infinite {
    if(steps.count == 0) return;

    ARILabelScriptFrame *frame = [ARILabelScriptFrame new];
    frame.steps = steps;
    frame.index = 0;
    frame.infinite = infinite;
    frame.remainingCount = repeatCount;
    [_frames addObject:frame];
}

- (void)_pushRootFrame {
    [_frames removeAllObjects];
    [self _pushFrameWithSteps:_rootSteps repeatCount:1 infinite:_rootLoops];
}

- (void)reset {
    _started = NO;
    _currentTextTemplate = @"";
    [_frames removeAllObjects];
    [self _pushRootFrame];
}

- (BOOL)loadSource:(NSString *)source {
    NSError *error = nil;
    NSDictionary *script = [ARILabelScriptCompiler scriptDictionaryFromSource:source error:&error];
    if(!script) {
        _valid = NO;
        _started = NO;
        _currentTextTemplate = @"";
        _lastError = error.localizedDescription ?: @"Invalid script.";
        [_frames removeAllObjects];
        return NO;
    }

    _rootSteps = [script[@"steps"] isKindOfClass:[NSArray class]] ? script[@"steps"] : @[];
    _rootLoops = script[@"loop"] ? [script[@"loop"] boolValue] : YES;
    _valid = YES;
    _lastError = @"";
    [self reset];
    return YES;
}

- (nullable NSDictionary *)_nextBlock {
    while(_frames.count > 0) {
        ARILabelScriptFrame *frame = _frames.lastObject;
        if(frame.index < frame.steps.count) {
            return frame.steps[frame.index++];
        }

        if(frame.infinite || frame.remainingCount > 1) {
            if(!frame.infinite) frame.remainingCount--;
            frame.index = 0;
            continue;
        }

        [_frames removeLastObject];
    }

    return nil;
}

- (BOOL)_evaluateCondition:(NSDictionary *)condition {
    NSString *type = [condition[@"type"] isKindOfClass:[NSString class]] ? condition[@"type"] : @"always";
    NSCalendar *calendar = [NSCalendar currentCalendar];

    if([type isEqualToString:@"always"]) {
        return YES;
    }

    if([type isEqualToString:@"hour_between"]) {
        double start = [condition[@"start"] respondsToSelector:@selector(doubleValue)] ? [condition[@"start"] doubleValue] : 0.0;
        double end = [condition[@"end"] respondsToSelector:@selector(doubleValue)] ? [condition[@"end"] doubleValue] : 24.0;
        NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];
        double hour = (double)components.hour + ((double)components.minute / 60.0);

        if(start == end) return YES;
        if(start < end) return hour >= start && hour < end;
        return hour >= start || hour < end;
    }

    if([type isEqualToString:@"weekday_is"]) {
        NSArray *days = [condition[@"days"] isKindOfClass:[NSArray class]] ? condition[@"days"] : @[];
        NSInteger weekday = [[calendar components:NSCalendarUnitWeekday fromDate:[NSDate date]] weekday];
        for(id day in days) {
            if([day respondsToSelector:@selector(integerValue)] && [day integerValue] == weekday) {
                return YES;
            }
        }
        return NO;
    }

    if([type isEqualToString:@"location_contains"]) {
        NSString *query = [condition[@"query"] isKindOfClass:[NSString class]] ? condition[@"query"] : @"";
        return [self _contextStringForKey:@"locationName" containsQuery:query];
    }

    if([type isEqualToString:@"weather_contains"]) {
        NSString *query = [condition[@"query"] isKindOfClass:[NSString class]] ? condition[@"query"] : @"";
        if(query.length == 0) {
            return NO;
        }

        NSString *weatherText = [self _contextStringForKey:@"weatherDescription"];
        NSString *temperatureText = [self _contextStringForKey:@"temperatureText"];
        NSString *combined = [NSString stringWithFormat:@"%@ %@", weatherText ?: @"", temperatureText ?: @""];
        return [combined rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
    }

    if([type isEqualToString:@"temperature_above"]) {
        double threshold = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
        double temperature = [self _contextNumberForKey:@"temperatureValue" fallback:NAN];
        return !isnan(temperature) && temperature >= threshold;
    }

    if([type isEqualToString:@"temperature_below"]) {
        double threshold = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
        double temperature = [self _contextNumberForKey:@"temperatureValue" fallback:NAN];
        return !isnan(temperature) && temperature < threshold;
    }

    if([type isEqualToString:@"battery_above"]) {
        double threshold = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
        double battery = [self _contextNumberForKey:@"batteryLevel" fallback:NAN];
        return !isnan(battery) && battery >= threshold;
    }

    if([type isEqualToString:@"battery_below"]) {
        double threshold = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
        double battery = [self _contextNumberForKey:@"batteryLevel" fallback:NAN];
        return !isnan(battery) && battery < threshold;
    }

    if([type isEqualToString:@"battery_charging"]) {
        return [self _contextBoolForKey:@"batteryCharging" fallback:NO];
    }

    if([type isEqualToString:@"battery_connected"]) {
        return [self _contextBoolForKey:@"batteryConnected" fallback:NO];
    }

    if([type isEqualToString:@"and"]) {
        NSArray *conditions = [condition[@"conditions"] isKindOfClass:[NSArray class]] ? condition[@"conditions"] : @[];
        for(NSDictionary *nested in conditions) {
            if(![self _evaluateCondition:nested]) return NO;
        }
        return YES;
    }

    if([type isEqualToString:@"or"]) {
        NSArray *conditions = [condition[@"conditions"] isKindOfClass:[NSArray class]] ? condition[@"conditions"] : @[];
        for(NSDictionary *nested in conditions) {
            if([self _evaluateCondition:nested]) return YES;
        }
        return NO;
    }

    if([type isEqualToString:@"not"]) {
        NSDictionary *nested = [condition[@"condition"] isKindOfClass:[NSDictionary class]] ? condition[@"condition"] : nil;
        return nested ? ![self _evaluateCondition:nested] : NO;
    }

    return NO;
}

- (NSTimeInterval)advance {
    if(!_valid || _rootSteps.count == 0) {
        _started = YES;
        return 60.0;
    }

    if(_frames.count == 0) {
        [self _pushRootFrame];
    }

    NSUInteger executedBlocks = 0;
    while(executedBlocks < 512) {
        NSDictionary *block = [self _nextBlock];
        if(!block) {
            _started = YES;
            return 60.0;
        }

        executedBlocks++;
        NSString *type = [block[@"type"] isKindOfClass:[NSString class]] ? block[@"type"] : @"";

        if([type isEqualToString:@"set_text"]) {
            _currentTextTemplate = [block[@"text"] isKindOfClass:[NSString class]] ? block[@"text"] : @"";
            continue;
        }

        if([type isEqualToString:@"wait"]) {
            _started = YES;
            double seconds = [block[@"seconds"] respondsToSelector:@selector(doubleValue)] ? [block[@"seconds"] doubleValue] : 0.0;
            return MAX(0.1, seconds);
        }

        if([type isEqualToString:@"reload"]) {
            [self _pushRootFrame];
            continue;
        }

        if([type isEqualToString:@"if"]) {
            NSDictionary *condition = [block[@"condition"] isKindOfClass:[NSDictionary class]] ? block[@"condition"] : nil;
            NSArray *branch = [self _evaluateCondition:condition ?: @{}]
                                  ? ([block[@"then"] isKindOfClass:[NSArray class]] ? block[@"then"] : @[])
                                  : ([block[@"else"] isKindOfClass:[NSArray class]] ? block[@"else"] : @[]);
            [self _pushFrameWithSteps:branch repeatCount:1 infinite:NO];
            continue;
        }

        if([type isEqualToString:@"repeat"]) {
            NSArray *steps = [block[@"steps"] isKindOfClass:[NSArray class]] ? block[@"steps"] : @[];
            NSInteger times = [block[@"times"] respondsToSelector:@selector(integerValue)] ? [block[@"times"] integerValue] : 0;
            BOOL infinite = times <= 0;
            [self _pushFrameWithSteps:steps repeatCount:MAX(1, times) infinite:infinite];
            continue;
        }
    }

    _started = YES;
    return 1.0;
}

@end

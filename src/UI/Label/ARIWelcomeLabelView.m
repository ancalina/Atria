//
// Created by ren7995 on 2023-05-30 18:39:12
// Copyright (c) 2023 ren7995. All rights reserved.
//

#import "ARIWelcomeLabelView.h"
#import "../../Manager/ARITweakManager.h"
#import "../../Script/ARILabelScriptRunner.h"
#import "../../../Prefs/src/ARILabelScriptVisualEditorController.h"
#import "../../../Shared/ARISharedConstants.h"
#import "../../../Shared/ARICustomGreetingScheduleStore.h"
#import "../../../Shared/ARILabelScriptCompiler.h"

#import <objc/message.h>
#import <objc/runtime.h>
#include <math.h>

typedef NS_ENUM(NSUInteger, ARIGreetingPeriod) {
    ARIGreetingPeriodMorning,
    ARIGreetingPeriodAfternoon,
    ARIGreetingPeriodEvening,
};

static BOOL ARILabelScriptEditorPresentationInFlight = NO;

@implementation ARIWelcomeLabelView {
    NSCalendar *_calendar;
    NSTimer *_updateTimer;
    UIImageView *_imageView;
    WALockscreenWidgetViewController *_weatherUpdater;
    ARILabelScriptRunner *_scriptRunner;
    NSString *_loadedScriptSource;
}

- (void)_invalidateObserversAndTimer {
    if(_updateTimer) {
        [_updateTimer invalidate];
        _updateTimer = nil;
    }

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSSystemClockDidChangeNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:ARIUpdateLabelVisibilityNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIDeviceBatteryLevelDidChangeNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIDeviceBatteryStateDidChangeNotification
                                                  object:nil];
}

- (NSString *)_safeStringFromWeatherUpdaterSelector:(SEL)selector fallback:(NSString *)fallback {
    id weatherUpdater = _weatherUpdater;
    if(!weatherUpdater || ![weatherUpdater respondsToSelector:selector]) {
        return fallback;
    }

    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(weatherUpdater, selector);
        if([value isKindOfClass:[NSString class]] && [((NSString *)value) length] > 0) {
            return [(NSString *)value copy];
        }
    } @catch (__unused NSException *exception) {
    }

    return fallback;
}

- (UIImage *)_safeConditionsImage {
    id weatherUpdater = _weatherUpdater;
    if(!weatherUpdater || ![weatherUpdater respondsToSelector:@selector(_conditionsImage)]) {
        return nil;
    }

    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(weatherUpdater, @selector(_conditionsImage));
        if([value isKindOfClass:[UIImage class]]) {
            return value;
        }
    } @catch (__unused NSException *exception) {
    }

    return nil;
}

- (NSString *)_weatherDescriptionText {
    NSArray<NSString *> *selectorNames = @[
        @"_conditionName",
        @"conditionName",
        @"_conditionDescription",
        @"conditionDescription",
        @"_conditionsDescription"
    ];

    for(NSString *selectorName in selectorNames) {
        NSString *value = [self _safeStringFromWeatherUpdaterSelector:NSSelectorFromString(selectorName) fallback:@""];
        if(value.length > 0) {
            return value;
        }
    }

    return @"";
}

- (double)_numericValueFromString:(NSString *)string fallback:(double)fallback {
    NSString *value = [string isKindOfClass:[NSString class]] ? string : @"";
    NSMutableString *filtered = [NSMutableString string];
    BOOL hasDecimal = NO;

    for(NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if((character >= '0' && character <= '9') || (character == '-' && filtered.length == 0)) {
            [filtered appendFormat:@"%C", character];
            continue;
        }

        if(character == '.' && !hasDecimal) {
            [filtered appendString:@"."];
            hasDecimal = YES;
        }
    }

    if(filtered.length == 0 || [filtered isEqualToString:@"-"] || [filtered isEqualToString:@"."] || [filtered isEqualToString:@"-."]) {
        return fallback;
    }

    return [filtered doubleValue];
}

- (NSDictionary<NSString *, id> *)_scriptContext {
    NSString *temperatureText = [self _safeStringFromWeatherUpdaterSelector:@selector(_temperature) fallback:@""];
    NSString *locationName = [self _safeStringFromWeatherUpdaterSelector:@selector(_locationName) fallback:@""];
    NSString *weatherDescription = [self _weatherDescriptionText];
    double temperatureValue = [self _numericValueFromString:temperatureText fallback:NAN];

    UIDevice *device = [UIDevice currentDevice];
    float batteryLevel = device.batteryLevel;
    UIDeviceBatteryState batteryState = device.batteryState;
    BOOL charging = batteryState == UIDeviceBatteryStateCharging;
    BOOL connected = batteryState == UIDeviceBatteryStateCharging || batteryState == UIDeviceBatteryStateFull;

    NSMutableDictionary<NSString *, id> *context = [NSMutableDictionary dictionary];
    context[@"temperatureText"] = temperatureText ?: @"";
    context[@"locationName"] = locationName ?: @"";
    context[@"weatherDescription"] = weatherDescription ?: @"";
    context[@"batteryCharging"] = @(charging);
    context[@"batteryConnected"] = @(connected);

    if(!isnan(temperatureValue)) {
        context[@"temperatureValue"] = @(temperatureValue);
    }

    if(batteryLevel >= 0.0f) {
        context[@"batteryLevel"] = @(roundf(batteryLevel * 100.0f));
    }

    return context;
}

- (NSString *)_currentWeekdayString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale currentLocale];
    formatter.calendar = _calendar;
    formatter.dateFormat = @"EEEE";
    return [formatter stringFromDate:[NSDate date]] ?: @"";
}

- (NSString *)_currentTimeString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale currentLocale];
    formatter.calendar = _calendar;
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:[NSDate date]] ?: @"";
}

- (NSString *)_batteryPercentageString {
    float batteryLevel = [UIDevice currentDevice].batteryLevel;
    if(batteryLevel < 0.0f) {
        return @"--%";
    }

    return [NSString stringWithFormat:@"%ld%%", (long)lroundf(batteryLevel * 100.0f)];
}

- (BOOL)_rawTextNeedsMinuteRefresh:(NSString *)rawText {
    NSString *text = [rawText isKindOfClass:[NSString class]] ? rawText : @"";
    NSArray<NSString *> *tokens = @[
        @"%TIME%",
        @"%시각%",
        @"%시간%"
    ];

    for(NSString *token in tokens) {
        if([text containsString:token]) {
            return YES;
        }
    }

    return NO;
}

- (NSTimeInterval)_secondsUntilNextMinuteBoundary {
    NSDateComponents *components = [_calendar components:(NSCalendarUnitSecond | NSCalendarUnitNanosecond) fromDate:[NSDate date]];
    NSTimeInterval interval = 60.0 - (NSTimeInterval)components.second - ((NSTimeInterval)components.nanosecond / 1000000000.0);
    return MAX(1.0, interval);
}

- (instancetype)init {
    self = [super init];
    if(self) {
        _calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];

        [self _scheduleNextUpdateAfter:60.0];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateText:) name:NSSystemClockDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateLabelVisibility:) name:ARIUpdateLabelVisibilityNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateText:) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateText:) name:UIDeviceBatteryStateDidChangeNotification object:nil];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;

        Class weatherClass = objc_getClass("WALockscreenWidgetViewController");
        if(weatherClass) {
            _weatherUpdater = [[weatherClass alloc] init];
            if([_weatherUpdater respondsToSelector:@selector(updateWeather)]) {
                @try {
                    [_weatherUpdater updateWeather];
                } @catch (__unused NSException *exception) {
                }
            }
        }
    }
    return self;
}

- (void)_scheduleNextUpdateAfter:(NSTimeInterval)interval {
    if(_updateTimer) {
        [_updateTimer invalidate];
        _updateTimer = nil;
    }

    NSTimeInterval safeInterval = MAX(0.1, interval);
    _updateTimer = [NSTimer timerWithTimeInterval:safeInterval target:self selector:@selector(updateText:) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:_updateTimer forMode:NSDefaultRunLoopMode];
}

- (NSString *)_labelScriptSource {
    id source = [[ARITweakManager sharedInstance] rawValueForKey:@"labelScriptSource"];
    return [source isKindOfClass:[NSString class]] ? source : @"";
}

- (BOOL)_reloadScriptRunnerIfNeeded {
    NSString *source = [self _labelScriptSource];
    if(_scriptRunner && [_loadedScriptSource isEqualToString:source]) {
        return NO;
    }

    _scriptRunner = [ARILabelScriptRunner new];
    [_scriptRunner loadSource:source];
    _loadedScriptSource = [source copy];
    return YES;
}

- (void)setupTextField:(UITextField *)textField {
    _imageView = [[UIImageView alloc] init];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_imageView.widthAnchor constraintEqualToConstant:30],
        [_imageView.heightAnchor constraintEqualToConstant:30],
    ]];

    textField.leftView = _imageView;
}

- (NSString *)loadRawText {
    return [[ARITweakManager sharedInstance] rawValueForKey:@"labelText"];
}

- (void)updateText:(NSTimer *)timer {
    if([self.textField isEditing]) return;

    BOOL scheduled = timer != nil;
    BOOL scriptEnabled = [[ARITweakManager sharedInstance] boolValueForKey:@"labelScriptEnabled"];
    BOOL shouldSchedule = YES;
    NSTimeInterval nextInterval = 60.0;
    NSString *rawText = [self loadRawText];

    if(scriptEnabled) {
        BOOL didReload = [self _reloadScriptRunnerIfNeeded];
        _scriptRunner.context = [self _scriptContext];
        if(_scriptRunner.isValid) {
            if(didReload || scheduled || !_scriptRunner.hasStarted) {
                nextInterval = [_scriptRunner advance];
            } else {
                shouldSchedule = NO;
            }

            NSString *scriptText = _scriptRunner.currentTextTemplate;
            if([scriptText isKindOfClass:[NSString class]] && scriptText.length > 0) {
                rawText = scriptText;
            }
        }
    } else {
        _scriptRunner = nil;
        _loadedScriptSource = nil;
        if([self _rawTextNeedsMinuteRefresh:rawText]) {
            nextInterval = [self _secondsUntilNextMinuteBoundary];
        }
    }

    [self setCurrentRawText:rawText];
    self.textField.text = [self processRawText:[self currentRawText] isScheduledUpdate:scheduled];

    if(shouldSchedule || !_updateTimer) {
        [self _scheduleNextUpdateAfter:nextInterval];
    }
}

- (NSString *)_stringValueForKey:(NSString *)key fallback:(NSString *)fallback {
    id value = [[ARITweakManager sharedInstance] rawValueForKey:key];
    if([value isKindOfClass:[NSString class]] && [((NSString *)value) length] > 0) {
        return [(NSString *)value copy];
    }

    return fallback;
}

- (ARIGreetingPeriod)_greetingPeriodForHour:(NSInteger)hour
                               morningStart:(NSInteger)morningStart
                             afternoonStart:(NSInteger)afternoonStart
                               eveningStart:(NSInteger)eveningStart {
    if(hour >= morningStart && hour < afternoonStart) {
        return ARIGreetingPeriodMorning;
    }

    if(hour >= afternoonStart && hour < eveningStart) {
        return ARIGreetingPeriodAfternoon;
    }

    return ARIGreetingPeriodEvening;
}

- (NSString *)_sanitizedCustomTokenName:(NSString *)rawName {
    NSString *tokenName = [rawName isKindOfClass:[NSString class]] ? [rawName copy] : @"";
    tokenName = [tokenName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    while([tokenName hasPrefix:@"%"] && [tokenName length] > 0) {
        tokenName = [tokenName substringFromIndex:1];
    }

    while([tokenName hasSuffix:@"%"] && [tokenName length] > 0) {
        tokenName = [tokenName substringToIndex:[tokenName length] - 1];
    }

    return tokenName;
}

- (NSString *)_customGreetingTextForEntries:(NSArray<NSDictionary *> *)entries {
    if(entries.count == 0) {
        return @"";
    }

    NSDateComponents *components = [_calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];
    double currentHour = (double)components.hour + ((double)components.minute / 60.0);
    NSDictionary *selectedEntry = entries.lastObject;
    for(NSDictionary *entry in entries) {
        double start = [entry[@"start"] respondsToSelector:@selector(doubleValue)] ? [entry[@"start"] doubleValue] : 0.0;
        if(currentHour >= start) {
            selectedEntry = entry;
        } else {
            break;
        }
    }

    NSString *text = [selectedEntry[@"text"] isKindOfClass:[NSString class]] ? selectedEntry[@"text"] : @"";
    return text ?: @"";
}

- (NSString *)_stringByReplacingCustomGreetingTokensInString:(NSString *)string {
    NSString *result = [string isKindOfClass:[NSString class]] ? [string copy] : @"";
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    NSArray<NSDictionary *> *tokens = [ARICustomGreetingScheduleStore effectiveTokensFromPreferences:preferences];

    for(NSDictionary *tokenDictionary in tokens) {
        NSString *rawTokenName = [tokenDictionary[@"name"] isKindOfClass:[NSString class]] ? tokenDictionary[@"name"] : @"";
        NSString *tokenName = [self _sanitizedCustomTokenName:rawTokenName];
        if([tokenName length] == 0) {
            continue;
        }

        NSString *token = [NSString stringWithFormat:@"%%%@%%", tokenName];
        NSArray<NSDictionary *> *entries = [tokenDictionary[@"entries"] isKindOfClass:[NSArray class]] ? tokenDictionary[@"entries"] : @[];
        result = [result stringByReplacingOccurrencesOfString:token withString:[self _customGreetingTextForEntries:entries]];
    }

    return result;
}

- (NSString *)processRawText:(NSString *)rawText isScheduledUpdate:(BOOL)scheduled {
    NSString *text = [rawText isKindOfClass:[NSString class]] ? [rawText copy] : @"";
    text = [self _stringByReplacingCustomGreetingTokensInString:text];

    NSString *greeting = @"Welcome";
    NSString *greetingKR = @"환영합니다";

    NSInteger hour = [[_calendar components:NSCalendarUnitHour fromDate:[NSDate date]] hour];
    switch([self _greetingPeriodForHour:hour morningStart:4 afternoonStart:12 eveningStart:18]) {
        case ARIGreetingPeriodMorning:
            greeting = @"Good morning";
            greetingKR = @"좋은 아침입니다";
            break;
        case ARIGreetingPeriodAfternoon:
            greeting = @"Good afternoon";
            greetingKR = @"좋은 오후입니다";
            break;
        case ARIGreetingPeriodEvening:
        default:
            greeting = @"Good evening";
            greetingKR = @"좋은 저녁입니다";
            break;
    }

    NSString *temperature = @"--";
    NSString *locationName = @"알 수 없음";
    NSString *batteryPercentage = [self _batteryPercentageString];
    NSString *weekday = [self _currentWeekdayString];
    NSString *currentTime = [self _currentTimeString];
    BOOL wantsWeatherText = [text containsString:@"\%TEMPERATURE\%"] ||
                            [text containsString:@"\%ONDO\%"] ||
                            [text containsString:@"\%온도\%"] ||
                            [text containsString:@"\%LOCATION\%"] ||
                            [text containsString:@"\%WHICH\%"] ||
                            [text containsString:@"\%위치\%"];

    if(wantsWeatherText || [[ARITweakManager sharedInstance] boolValueForKey:@"showWeatherIcon"]) {
        temperature = [self _safeStringFromWeatherUpdaterSelector:@selector(_temperature) fallback:@"--"];
        locationName = [self _safeStringFromWeatherUpdaterSelector:@selector(_locationName) fallback:@"알 수 없음"];
        _imageView.image = [self _safeConditionsImage];
    } else {
        _imageView.image = nil;
    }

    text = [text stringByReplacingOccurrencesOfString:@"\%GREETING\%" withString:greeting];
    text = [text stringByReplacingOccurrencesOfString:@"\%GREETING_KR\%" withString:greetingKR];
    text = [text stringByReplacingOccurrencesOfString:@"\%인삿말_한\%" withString:greetingKR];
    text = [text stringByReplacingOccurrencesOfString:@"\%인삿말_영\%" withString:greeting];
    text = [text stringByReplacingOccurrencesOfString:@"\%TEMPERATURE\%" withString:temperature];
    text = [text stringByReplacingOccurrencesOfString:@"\%ONDO\%" withString:temperature];
    text = [text stringByReplacingOccurrencesOfString:@"\%온도\%" withString:temperature];
    text = [text stringByReplacingOccurrencesOfString:@"\%LOCATION\%" withString:locationName];
    text = [text stringByReplacingOccurrencesOfString:@"\%WHICH\%" withString:locationName];
    text = [text stringByReplacingOccurrencesOfString:@"\%위치\%" withString:locationName];
    text = [text stringByReplacingOccurrencesOfString:@"\%BATTERY\%" withString:batteryPercentage];
    text = [text stringByReplacingOccurrencesOfString:@"\%배터리\%" withString:batteryPercentage];
    text = [text stringByReplacingOccurrencesOfString:@"\%DAY\%" withString:weekday];
    text = [text stringByReplacingOccurrencesOfString:@"\%WEEKDAY\%" withString:weekday];
    text = [text stringByReplacingOccurrencesOfString:@"\%요일\%" withString:weekday];
    text = [text stringByReplacingOccurrencesOfString:@"\%TIME\%" withString:currentTime];
    text = [text stringByReplacingOccurrencesOfString:@"\%시각\%" withString:currentTime];
    text = [text stringByReplacingOccurrencesOfString:@"\%시간\%" withString:currentTime];
    return text;
}

- (void)saveTextValue:(NSString *)text {
    [[ARITweakManager sharedInstance] setValue:text forKey:@"labelText"];
}

- (UIViewController *)_visibleViewControllerFromController:(UIViewController *)controller {
    UIViewController *current = controller;
    while(current) {
        UIViewController *next = nil;
        if(current.presentedViewController) {
            next = current.presentedViewController;
        } else if([current isKindOfClass:[UINavigationController class]]) {
            next = ((UINavigationController *)current).visibleViewController;
        } else if([current isKindOfClass:[UITabBarController class]]) {
            next = ((UITabBarController *)current).selectedViewController;
        }

        if(!next || next == current) {
            return current;
        }
        current = next;
    }

    return controller;
}

- (BOOL)_controllerContainsScriptEditor:(UIViewController *)controller {
    if(!controller) {
        return NO;
    }
    if([controller isKindOfClass:[ARILabelScriptVisualEditorController class]]) {
        return YES;
    }
    if([controller isKindOfClass:[UINavigationController class]]) {
        UIViewController *topController = ((UINavigationController *)controller).topViewController;
        return [topController isKindOfClass:[ARILabelScriptVisualEditorController class]];
    }
    return NO;
}

- (void)_presentScriptEditorFromLabel {
    if(ARILabelScriptEditorPresentationInFlight) {
        return;
    }

    UIWindow *window = [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
    UIViewController *presenter = [self _visibleViewControllerFromController:window.rootViewController];
    if(!presenter) {
        return;
    }

    if([self _controllerContainsScriptEditor:presenter] ||
       [self _controllerContainsScriptEditor:presenter.presentedViewController] ||
       presenter.isBeingPresented ||
       presenter.isBeingDismissed) {
        return;
    }

    NSString *source = [self _labelScriptSource];
    NSError *error = nil;
    NSMutableDictionary *script = [ARILabelScriptCompiler mutableScriptDictionaryFromSource:source error:&error];
    if(!script) {
        if(source.length == 0) {
            script = [@{ @"loop": @YES, @"steps": [NSMutableArray new] } mutableCopy];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"스크립트를 열 수 없음"
                                                                           message:error.localizedDescription ?: @"설정의 스크립트 에디터를 사용해 주세요."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"확인" style:UIAlertActionStyleCancel handler:nil]];
            [presenter presentViewController:alert animated:YES completion:nil];
            return;
        }
    }

    ARILabelScriptVisualEditorController *controller = [[ARILabelScriptVisualEditorController alloc] initRootControllerWithScript:script];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    ARILabelScriptEditorPresentationInFlight = YES;
    [presenter presentViewController:navigationController animated:YES completion:^{
        ARILabelScriptEditorPresentationInFlight = NO;
    }];
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    if([[ARITweakManager sharedInstance] boolValueForKey:@"labelScriptEnabled"]) {
        [ARITweakManager dismissFloatingDockIfPossible];
        [self _presentScriptEditorFromLabel];
        return NO;
    }

    return [super textFieldShouldBeginEditing:textField];
}

- (void)updateView {
    [super updateView];
    self.textField.leftViewMode = [[ARITweakManager sharedInstance] boolValueForKey:@"showWeatherIcon"]
                                      ? UITextFieldViewModeAlways // UnlessEditing
                                      : UITextFieldViewModeNever;
}

- (void)removeFromSuperview {
    [self _invalidateObserversAndTimer];
    [super removeFromSuperview];
}

- (void)dealloc {
    [self _invalidateObserversAndTimer];
}

@end

//
// Block editor for label scripts.
//

#include <math.h>

#import "ARILabelScriptBlockEditorController.h"
#import "ARILabelScriptVisualEditorController.h"
#import "../../Shared/ARISharedConstants.h"

typedef void (^ARILabelScriptTimePickerCompletion)(double value);
typedef void (^ARILabelScriptWeekdayPickerCompletion)(NSArray<NSNumber *> *days);

static NSString *ARILabelScriptFormattedTimeValue(double value) {
    NSInteger totalMinutes = (NSInteger)llround(value * 60.0);
    if(totalMinutes < 0) totalMinutes = 0;
    if(totalMinutes > 24 * 60) totalMinutes = 24 * 60;

    NSInteger hours = totalMinutes / 60;
    NSInteger minutes = totalMinutes % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)hours, (long)minutes];
}

static NSString *ARILabelScriptWeekdayTitle(NSInteger weekday) {
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

static NSString *ARILabelScriptWeekdayShortTitle(NSInteger weekday) {
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

static NSArray<NSNumber *> *ARILabelScriptSortedDays(NSArray *days) {
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

static NSString *ARILabelScriptWeekdaySummary(NSArray *days) {
    NSArray<NSNumber *> *sortedDays = ARILabelScriptSortedDays(days);
    if(sortedDays.count == 0) {
        return @"선택 안 함";
    }

    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:sortedDays.count];
    for(NSNumber *day in sortedDays) {
        [titles addObject:ARILabelScriptWeekdayShortTitle(day.integerValue)];
    }
    return [titles componentsJoinedByString:@", "];
}

static NSDate *ARILabelScriptDateFromTimeValue(double value) {
    NSInteger totalMinutes = (NSInteger)llround(value * 60.0);
    if(totalMinutes < 0) totalMinutes = 0;
    if(totalMinutes >= 24 * 60) totalMinutes = 0;

    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.hour = totalMinutes / 60;
    components.minute = totalMinutes % 60;
    return [[NSCalendar currentCalendar] dateFromComponents:components] ?: [NSDate date];
}

static double ARILabelScriptTimeValueFromDate(NSDate *date) {
    NSDateComponents *components = [[NSCalendar currentCalendar] components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date ?: [NSDate date]];
    return (double)components.hour + ((double)components.minute / 60.0);
}

static NSString *ARILabelScriptFormattedMetricValue(double value, NSString *suffix) {
    double roundedValue = round(value);
    if(fabs(value - roundedValue) < 0.01) {
        return [NSString stringWithFormat:@"%ld%@", (long)roundedValue, suffix ?: @""];
    }

    return [NSString stringWithFormat:@"%.1f%@", value, suffix ?: @""];
}

static NSString *ARILabelScriptBlockTitle(NSString *type) {
    if([type isEqualToString:@"set_text"]) return @"텍스트 설정";
    if([type isEqualToString:@"wait"]) return @"대기";
    if([type isEqualToString:@"reload"]) return @"리로드";
    if([type isEqualToString:@"if"]) return @"조건문";
    if([type isEqualToString:@"repeat"]) return @"반복";
    return type.length > 0 ? type : @"블록";
}

static NSString *ARILabelScriptConditionTitle(NSString *type) {
    if([type isEqualToString:@"always"]) return @"항상";
    if([type isEqualToString:@"hour_between"]) return @"시간대";
    if([type isEqualToString:@"weekday_is"]) return @"요일";
    if([type isEqualToString:@"location_contains"]) return @"지역 포함";
    if([type isEqualToString:@"weather_contains"]) return @"날씨 포함";
    if([type isEqualToString:@"temperature_above"]) return @"온도 이상";
    if([type isEqualToString:@"temperature_below"]) return @"온도 미만";
    if([type isEqualToString:@"battery_above"]) return @"배터리 이상";
    if([type isEqualToString:@"battery_below"]) return @"배터리 미만";
    if([type isEqualToString:@"battery_charging"]) return @"충전 중";
    if([type isEqualToString:@"battery_connected"]) return @"충전기 연결됨";
    return type.length > 0 ? type : @"조건";
}

@interface ARILabelScriptTimePickerController : UIViewController
- (instancetype)initWithTitle:(NSString *)title value:(double)value completion:(ARILabelScriptTimePickerCompletion)completion;
@end

@implementation ARILabelScriptTimePickerController {
    UIDatePicker *_timePicker;
    double _value;
    ARILabelScriptTimePickerCompletion _completion;
}

- (instancetype)initWithTitle:(NSString *)title value:(double)value completion:(ARILabelScriptTimePickerCompletion)completion {
    self = [super init];
    if(self) {
        self.title = title;
        _value = value;
        _completion = [completion copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.view.tintColor = kARIPrefTintColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                            target:self
                                                                                            action:@selector(saveSelection)];

    _timePicker = [[UIDatePicker alloc] init];
    _timePicker.translatesAutoresizingMaskIntoConstraints = NO;
    _timePicker.datePickerMode = UIDatePickerModeTime;
    if(@available(iOS 13.4, *)) {
        _timePicker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    }
    _timePicker.minuteInterval = 1;
    _timePicker.date = ARILabelScriptDateFromTimeValue(_value);
    [_timePicker addTarget:self action:@selector(timeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_timePicker];

    [NSLayoutConstraint activateConstraints:@[
        [_timePicker.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_timePicker.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24.0]
    ]];
}

- (void)timeChanged:(UIDatePicker *)sender {
    _value = ARILabelScriptTimeValueFromDate(sender.date);
}

- (void)saveSelection {
    if(_completion) {
        _completion(_value);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end

@interface ARILabelScriptWeekdayPickerController : UITableViewController
- (instancetype)initWithDays:(NSArray<NSNumber *> *)days completion:(ARILabelScriptWeekdayPickerCompletion)completion;
@end

@implementation ARILabelScriptWeekdayPickerController {
    NSMutableOrderedSet<NSNumber *> *_selectedDays;
    ARILabelScriptWeekdayPickerCompletion _completion;
}

- (instancetype)initWithDays:(NSArray<NSNumber *> *)days completion:(ARILabelScriptWeekdayPickerCompletion)completion {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        self.title = @"요일 목록";
        _selectedDays = [NSMutableOrderedSet orderedSetWithArray:ARILabelScriptSortedDays(days)];
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
    cell.textLabel.text = ARILabelScriptWeekdayTitle(weekday);
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
        _completion(ARILabelScriptSortedDays(_selectedDays.array));
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end

@implementation ARILabelScriptBlockEditorController {
    NSMutableDictionary *_block;
}

- (instancetype)initWithBlock:(NSMutableDictionary *)block title:(NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        _block = block ?: [NSMutableDictionary new];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = kARIPrefTintColor;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSString *)_type {
    return [_block[@"type"] isKindOfClass:[NSString class]] ? _block[@"type"] : @"set_text";
}

- (NSMutableArray *)_mutableArrayForKey:(NSString *)key {
    id value = _block[key];
    if([value isKindOfClass:[NSMutableArray class]]) {
        return value;
    }

    NSMutableArray *array = [NSMutableArray new];
    _block[key] = array;
    return array;
}

- (NSMutableDictionary *)_mutableDictionaryForKey:(NSString *)key {
    id value = _block[key];
    if([value isKindOfClass:[NSMutableDictionary class]]) {
        return value;
    }

    NSMutableDictionary *dictionary = [NSMutableDictionary new];
    _block[key] = dictionary;
    return dictionary;
}

- (void)_resetBlockForType:(NSString *)type {
    [_block removeAllObjects];
    _block[@"type"] = type;

    if([type isEqualToString:@"set_text"]) {
        _block[@"text"] = @"새 텍스트";
    } else if([type isEqualToString:@"wait"]) {
        _block[@"seconds"] = @2;
    } else if([type isEqualToString:@"reload"]) {
    } else if([type isEqualToString:@"if"]) {
        _block[@"condition"] = [@{ @"type": @"hour_between", @"start": @20, @"end": @24 } mutableCopy];
        _block[@"then"] = [NSMutableArray arrayWithObject:[@{ @"type": @"set_text", @"text": @"조건 만족" } mutableCopy]];
        _block[@"else"] = [NSMutableArray arrayWithObject:[@{ @"type": @"set_text", @"text": @"조건 불만족" } mutableCopy]];
    } else if([type isEqualToString:@"repeat"]) {
        _block[@"times"] = @0;
        _block[@"steps"] = [NSMutableArray arrayWithObjects:
            [@{ @"type": @"set_text", @"text": @"반복 문구" } mutableCopy],
            [@{ @"type": @"wait", @"seconds": @2 } mutableCopy],
            nil
        ];
    }
}

- (NSString *)_conditionType {
    NSDictionary *condition = [self _mutableDictionaryForKey:@"condition"];
    NSString *type = [condition[@"type"] isKindOfClass:[NSString class]] ? condition[@"type"] : @"always";
    return type;
}

- (NSString *)_conditionSummary {
    NSDictionary *condition = [self _mutableDictionaryForKey:@"condition"];
    NSString *type = [self _conditionType];
    if([type isEqualToString:@"always"]) {
        return @"항상 참";
    }
    if([type isEqualToString:@"hour_between"]) {
        double start = [condition[@"start"] respondsToSelector:@selector(doubleValue)] ? [condition[@"start"] doubleValue] : 0.0;
        double end = [condition[@"end"] respondsToSelector:@selector(doubleValue)] ? [condition[@"end"] doubleValue] : 24.0;
        return [NSString stringWithFormat:@"%@ ~ %@", ARILabelScriptFormattedTimeValue(start), ARILabelScriptFormattedTimeValue(end)];
    }
    if([type isEqualToString:@"weekday_is"]) {
        NSArray *days = [condition[@"days"] isKindOfClass:[NSArray class]] ? condition[@"days"] : @[];
        return [NSString stringWithFormat:@"요일 %@", ARILabelScriptWeekdaySummary(days)];
    }
    if([type isEqualToString:@"location_contains"]) {
        NSString *query = [condition[@"query"] isKindOfClass:[NSString class]] ? condition[@"query"] : @"";
        return [NSString stringWithFormat:@"지역에 \"%@\"", query];
    }
    if([type isEqualToString:@"weather_contains"]) {
        NSString *query = [condition[@"query"] isKindOfClass:[NSString class]] ? condition[@"query"] : @"";
        return [NSString stringWithFormat:@"날씨에 \"%@\"", query];
    }
    if([type isEqualToString:@"temperature_above"]) {
        double value = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
        return [NSString stringWithFormat:@"온도 %@ 이상", ARILabelScriptFormattedMetricValue(value, @"°")];
    }
    if([type isEqualToString:@"temperature_below"]) {
        double value = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
        return [NSString stringWithFormat:@"온도 %@ 미만", ARILabelScriptFormattedMetricValue(value, @"°")];
    }
    if([type isEqualToString:@"battery_above"]) {
        double value = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
        return [NSString stringWithFormat:@"배터리 %@ 이상", ARILabelScriptFormattedMetricValue(value, @"%")];
    }
    if([type isEqualToString:@"battery_below"]) {
        double value = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
        return [NSString stringWithFormat:@"배터리 %@ 미만", ARILabelScriptFormattedMetricValue(value, @"%")];
    }
    if([type isEqualToString:@"battery_charging"]) {
        return @"충전 중";
    }
    if([type isEqualToString:@"battery_connected"]) {
        return @"충전기 연결됨";
    }
    return type;
}

- (void)_showTextInputWithTitle:(NSString *)title
                        message:(NSString *)message
                   placeholder:(NSString *)placeholder
                   initialText:(NSString *)initialText
                    keyboardType:(UIKeyboardType)keyboardType
                     completion:(void (^)(NSString *text))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = placeholder;
        textField.text = initialText;
        textField.keyboardType = keyboardType;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"저장" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        if(completion) completion(alert.textFields.firstObject.text ?: @"");
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSString *type = [self _type];
    if([type isEqualToString:@"if"]) return 4;
    if([type isEqualToString:@"repeat"]) return 3;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSString *type = [self _type];
    if(section == 0) return 1;

    if([type isEqualToString:@"set_text"]) return section == 1 ? 1 : 0;
    if([type isEqualToString:@"wait"]) return section == 1 ? 1 : 0;
    if([type isEqualToString:@"reload"]) return section == 1 ? 1 : 0;

    if([type isEqualToString:@"repeat"]) {
        if(section == 1) return 1;
        if(section == 2) return 1;
    }

    if([type isEqualToString:@"if"]) {
        if(section == 1) {
            NSString *conditionType = [self _conditionType];
            if([conditionType isEqualToString:@"hour_between"]) return 3;
            if([conditionType isEqualToString:@"weekday_is"] ||
               [conditionType isEqualToString:@"location_contains"] ||
               [conditionType isEqualToString:@"weather_contains"] ||
               [conditionType isEqualToString:@"temperature_above"] ||
               [conditionType isEqualToString:@"temperature_below"] ||
               [conditionType isEqualToString:@"battery_above"] ||
               [conditionType isEqualToString:@"battery_below"]) return 2;
            return 1;
        }
        return 1;
    }

    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *type = [self _type];
    if(section == 0) return @"블록 유형";
    if([type isEqualToString:@"set_text"] && section == 1) return @"텍스트";
    if([type isEqualToString:@"wait"] && section == 1) return @"대기";
    if([type isEqualToString:@"reload"] && section == 1) return @"리로드";
    if([type isEqualToString:@"repeat"]) {
        if(section == 1) return @"반복 옵션";
        if(section == 2) return @"반복 블록";
    }
    if([type isEqualToString:@"if"]) {
        if(section == 1) return @"조건";
        if(section == 2) return @"참일 때";
        if(section == 3) return @"아니면";
    }
    return nil;
}

- (UITableViewCell *)_valueCellForTableView:(UITableView *)tableView title:(NSString *)title value:(NSString *)value {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = value;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)_pushTimePickerWithTitle:(NSString *)title value:(double)value completion:(ARILabelScriptTimePickerCompletion)completion {
    ARILabelScriptTimePickerController *controller = [[ARILabelScriptTimePickerController alloc] initWithTitle:title value:value completion:^(double selectedValue) {
        if(completion) {
            completion(selectedValue);
        }
        [self.tableView reloadData];
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)_pushWeekdayPickerWithDays:(NSArray<NSNumber *> *)days completion:(ARILabelScriptWeekdayPickerCompletion)completion {
    ARILabelScriptWeekdayPickerController *controller = [[ARILabelScriptWeekdayPickerController alloc] initWithDays:days completion:^(NSArray<NSNumber *> *selectedDays) {
        if(completion) {
            completion(selectedDays);
        }
        [self.tableView reloadData];
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *type = [self _type];

    if(indexPath.section == 0) {
        return [self _valueCellForTableView:tableView title:@"유형" value:ARILabelScriptBlockTitle(type)];
    }

    if([type isEqualToString:@"set_text"]) {
        NSString *text = [_block[@"text"] isKindOfClass:[NSString class]] ? _block[@"text"] : @"";
        return [self _valueCellForTableView:tableView title:@"텍스트" value:text];
    }

    if([type isEqualToString:@"wait"]) {
        double seconds = [_block[@"seconds"] respondsToSelector:@selector(doubleValue)] ? [_block[@"seconds"] doubleValue] : 0.0;
        return [self _valueCellForTableView:tableView title:@"대기 초" value:[NSString stringWithFormat:@"%.1f", seconds]];
    }

    if([type isEqualToString:@"reload"]) {
        return [self _valueCellForTableView:tableView title:@"동작" value:@"스크립트를 처음부터 다시 실행"];
    }

    if([type isEqualToString:@"repeat"]) {
        if(indexPath.section == 1) {
            NSInteger times = [_block[@"times"] respondsToSelector:@selector(integerValue)] ? [_block[@"times"] integerValue] : 0;
            NSString *value = times <= 0 ? @"무한" : [NSString stringWithFormat:@"%ld", (long)times];
            return [self _valueCellForTableView:tableView title:@"반복 횟수" value:value];
        }

        NSMutableArray *steps = [self _mutableArrayForKey:@"steps"];
        return [self _valueCellForTableView:tableView title:@"하위 블록 편집" value:[NSString stringWithFormat:@"%lu개", (unsigned long)steps.count]];
    }

    if([type isEqualToString:@"if"]) {
        NSMutableDictionary *condition = [self _mutableDictionaryForKey:@"condition"];
        NSString *conditionType = [self _conditionType];
        if(indexPath.section == 1) {
            if(indexPath.row == 0) {
                return [self _valueCellForTableView:tableView title:@"조건 유형" value:ARILabelScriptConditionTitle(conditionType)];
            }

            if([conditionType isEqualToString:@"hour_between"]) {
                if(indexPath.row == 1) {
                    double start = [condition[@"start"] respondsToSelector:@selector(doubleValue)] ? [condition[@"start"] doubleValue] : 0.0;
                    return [self _valueCellForTableView:tableView title:@"시작 시각" value:ARILabelScriptFormattedTimeValue(start)];
                }
                double end = [condition[@"end"] respondsToSelector:@selector(doubleValue)] ? [condition[@"end"] doubleValue] : 24.0;
                return [self _valueCellForTableView:tableView title:@"종료 시각" value:ARILabelScriptFormattedTimeValue(end)];
            }

            NSArray *days = [condition[@"days"] isKindOfClass:[NSArray class]] ? condition[@"days"] : @[];
            if([conditionType isEqualToString:@"weekday_is"]) {
                return [self _valueCellForTableView:tableView title:@"요일 목록" value:ARILabelScriptWeekdaySummary(days)];
            }

            if([conditionType isEqualToString:@"location_contains"] || [conditionType isEqualToString:@"weather_contains"]) {
                NSString *query = [condition[@"query"] isKindOfClass:[NSString class]] ? condition[@"query"] : @"";
                return [self _valueCellForTableView:tableView title:@"키워드" value:query.length > 0 ? query : @"입력 필요"];
            }

            if([conditionType isEqualToString:@"temperature_above"] || [conditionType isEqualToString:@"temperature_below"]) {
                double value = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
                return [self _valueCellForTableView:tableView title:@"기준 온도" value:ARILabelScriptFormattedMetricValue(value, @"°")];
            }

            if([conditionType isEqualToString:@"battery_above"] || [conditionType isEqualToString:@"battery_below"]) {
                double value = [condition[@"value"] respondsToSelector:@selector(doubleValue)] ? [condition[@"value"] doubleValue] : 0.0;
                return [self _valueCellForTableView:tableView title:@"배터리 값" value:ARILabelScriptFormattedMetricValue(value, @"%")];
            }
        }

        if(indexPath.section == 2) {
            NSMutableArray *thenSteps = [self _mutableArrayForKey:@"then"];
            return [self _valueCellForTableView:tableView title:@"참일 때 편집" value:[NSString stringWithFormat:@"%lu개", (unsigned long)thenSteps.count]];
        }

        NSMutableArray *elseSteps = [self _mutableArrayForKey:@"else"];
        return [self _valueCellForTableView:tableView title:@"아니면 편집" value:[NSString stringWithFormat:@"%lu개", (unsigned long)elseSteps.count]];
    }

    return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
}

- (void)_presentTypeSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"블록 유형"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *types = @[
        @{ @"type": @"set_text", @"title": @"텍스트 설정" },
        @{ @"type": @"wait", @"title": @"대기" },
        @{ @"type": @"reload", @"title": @"리로드" },
        @{ @"type": @"if", @"title": @"조건문" },
        @{ @"type": @"repeat", @"title": @"반복" },
    ];

    for(NSDictionary *item in types) {
        [sheet addAction:[UIAlertAction actionWithTitle:item[@"title"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            [self _resetBlockForType:item[@"type"]];
            [self.tableView reloadData];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)_presentConditionTypeSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"조건 유형"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *types = @[
        @{ @"type": @"always", @"title": @"항상" },
        @{ @"type": @"hour_between", @"title": @"시간대" },
        @{ @"type": @"weekday_is", @"title": @"요일" },
        @{ @"type": @"location_contains", @"title": @"지역 포함" },
        @{ @"type": @"weather_contains", @"title": @"날씨 포함" },
        @{ @"type": @"temperature_above", @"title": @"온도 이상" },
        @{ @"type": @"temperature_below", @"title": @"온도 미만" },
        @{ @"type": @"battery_above", @"title": @"배터리 이상" },
        @{ @"type": @"battery_below", @"title": @"배터리 미만" },
        @{ @"type": @"battery_charging", @"title": @"충전 중" },
    ];

    for(NSDictionary *item in types) {
        [sheet addAction:[UIAlertAction actionWithTitle:item[@"title"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            NSMutableDictionary *condition = [self _mutableDictionaryForKey:@"condition"];
            [condition removeAllObjects];
            condition[@"type"] = item[@"type"];
            if([item[@"type"] isEqualToString:@"hour_between"]) {
                condition[@"start"] = @20;
                condition[@"end"] = @24;
            } else if([item[@"type"] isEqualToString:@"weekday_is"]) {
                condition[@"days"] = [NSMutableArray arrayWithObject:@1];
            } else if([item[@"type"] isEqualToString:@"location_contains"]) {
                condition[@"query"] = @"서울";
            } else if([item[@"type"] isEqualToString:@"weather_contains"]) {
                condition[@"query"] = @"비";
            } else if([item[@"type"] isEqualToString:@"temperature_above"]) {
                condition[@"value"] = @25;
            } else if([item[@"type"] isEqualToString:@"temperature_below"]) {
                condition[@"value"] = @10;
            } else if([item[@"type"] isEqualToString:@"battery_above"]) {
                condition[@"value"] = @80;
            } else if([item[@"type"] isEqualToString:@"battery_below"]) {
                condition[@"value"] = @20;
            }
            [self.tableView reloadData];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSString *type = [self _type];
    if(indexPath.section == 0) {
        [self _presentTypeSheet];
        return;
    }

    if([type isEqualToString:@"set_text"]) {
        NSString *text = [_block[@"text"] isKindOfClass:[NSString class]] ? _block[@"text"] : @"";
        [self _showTextInputWithTitle:@"텍스트"
                              message:nil
                         placeholder:@"표시할 텍스트"
                         initialText:text
                         keyboardType:UIKeyboardTypeDefault
                           completion:^(NSString *input) {
            _block[@"text"] = input ?: @"";
        }];
        return;
    }

    if([type isEqualToString:@"wait"]) {
        NSString *value = [_block[@"seconds"] respondsToSelector:@selector(stringValue)] ? [_block[@"seconds"] stringValue] : @"2";
        [self _showTextInputWithTitle:@"대기 초"
                              message:@"예: 2 또는 0.5"
                         placeholder:@"seconds"
                         initialText:value
                         keyboardType:UIKeyboardTypeDecimalPad
                           completion:^(NSString *input) {
            _block[@"seconds"] = @([input doubleValue]);
        }];
        return;
    }

    if([type isEqualToString:@"reload"]) {
        return;
    }

    if([type isEqualToString:@"repeat"]) {
        if(indexPath.section == 1) {
            NSString *value = [_block[@"times"] respondsToSelector:@selector(stringValue)] ? [_block[@"times"] stringValue] : @"0";
            [self _showTextInputWithTitle:@"반복 횟수"
                                  message:@"0이면 무한 반복"
                             placeholder:@"0"
                             initialText:value
                             keyboardType:UIKeyboardTypeNumberPad
                               completion:^(NSString *input) {
                _block[@"times"] = @([input integerValue]);
            }];
            return;
        }

        ARILabelScriptVisualEditorController *controller = [[ARILabelScriptVisualEditorController alloc] initWithSteps:[self _mutableArrayForKey:@"steps"] title:@"반복 블록"];
        [self.navigationController pushViewController:controller animated:YES];
        return;
    }

    if([type isEqualToString:@"if"]) {
        NSMutableDictionary *condition = [self _mutableDictionaryForKey:@"condition"];
        NSString *conditionType = [self _conditionType];
        if(indexPath.section == 1) {
            if(indexPath.row == 0) {
                [self _presentConditionTypeSheet];
                return;
            }

            if([conditionType isEqualToString:@"hour_between"]) {
                if(indexPath.row == 1) {
                    double value = [condition[@"start"] respondsToSelector:@selector(doubleValue)] ? [condition[@"start"] doubleValue] : 20.0;
                    [self _pushTimePickerWithTitle:@"시작 시각" value:value completion:^(double selectedValue) {
                        condition[@"start"] = @(selectedValue);
                    }];
                    return;
                }

                double value = [condition[@"end"] respondsToSelector:@selector(doubleValue)] ? [condition[@"end"] doubleValue] : 24.0;
                [self _pushTimePickerWithTitle:@"종료 시각" value:value completion:^(double selectedValue) {
                    condition[@"end"] = @(selectedValue);
                }];
                return;
            }

            if([conditionType isEqualToString:@"weekday_is"]) {
                NSArray *days = [condition[@"days"] isKindOfClass:[NSArray class]] ? condition[@"days"] : @[];
                [self _pushWeekdayPickerWithDays:days completion:^(NSArray<NSNumber *> *selectedDays) {
                    condition[@"days"] = [selectedDays mutableCopy];
                }];
                return;
            }

            if([conditionType isEqualToString:@"location_contains"] || [conditionType isEqualToString:@"weather_contains"]) {
                NSString *title = [conditionType isEqualToString:@"location_contains"] ? @"지역 키워드" : @"날씨 키워드";
                NSString *placeholder = [conditionType isEqualToString:@"location_contains"] ? @"예: 서울" : @"예: 비";
                NSString *query = [condition[@"query"] isKindOfClass:[NSString class]] ? condition[@"query"] : @"";
                [self _showTextInputWithTitle:title
                                      message:nil
                                 placeholder:placeholder
                                 initialText:query
                                 keyboardType:UIKeyboardTypeDefault
                                   completion:^(NSString *input) {
                    condition[@"query"] = input ?: @"";
                }];
                return;
            }

            if([conditionType isEqualToString:@"temperature_above"] || [conditionType isEqualToString:@"temperature_below"]) {
                NSString *value = [condition[@"value"] respondsToSelector:@selector(stringValue)] ? [condition[@"value"] stringValue] : @"0";
                [self _showTextInputWithTitle:@"기준 온도"
                                      message:@"섭씨 기준"
                                 placeholder:@"예: 20"
                                 initialText:value
                                 keyboardType:UIKeyboardTypeDecimalPad
                                   completion:^(NSString *input) {
                    condition[@"value"] = @([input doubleValue]);
                }];
                return;
            }

            if([conditionType isEqualToString:@"battery_above"] || [conditionType isEqualToString:@"battery_below"]) {
                NSString *value = [condition[@"value"] respondsToSelector:@selector(stringValue)] ? [condition[@"value"] stringValue] : @"50";
                [self _showTextInputWithTitle:@"배터리 값"
                                      message:@"0~100"
                                 placeholder:@"예: 50"
                                 initialText:value
                                 keyboardType:UIKeyboardTypeDecimalPad
                                   completion:^(NSString *input) {
                    condition[@"value"] = @([input doubleValue]);
                }];
            }
            return;
        }

        if(indexPath.section == 2) {
            ARILabelScriptVisualEditorController *controller = [[ARILabelScriptVisualEditorController alloc] initWithSteps:[self _mutableArrayForKey:@"then"] title:@"참일 때"];
            [self.navigationController pushViewController:controller animated:YES];
            return;
        }

        ARILabelScriptVisualEditorController *controller = [[ARILabelScriptVisualEditorController alloc] initWithSteps:[self _mutableArrayForKey:@"else"] title:@"아니면"];
        [self.navigationController pushViewController:controller animated:YES];
    }
}

@end

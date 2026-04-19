//
// Token editor for custom greeting schedules.
//

#include <math.h>

#import "ARICustomGreetingTokenEditorController.h"
#import "../../Shared/ARISharedConstants.h"
#import "../../Shared/ARICustomGreetingScheduleStore.h"

typedef void (^ARICustomGreetingEntrySaveHandler)(NSDictionary *entry);

@interface ARICustomGreetingTimePickerController : UIViewController
- (instancetype)initWithTitle:(NSString *)title value:(double)value completion:(void (^)(double value))completion;
@end

@implementation ARICustomGreetingTimePickerController {
    UIDatePicker *_timePicker;
    double _value;
    void (^_completion)(double);
}

- (instancetype)initWithTitle:(NSString *)title value:(double)value completion:(void (^)(double value))completion {
    self = [super init];
    if(self) {
        self.title = title;
        _value = value;
        _completion = [completion copy];
    }
    return self;
}

- (NSDate *)_dateFromValue:(double)value {
    NSInteger totalMinutes = (NSInteger)llround(value * 60.0);
    if(totalMinutes < 0) totalMinutes = 0;
    if(totalMinutes >= 24 * 60) totalMinutes = 0;

    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.hour = totalMinutes / 60;
    components.minute = totalMinutes % 60;
    return [[NSCalendar currentCalendar] dateFromComponents:components] ?: [NSDate date];
}

- (double)_timeValueFromDate:(NSDate *)date {
    NSDateComponents *components = [[NSCalendar currentCalendar] components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date ?: [NSDate date]];
    return (double)components.hour + ((double)components.minute / 60.0);
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
    _timePicker.date = [self _dateFromValue:_value];
    [_timePicker addTarget:self action:@selector(timeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_timePicker];

    [NSLayoutConstraint activateConstraints:@[
        [_timePicker.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_timePicker.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24.0]
    ]];
}

- (void)timeChanged:(UIDatePicker *)sender {
    _value = [self _timeValueFromDate:sender.date];
}

- (void)saveSelection {
    if(_completion) {
        _completion(_value);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end

@interface ARICustomGreetingEntryEditorController : UITableViewController
- (instancetype)initWithEntry:(NSDictionary *)entry onSave:(ARICustomGreetingEntrySaveHandler)onSave;
@end

@implementation ARICustomGreetingEntryEditorController {
    NSMutableDictionary *_entry;
    ARICustomGreetingEntrySaveHandler _onSave;
}

- (instancetype)initWithEntry:(NSDictionary *)entry onSave:(ARICustomGreetingEntrySaveHandler)onSave {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        _entry = [entry mutableCopy] ?: [@{ @"start": @4, @"text": @"" } mutableCopy];
        _onSave = [onSave copy];
        self.title = @"시간대";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = kARIPrefTintColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"저장"
                                                                               style:UIBarButtonItemStyleDone
                                                                              target:self
                                                                              action:@selector(saveEntry)];
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"시각" : @"문구";
}

- (UITableViewCell *)_valueCellWithTitle:(NSString *)title value:(NSString *)value {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = value;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if(indexPath.section == 0) {
        double value = [_entry[@"start"] respondsToSelector:@selector(doubleValue)] ? [_entry[@"start"] doubleValue] : 4.0;
        return [self _valueCellWithTitle:@"시작" value:[ARICustomGreetingScheduleStore formattedTimeValue:value]];
    }

    NSString *text = [_entry[@"text"] isKindOfClass:[NSString class]] ? _entry[@"text"] : @"";
    return [self _valueCellWithTitle:@"텍스트" value:text.length > 0 ? text : @"비어 있음"];
}

- (void)_showTextEditor {
    NSString *text = [_entry[@"text"] isKindOfClass:[NSString class]] ? _entry[@"text"] : @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"문구"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"문구";
        textField.text = text;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"저장" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        _entry[@"text"] = alert.textFields.firstObject.text ?: @"";
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if(indexPath.section == 0) {
        double value = [_entry[@"start"] respondsToSelector:@selector(doubleValue)] ? [_entry[@"start"] doubleValue] : 4.0;
        ARICustomGreetingTimePickerController *controller = [[ARICustomGreetingTimePickerController alloc] initWithTitle:@"시작 시각" value:value completion:^(double newValue) {
            _entry[@"start"] = @(newValue);
            [self.tableView reloadData];
        }];
        [self.navigationController pushViewController:controller animated:YES];
        return;
    }

    [self _showTextEditor];
}

- (void)saveEntry {
    if(_onSave) {
        _onSave([_entry copy]);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end

@implementation ARICustomGreetingTokenEditorController {
    NSString *_tokenIdentifier;
    NSUserDefaults *_preferences;
    NSString *_tokenName;
    NSMutableArray<NSMutableDictionary *> *_entries;
}

- (instancetype)initWithTokenIdentifier:(NSString *)tokenIdentifier {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        _tokenIdentifier = [tokenIdentifier isKindOfClass:[NSString class]] && tokenIdentifier.length > 0
                               ? [tokenIdentifier copy]
                               : [ARICustomGreetingScheduleStore newTokenIdentifier];
        _preferences = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
        [self _reloadData];
    }
    return self;
}

- (NSInteger)_indexOfTokenIdentifier:(NSString *)tokenIdentifier inTokens:(NSArray<NSDictionary *> *)tokens {
    __block NSInteger foundIndex = NSNotFound;
    [tokens enumerateObjectsUsingBlock:^(NSDictionary *token, NSUInteger index, BOOL *stop) {
        NSString *identifier = [token[@"id"] isKindOfClass:[NSString class]] ? token[@"id"] : @"";
        if([identifier isEqualToString:tokenIdentifier]) {
            foundIndex = (NSInteger)index;
            *stop = YES;
        }
    }];
    return foundIndex;
}

- (NSMutableDictionary *)_mutableTokenDictionaryFromPreferences {
    NSArray<NSMutableDictionary *> *tokens = [ARICustomGreetingScheduleStore editableTokensFromPreferences:_preferences];
    NSInteger index = [self _indexOfTokenIdentifier:_tokenIdentifier inTokens:tokens];
    if(index == NSNotFound) {
        return nil;
    }

    return [tokens[index] mutableCopy];
}

- (void)_reloadData {
    NSMutableDictionary *token = [self _mutableTokenDictionaryFromPreferences];
    _tokenName = [token[@"name"] isKindOfClass:[NSString class]] ? token[@"name"] : @"";

    NSArray *entryArray = [token[@"entries"] isKindOfClass:[NSArray class]] ? token[@"entries"] : @[];
    _entries = [NSMutableArray array];
    for(NSDictionary *entry in entryArray) {
        [_entries addObject:[entry mutableCopy]];
    }

    self.title = _tokenName.length > 0 ? _tokenName : @"새 토큰";
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

- (NSMutableDictionary *)_currentTokenDictionary {
    NSMutableArray<NSMutableDictionary *> *entryCopies = [NSMutableArray arrayWithCapacity:_entries.count];
    for(NSDictionary *entry in _entries) {
        [entryCopies addObject:[entry mutableCopy]];
    }

    return [@{
        @"id": _tokenIdentifier ?: [ARICustomGreetingScheduleStore newTokenIdentifier],
        @"name": _tokenName ?: @"",
        @"entries": entryCopies
    } mutableCopy];
}

- (void)_saveData {
    NSError *error = nil;
    NSMutableArray<NSMutableDictionary *> *tokens = [[ARICustomGreetingScheduleStore editableTokensFromPreferences:_preferences] mutableCopy] ?: [NSMutableArray new];
    NSInteger tokenIndex = [self _indexOfTokenIdentifier:_tokenIdentifier inTokens:tokens];
    NSMutableDictionary *token = [self _currentTokenDictionary];

    if(tokenIndex == NSNotFound) {
        [tokens addObject:token];
    } else {
        tokens[tokenIndex] = token;
    }

    NSString *source = [ARICustomGreetingScheduleStore sourceFromTokenDictionaries:tokens error:&error];
    if(!source) {
        [self _showAlertWithTitle:@"저장 실패" message:error.localizedDescription ?: @"저장할 수 없습니다."];
        return;
    }

    [_preferences setObject:source forKey:ARICustomGreetingTokensPreferenceKey];
    [_preferences synchronize];
    [self _postReloadNotification];
    [self _reloadData];
    [self.tableView reloadData];
}

- (void)_deleteToken {
    NSMutableArray<NSMutableDictionary *> *tokens = [[ARICustomGreetingScheduleStore editableTokensFromPreferences:_preferences] mutableCopy] ?: [NSMutableArray new];
    NSInteger tokenIndex = [self _indexOfTokenIdentifier:_tokenIdentifier inTokens:tokens];
    if(tokenIndex == NSNotFound) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    [tokens removeObjectAtIndex:tokenIndex];

    NSError *error = nil;
    NSString *source = [ARICustomGreetingScheduleStore sourceFromTokenDictionaries:tokens error:&error];
    if(!source) {
        [self _showAlertWithTitle:@"삭제 실패" message:error.localizedDescription ?: @"삭제할 수 없습니다."];
        return;
    }

    [_preferences setObject:source forKey:ARICustomGreetingTokensPreferenceKey];
    [_preferences synchronize];
    [self _postReloadNotification];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)_confirmDeleteToken {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"토큰 삭제"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"삭제" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self _deleteToken];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = kARIPrefTintColor;
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(section == 0) {
        return 1;
    }

    if(section == 1) {
        return _entries.count + 1;
    }

    return 1;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if(section == 0) {
        return @"이름";
    }

    if(section == 1) {
        return @"시간대";
    }

    return nil;
}

- (UITableViewCell *)_valueCellWithTitle:(NSString *)title value:(NSString *)value {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = value;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if(indexPath.section == 0) {
        return [self _valueCellWithTitle:@"이름" value:_tokenName.length > 0 ? _tokenName : @"미설정"];
    }

    if(indexPath.section == 1) {
        if(indexPath.row >= _entries.count) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.textLabel.text = @"시간대 추가";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.imageView.image = [[UIImage systemImageNamed:@"plus.circle.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            cell.imageView.tintColor = kARIPrefTintColor;
            return cell;
        }

        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        NSDictionary *entry = _entries[indexPath.row];
        cell.textLabel.text = [ARICustomGreetingScheduleStore formattedTimeValue:[entry[@"start"] respondsToSelector:@selector(doubleValue)] ? [entry[@"start"] doubleValue] : 0.0];
        NSString *text = [entry[@"text"] isKindOfClass:[NSString class]] ? entry[@"text"] : @"";
        cell.detailTextLabel.text = text.length > 0 ? text : @"비어 있음";
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @"삭제";
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.textColor = [UIColor systemRedColor];
    return cell;
}

- (void)_editTokenName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"토큰 이름"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"예: asdf";
        textField.text = _tokenName;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"저장" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        _tokenName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
        [self _saveData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)_openEntryEditorAtIndex:(NSInteger)index creatingNewEntry:(BOOL)creatingNewEntry {
    NSDictionary *entry = creatingNewEntry ? @{ @"start": @4, @"text": @"" } : [_entries[index] copy];
    ARICustomGreetingEntryEditorController *controller = [[ARICustomGreetingEntryEditorController alloc] initWithEntry:entry onSave:^(NSDictionary *savedEntry) {
        if(creatingNewEntry) {
            [_entries addObject:[savedEntry mutableCopy]];
        } else {
            _entries[index] = [savedEntry mutableCopy];
        }
        [self _saveData];
    }];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if(indexPath.section == 0) {
        [self _editTokenName];
        return;
    }

    if(indexPath.section == 1) {
        if(indexPath.row >= _entries.count) {
            [self _openEntryEditorAtIndex:_entries.count creatingNewEntry:YES];
            return;
        }

        [self _openEntryEditorAtIndex:indexPath.row creatingNewEntry:NO];
        return;
    }

    [self _confirmDeleteToken];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 && indexPath.row < _entries.count;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if(editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != 1 || indexPath.row >= _entries.count) {
        return;
    }

    [_entries removeObjectAtIndex:indexPath.row];
    [self _saveData];
    [tableView reloadData];
}

@end

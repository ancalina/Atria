//
// Dynamic settings page for page labels.
//

#import "ARIListController.h"
#import "../../Shared/ARICustomGreetingScheduleStore.h"

#if __has_include(<UniformTypeIdentifiers/UniformTypeIdentifiers.h>)
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

static NSString *const ARILabelFontModeKey = @"labelFontMode";
static NSString *const ARILabelCustomFontPathKey = @"labelCustomFontPath";
static NSString *const ARILabelNamedFontNameKey = @"labelCustomFontName";
static NSString *const ARILabelFontModeSystem = @"system";
static NSString *const ARILabelFontModeBundle = @"bundle";
static NSString *const ARILabelFontModeImported = @"imported";
static NSString *const ARILabelFontModeNamed = @"named";
static NSString *const ARILabelFontDirectory = @"/var/mobile/Library/Preferences/AtriaFonts";

@interface ARILabelInstalledFontPickerController : UITableViewController <UISearchResultsUpdating>
- (instancetype)initWithSelectionHandler:(void (^)(NSString *fontName))selectionHandler;
@end

@implementation ARILabelInstalledFontPickerController {
    NSArray<NSDictionary *> *_fontDefinitions;
    NSArray<NSDictionary *> *_filteredDefinitions;
    UISearchController *_searchController;
    void (^_selectionHandler)(NSString *fontName);
}

- (instancetype)initWithSelectionHandler:(void (^)(NSString *fontName))selectionHandler {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        self.title = @"설치된 폰트";
        _selectionHandler = [selectionHandler copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = kARIPrefTintColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           target:self
                                                                                           action:@selector(closePicker)];

    NSMutableArray<NSDictionary *> *definitions = [NSMutableArray array];
    NSArray<NSString *> *familyNames = [[UIFont familyNames] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for(NSString *familyName in familyNames) {
        NSArray<NSString *> *fontNames = [[UIFont fontNamesForFamilyName:familyName] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for(NSString *fontName in fontNames) {
            [definitions addObject:@{
                @"family": familyName ?: @"",
                @"name": fontName ?: @""
            }];
        }
    }

    _fontDefinitions = definitions;
    _filteredDefinitions = _fontDefinitions;

    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchResultsUpdater = self;
    _searchController.searchBar.placeholder = @"폰트 검색";
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)closePicker {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)_reloadFilteredDefinitions {
    NSString *query = [[_searchController.searchBar.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if(query.length == 0) {
        _filteredDefinitions = _fontDefinitions;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *definition, __unused NSDictionary<NSString *,id> *bindings) {
            NSString *familyName = [definition[@"family"] lowercaseString];
            NSString *fontName = [definition[@"name"] lowercaseString];
            return [familyName containsString:query] || [fontName containsString:query];
        }];
        _filteredDefinitions = [_fontDefinitions filteredArrayUsingPredicate:predicate];
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

    static NSString *identifier = @"InstalledFont";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if(!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }

    NSDictionary *definition = _filteredDefinitions[indexPath.row];
    NSString *fontName = definition[@"name"];
    NSString *familyName = definition[@"family"];
    cell.textLabel.text = fontName;
    cell.detailTextLabel.text = familyName;
    UIFont *previewFont = [UIFont fontWithName:fontName size:17.0];
    cell.textLabel.font = previewFont ?: [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.row >= _filteredDefinitions.count) {
        return;
    }

    NSString *fontName = _filteredDefinitions[indexPath.row][@"name"];
    if(_selectionHandler) {
        _selectionHandler(fontName);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface ARIPageLabelsListController : ARIListController <UIDocumentPickerDelegate>
@end

@implementation ARIPageLabelsListController {
    NSUserDefaults *_preferences;
}

- (NSArray *)specifiers {
    if(!_specifiers) {
        _preferences = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
        _specifiers = [self loadSpecifiersFromPlistName:@"PageLabels" target:self];
        [self atriaResolveIconPathsForSpecifiers:_specifiers];
        [self _refreshDynamicSpecifiers];
    }

    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self _refreshDynamicSpecifiers];
    [self reloadSpecifiers];
}

- (PSSpecifier *)_specifierForIdentifier:(NSString *)identifier {
    for(PSSpecifier *specifier in self.specifiers) {
        NSString *value = [specifier propertyForKey:@"id"];
        if([value isKindOfClass:[NSString class]] && [value isEqualToString:identifier]) {
            return specifier;
        }
    }
    return nil;
}

- (NSString *)_sanitizedTokenName:(NSString *)rawName {
    NSString *tokenName = ([rawName isKindOfClass:[NSString class]] ? rawName : @"");
    tokenName = [tokenName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while([tokenName hasPrefix:@"%"] && tokenName.length > 0) {
        tokenName = [tokenName substringFromIndex:1];
    }
    while([tokenName hasSuffix:@"%"] && tokenName.length > 0) {
        tokenName = [tokenName substringToIndex:tokenName.length - 1];
    }
    return tokenName;
}

- (NSString *)_customTokenSummaryText {
    NSArray<NSDictionary *> *tokens = [ARICustomGreetingScheduleStore effectiveTokensFromPreferences:_preferences];
    NSMutableArray<NSString *> *tokenNames = [NSMutableArray array];
    for(NSDictionary *token in tokens) {
        NSString *name = [self _sanitizedTokenName:token[@"name"]];
        if(name.length == 0) {
            continue;
        }
        [tokenNames addObject:[NSString stringWithFormat:@"%%%@%%", name]];
    }

    NSString *customTokenText = tokenNames.count > 0 ? [tokenNames componentsJoinedByString:@", "] : @"없음";
    return [NSString stringWithFormat:@"기본 토큰: %%인삿말_한%%, %%BATTERY%%, %%DAY%%, %%TIME%%, %%LOCATION%%, %%TEMPERATURE%%\n맞춤 토큰: %@", customTokenText];
}

- (NSString *)_fontMode {
    NSString *mode = [_preferences objectForKey:ARILabelFontModeKey];
    if(![mode isKindOfClass:[NSString class]] || mode.length == 0) {
        return ARILabelFontModeBundle;
    }
    return mode;
}

- (NSString *)_selectedImportedFontPath {
    NSString *path = [_preferences objectForKey:ARILabelCustomFontPathKey];
    return [path isKindOfClass:[NSString class]] ? path : nil;
}

- (NSString *)_selectedNamedFontName {
    NSString *fontName = [_preferences objectForKey:ARILabelNamedFontNameKey];
    return [fontName isKindOfClass:[NSString class]] ? fontName : nil;
}

- (NSArray<NSString *> *)_importedFontPaths {
    NSArray<NSString *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:ARILabelFontDirectory error:nil] ?: @[];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for(NSString *filename in contents) {
        NSString *extension = filename.pathExtension.lowercaseString;
        if(![@[ @"ttf", @"otf", @"ttc", @"otc" ] containsObject:extension]) {
            continue;
        }
        [paths addObject:[ARILabelFontDirectory stringByAppendingPathComponent:filename]];
    }
    return [paths sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSString *)_fontFooterText {
    NSString *mode = [self _fontMode];
    NSString *fontName = @"기본 시스템 폰트";

    if([mode isEqualToString:ARILabelFontModeImported]) {
        NSString *path = [self _selectedImportedFontPath];
        fontName = path.lastPathComponent.length > 0 ? path.lastPathComponent : @"가져온 폰트";
    } else if([mode isEqualToString:ARILabelFontModeNamed]) {
        NSString *selectedFontName = [self _selectedNamedFontName];
        fontName = selectedFontName.length > 0 ? selectedFontName : @"설치된 폰트";
    } else if([mode isEqualToString:ARILabelFontModeBundle]) {
        fontName = @"Custom.ttf";
    }

    return [NSString stringWithFormat:@"현재 폰트: %@\n가져오거나 선택한 뒤 리스프링하면 적용됩니다.", fontName];
}

- (void)_refreshDynamicSpecifiers {
    [[self _specifierForIdentifier:@"tokenSummaryGroup"] setProperty:[self _customTokenSummaryText] forKey:@"footerText"];
    [[self _specifierForIdentifier:@"fontGroup"] setProperty:[self _fontFooterText] forKey:@"footerText"];
}

- (void)_setFontMode:(NSString *)mode path:(NSString *)path fontName:(NSString *)fontName {
    if(mode.length > 0) {
        [_preferences setObject:mode forKey:ARILabelFontModeKey];
    } else {
        [_preferences removeObjectForKey:ARILabelFontModeKey];
    }

    if(path.length > 0) {
        [_preferences setObject:path forKey:ARILabelCustomFontPathKey];
    } else {
        [_preferences removeObjectForKey:ARILabelCustomFontPathKey];
    }

    if(fontName.length > 0) {
        [_preferences setObject:fontName forKey:ARILabelNamedFontNameKey];
    } else {
        [_preferences removeObjectForKey:ARILabelNamedFontNameKey];
    }

    [_preferences synchronize];
    [self _refreshDynamicSpecifiers];
    [self reloadSpecifiers];
}

- (void)_showSimpleAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"확인" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)_presentInstalledFontPicker {
    ARILabelInstalledFontPickerController *controller = [[ARILabelInstalledFontPickerController alloc] initWithSelectionHandler:^(NSString *fontName) {
        [self _setFontMode:ARILabelFontModeNamed path:nil fontName:fontName];
    }];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)pickFontFromFiles {
#if __has_include(<UniformTypeIdentifiers/UniformTypeIdentifiers.h>)
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFont ] asCopy:YES];
#else
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[ @"public.font" ] inMode:UIDocumentPickerModeImport];
#endif
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)chooseFont {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"폰트 선택"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"기본 시스템 폰트"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self _setFontMode:ARILabelFontModeSystem path:nil fontName:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"번들 폰트 (Custom.ttf)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self _setFontMode:ARILabelFontModeBundle path:nil fontName:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"설치된 폰트에서 선택"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self _presentInstalledFontPicker];
    }]];

    for(NSString *fontPath in [self _importedFontPaths]) {
        NSString *title = fontPath.lastPathComponent;
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            [self _setFontMode:ARILabelFontModeImported path:fontPath fontName:nil];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
    if(sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)resetCustomFont {
    [self _setFontMode:ARILabelFontModeSystem path:nil fontName:nil];
}

- (void)documentPickerWasCancelled:(__unused UIDocumentPickerViewController *)controller {
}

- (void)documentPicker:(__unused UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if(!url) {
        return;
    }

    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:ARILabelFontDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *baseName = url.lastPathComponent.length > 0 ? url.lastPathComponent : @"ImportedFont.ttf";
    NSString *destinationPath = [ARILabelFontDirectory stringByAppendingPathComponent:baseName];
    NSUInteger suffix = 2;
    while([fileManager fileExistsAtPath:destinationPath]) {
        NSString *filename = [[baseName stringByDeletingPathExtension] stringByAppendingFormat:@"-%lu", (unsigned long)suffix];
        NSString *extension = baseName.pathExtension;
        destinationPath = [ARILabelFontDirectory stringByAppendingPathComponent:(extension.length > 0 ? [filename stringByAppendingPathExtension:extension] : filename)];
        suffix++;
    }

    NSError *error = nil;
    if(![fileManager copyItemAtURL:url toURL:[NSURL fileURLWithPath:destinationPath] error:&error]) {
        if(accessed) {
            [url stopAccessingSecurityScopedResource];
        }
        [self _showSimpleAlertWithTitle:@"가져오기 실패" message:error.localizedDescription ?: @"폰트를 가져올 수 없습니다."];
        return;
    }

    if(accessed) {
        [url stopAccessingSecurityScopedResource];
    }

    [self _setFontMode:ARILabelFontModeImported path:destinationPath fontName:nil];
    [self _showSimpleAlertWithTitle:@"가져오기 완료" message:@"리스프링 후 적용됩니다."];
}

@end

//
// Settings page for custom greeting tokens.
//

#import "ARICustomGreetingSettingsController.h"
#import "ARICustomGreetingTokenEditorController.h"
#import "../../Shared/ARICustomGreetingScheduleStore.h"

@implementation ARICustomGreetingSettingsController {
    NSUserDefaults *_preferences;
}

- (instancetype)init {
    self = [super init];
    if(self) {
        _preferences = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
        self.title = @"맞춤 토큰";
    }
    return self;
}

- (NSArray *)specifiers {
    if(!_specifiers) {
        [self _rebuildSpecifiers];
    }

    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self _rebuildSpecifiers];
    [self reloadSpecifiers];
}

- (void)_rebuildSpecifiers {
    NSMutableArray<PSSpecifier *> *specifiers = [NSMutableArray array];

    PSSpecifier *group = [PSSpecifier preferenceSpecifierNamed:@"토큰"
                                                        target:self
                                                           set:nil
                                                           get:nil
                                                        detail:nil
                                                          cell:PSGroupCell
                                                          edit:nil];
    [group setProperty:@"레이블에서 %이름% 형식으로 사용합니다." forKey:@"footerText"];
    [specifiers addObject:group];

    NSArray<NSDictionary *> *tokens = [ARICustomGreetingScheduleStore effectiveTokensFromPreferences:_preferences];
    for(NSDictionary *token in tokens) {
        NSString *tokenIdentifier = [token[@"id"] isKindOfClass:[NSString class]] ? token[@"id"] : @"";
        if(tokenIdentifier.length == 0) {
            continue;
        }

        NSString *title = [ARICustomGreetingScheduleStore tokenNameForDictionary:token fallback:@"미설정"];
        PSSpecifier *tokenSpecifier = [PSSpecifier preferenceSpecifierNamed:title
                                                                     target:self
                                                                        set:nil
                                                                        get:nil
                                                                     detail:nil
                                                                       cell:PSButtonCell
                                                                       edit:nil];
        [tokenSpecifier setProperty:tokenIdentifier forKey:@"tokenIdentifier"];
        [tokenSpecifier setButtonAction:@selector(openToken:)];
        [specifiers addObject:tokenSpecifier];
    }

    PSSpecifier *addSpecifier = [PSSpecifier preferenceSpecifierNamed:@"토큰 추가"
                                                               target:self
                                                                  set:nil
                                                                  get:nil
                                                               detail:nil
                                                                 cell:PSButtonCell
                                                                 edit:nil];
    [addSpecifier setButtonAction:@selector(addToken:)];
    [specifiers addObject:addSpecifier];

    _specifiers = [specifiers copy];
}

- (void)_openTokenWithIdentifier:(NSString *)tokenIdentifier {
    ARICustomGreetingTokenEditorController *controller = [[ARICustomGreetingTokenEditorController alloc] initWithTokenIdentifier:tokenIdentifier];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)openToken:(PSSpecifier *)specifier {
    NSString *tokenIdentifier = [specifier propertyForKey:@"tokenIdentifier"];
    if(![tokenIdentifier isKindOfClass:[NSString class]] || tokenIdentifier.length == 0) {
        return;
    }

    [self _openTokenWithIdentifier:tokenIdentifier];
}

- (void)addToken:(__unused PSSpecifier *)specifier {
    [self _openTokenWithIdentifier:nil];
}

@end

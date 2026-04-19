//
// Settings page for label scripts.
//

#import "ARILabelScriptSettingsController.h"
#import "ARILabelScriptEditorController.h"
#import "ARILabelScriptVisualEditorController.h"
#import "../../Shared/ARILabelScriptCompiler.h"

@implementation ARILabelScriptSettingsController

- (NSArray *)specifiers {
    if(!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"LabelScript" target:self];
    }

    return _specifiers;
}

- (NSUserDefaults *)_preferences {
    return [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
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

- (void)openScriptEditor {
    [self.navigationController pushViewController:[ARILabelScriptEditorController new] animated:YES];
}

- (void)openVisualEditor {
    NSUserDefaults *preferences = [self _preferences];
    NSString *source = [[preferences objectForKey:@"labelScriptSource"] isKindOfClass:[NSString class]]
                           ? [preferences objectForKey:@"labelScriptSource"]
                           : @"";

    NSError *error = nil;
    NSMutableDictionary *script = [ARILabelScriptCompiler mutableScriptDictionaryFromSource:source error:&error];
    if(!script) {
        if(source.length == 0) {
            script = [@{ @"loop": @YES, @"steps": [NSMutableArray new] } mutableCopy];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"스크립트를 열 수 없음"
                                                                           message:error.localizedDescription ?: @"이 스크립트는 소스 편집기에서 열어 주세요."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"소스 편집기"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(__unused UIAlertAction *action) {
                [self openScriptEditor];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
    }

    ARILabelScriptVisualEditorController *controller = [[ARILabelScriptVisualEditorController alloc] initRootControllerWithScript:script];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)installExampleScript {
    NSUserDefaults *preferences = [self _preferences];
    [preferences setObject:[ARILabelScriptCompiler defaultScriptSource] forKey:@"labelScriptSource"];
    [preferences setObject:@(YES) forKey:@"labelScriptEnabled"];
    [preferences synchronize];
    [self _postReloadNotification];
    [self _showAlertWithTitle:@"완료" message:@"예제를 적용했습니다."];
}

- (void)validateCurrentScript {
    NSUserDefaults *preferences = [self _preferences];
    NSString *source = [[preferences objectForKey:@"labelScriptSource"] isKindOfClass:[NSString class]]
                           ? [preferences objectForKey:@"labelScriptSource"]
                           : @"";

    NSError *error = nil;
    NSDictionary *script = [ARILabelScriptCompiler scriptDictionaryFromSource:source error:&error];
    if(!script) {
        [self _showAlertWithTitle:@"검사 실패" message:error.localizedDescription ?: @"스크립트를 읽을 수 없습니다."];
        return;
    }

    NSUInteger count = [[script objectForKey:@"steps"] count];
    [self _showAlertWithTitle:@"검사 완료"
                      message:[NSString stringWithFormat:@"최상위 블록 %lu개", (unsigned long)count]];
}

- (void)clearCurrentScript {
    NSUserDefaults *preferences = [self _preferences];
    [preferences setObject:@"" forKey:@"labelScriptSource"];
    [preferences setObject:@(NO) forKey:@"labelScriptEnabled"];
    [preferences synchronize];
    [self _postReloadNotification];
    [self _showAlertWithTitle:@"완료" message:@"스크립트를 비웠습니다."];
}

@end

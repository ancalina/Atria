//
// Multi-line editor for label scripts.
//

#import "ARILabelScriptEditorController.h"
#import "ARIListController.h"
#import "../../Shared/ARILabelScriptCompiler.h"

@implementation ARILabelScriptEditorController {
    UITextView *_textView;
    NSUserDefaults *_preferences;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"소스 편집기";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    _preferences = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];

    _textView = [[UITextView alloc] init];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    _textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textView.autocorrectionType = UITextAutocorrectionTypeNo;
    _textView.smartDashesType = UITextSmartDashesTypeNo;
    _textView.smartQuotesType = UITextSmartQuotesTypeNo;
    _textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _textView.text = [[_preferences objectForKey:@"labelScriptSource"] isKindOfClass:[NSString class]]
                         ? [_preferences objectForKey:@"labelScriptSource"]
                         : @"";

    [self.view addSubview:_textView];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_textView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [_textView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:12.0],
        [_textView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-12.0],
        [_textView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    ]];

    UIBarButtonItem *exampleButton = [[UIBarButtonItem alloc] initWithTitle:@"예제"
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(insertExampleScript)];
    UIBarButtonItem *validateButton = [[UIBarButtonItem alloc] initWithTitle:@"검사"
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(validateCurrentBuffer)];
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithTitle:@"저장"
                                                                   style:UIBarButtonItemStyleDone
                                                                  target:self
                                                                  action:@selector(saveScript)];
    self.navigationItem.leftBarButtonItem = exampleButton;
    self.navigationItem.rightBarButtonItems = @[ saveButton, validateButton ];
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

- (void)insertExampleScript {
    _textView.text = [ARILabelScriptCompiler defaultScriptSource];
}

- (void)validateCurrentBuffer {
    NSError *error = nil;
    NSDictionary *script = [ARILabelScriptCompiler scriptDictionaryFromSource:_textView.text error:&error];
    if(!script) {
        [self _showAlertWithTitle:@"검사 실패" message:error.localizedDescription ?: @"스크립트를 읽을 수 없습니다."];
        return;
    }

    NSUInteger count = [[script objectForKey:@"steps"] count];
    [self _showAlertWithTitle:@"검사 완료"
                      message:[NSString stringWithFormat:@"최상위 블록 %lu개", (unsigned long)count]];
}

- (void)saveScript {
    NSError *error = nil;
    if(![ARILabelScriptCompiler scriptDictionaryFromSource:_textView.text error:&error]) {
        [self _showAlertWithTitle:@"저장 실패" message:error.localizedDescription ?: @"스크립트를 저장할 수 없습니다."];
        return;
    }

    [_preferences setObject:_textView.text ?: @"" forKey:@"labelScriptSource"];
    [_preferences synchronize];
    [self _postReloadNotification];
    [self.navigationController popViewControllerAnimated:YES];
}

@end

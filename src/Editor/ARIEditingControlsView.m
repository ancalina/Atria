//
// Created by ren7995 on 2021-04-25 21:49:35
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "ARIEditingControlsView.h"
#import "../Manager/ARIEditManager.h"
#import "../Manager/ARITweakManager.h"
#include <float.h>
#include <math.h>

static const double ARIEditorStepValues[] = {
    10.0, 5.0, 2.0, 1.0, 0.5, 0.1, 0.05, 0.01
};
static const NSUInteger ARIEditorStepCount =
    sizeof(ARIEditorStepValues) / sizeof(ARIEditorStepValues[0]);

static UIButton *ARIEditorValueButton(NSString *title) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    [button setTitleColor:[[UIColor labelColor] colorWithAlphaComponent:0.35F]
                  forState:UIControlStateDisabled];
    button.titleLabel.font = [UIFont systemFontOfSize:27 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    button.layer.cornerRadius = 12.0F;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:46.0F],
        [button.heightAnchor constraintEqualToConstant:46.0F]
    ]];
    return button;
}

static NSNumber *ARIEditorNumberFromString(NSString *text) {
    if(text.length == 0) return nil;
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.usesGroupingSeparator = NO;
    NSNumber *number = [formatter numberFromString:text];
    if(number) return number;
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    return [formatter numberFromString:text];
}

@interface ARIEditingControlsView ()
@property (nonatomic, strong) UIToolbar *numberEntryToolbar;
@property (nonatomic, strong) UIBarButtonItem *numberEntryCancelItem;
@property (nonatomic, strong) UIBarButtonItem *numberEntrySignItem;
@property (nonatomic, strong) UIBarButtonItem *numberEntrySpacingItem;
@property (nonatomic, strong) UIBarButtonItem *numberEntryDoneItem;
@property (nonatomic, strong) UIButton *decrementButton;
@property (nonatomic, strong) UIButton *incrementButton;
@property (nonatomic, readwrite, assign) BOOL usesStepButtons;
@property (nonatomic, assign) BOOL integralValue;
@property (nonatomic, assign) NSUInteger stepIndex;
@property (nonatomic, strong) NSNumberFormatter *displayNumberFormatter;
@property (nonatomic, strong) NSLayoutConstraint *stepStackCenterYConstraint;
- (void)_updateNumberEntryToolbar;
- (void)_displayValue:(double)value option:(ARIOption *)option;
- (void)_applyEditorValue:(double)value;
- (void)_changeValueBy:(double)delta;
- (void)toggleNumberEntrySign;
@end

@implementation ARIEditingControlsView

- (instancetype)initWithTargetSetting:(NSString *)key {
    self = [super init];
    if(self) {
        ARIOption *option = [[ARITweakManager sharedInstance] getSettingByKey:key];
        float lower = option.lowerLimit;
        float upper = option.upperLimit;

        self.targetSetting = key;
        self.integralValue = option.isIntegralValue;
        self.usesStepButtons = [[ARITweakManager sharedInstance]
            boolValueForKey:@"useStepperControls"];
        self.stepIndex = 3; // 1
        NSNumberFormatter *displayFormatter = [NSNumberFormatter new];
        displayFormatter.numberStyle = NSNumberFormatterDecimalStyle;
        displayFormatter.usesGroupingSeparator = NO;
        displayFormatter.minimumFractionDigits = 2;
        displayFormatter.maximumFractionDigits = 2;
        self.displayNumberFormatter = displayFormatter;

        // Create slider with labels for low/high limit
        UISlider *slider = [[UISlider alloc] init];
        [slider addTarget:self action:@selector(sliderDidChange:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(sliderDidBegin:) forControlEvents:UIControlEventTouchDown];
        [slider setBackgroundColor:[UIColor clearColor]];
        slider.minimumValue = lower;
        slider.maximumValue = upper;
        slider.continuous = YES;
        [self addSubview:slider];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [slider.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                                constant:-15],
            [slider.widthAnchor constraintEqualToAnchor:self.widthAnchor
                                               constant:-140],
            [slider.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                constant:-15],
            [slider.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
        self.slider = slider;

        UILabel *lowerLabel = [UILabel new];
        lowerLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        lowerLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:lowerLabel];
        lowerLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [lowerLabel.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                                    constant:-15],
            [lowerLabel.widthAnchor constraintEqualToConstant:50],
            [lowerLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                    constant:-15],
            [lowerLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                     constant:15],
        ]];
        self.lowerLabel = lowerLabel;

        UILabel *upperLabel = [UILabel new];
        upperLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        upperLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:upperLabel];
        upperLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [upperLabel.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                                    constant:-15],
            [upperLabel.widthAnchor constraintEqualToConstant:50],
            [upperLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                    constant:-15],
            [upperLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                      constant:-15],
        ]];
        self.upperLabel = upperLabel;
        slider.hidden = self.usesStepButtons;
        lowerLabel.hidden = self.usesStepButtons;
        upperLabel.hidden = self.usesStepButtons;

        // Create toolbar and text field
        UIToolbar *toolbar = [[UIToolbar alloc] init];
        toolbar.translucent = YES;
        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(endTextEntry)];
        UIBarButtonItem *signItem = [[UIBarButtonItem alloc] initWithTitle:@"−"
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(toggleNumberEntrySign)];
        signItem.accessibilityLabel = @"음수 부호 전환";
        UIBarButtonItem *spacingItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(textFieldShouldReturn:)];
        self.numberEntryToolbar = toolbar;
        self.numberEntryCancelItem = cancelItem;
        self.numberEntrySignItem = signItem;
        self.numberEntrySpacingItem = spacingItem;
        self.numberEntryDoneItem = doneItem;

        UITextField *textEntry = [UITextField new];
        textEntry.backgroundColor = [UIColor clearColor];
        textEntry.keyboardType = self.usesStepButtons && self.integralValue
            ? UIKeyboardTypeNumberPad
            : UIKeyboardTypeDecimalPad;
        textEntry.delegate = self;
        textEntry.font = [UIFont systemFontOfSize:self.usesStepButtons ? 28 : 12
                                          weight:self.usesStepButtons ? UIFontWeightSemibold
                                                                       : UIFontWeightRegular];
        textEntry.textAlignment = NSTextAlignmentCenter;
        textEntry.adjustsFontSizeToFitWidth = self.usesStepButtons;
        if(self.usesStepButtons) textEntry.minimumFontSize = 13.0F;
        textEntry.inputAccessoryView = toolbar;
        textEntry.translatesAutoresizingMaskIntoConstraints = NO;
        self.currentValueTextEntry = textEntry;

        if(self.usesStepButtons) {
            UIButton *decrement = ARIEditorValueButton(@"−");
            [decrement addTarget:self
                          action:@selector(decrementValue:)
                forControlEvents:UIControlEventTouchUpInside];
            decrement.accessibilityLabel = @"값 감소";
            self.decrementButton = decrement;

            UIButton *increment = ARIEditorValueButton(@"+");
            [increment addTarget:self
                          action:@selector(incrementValue:)
                forControlEvents:UIControlEventTouchUpInside];
            increment.accessibilityLabel = @"값 증가";
            self.incrementButton = increment;

            UIStackView *stack = [[UIStackView alloc]
                initWithArrangedSubviews:@[ decrement, textEntry, increment ]];
            stack.axis = UILayoutConstraintAxisHorizontal;
            stack.alignment = UIStackViewAlignmentCenter;
            stack.distribution = UIStackViewDistributionFill;
            stack.spacing = 8.0F;
            stack.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:stack];
            self.stepStackCenterYConstraint =
                [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor];
            [NSLayoutConstraint activateConstraints:@[
                [textEntry.widthAnchor constraintGreaterThanOrEqualToConstant:84.0F],
                [textEntry.heightAnchor constraintEqualToConstant:46.0F],
                [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
                self.stepStackCenterYConstraint,
                [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:4.0F],
                [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-4.0F]
            ]];
        } else {
            [self addSubview:textEntry];
            [NSLayoutConstraint activateConstraints:@[
                [textEntry.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                                       constant:-30],
                [textEntry.widthAnchor constraintEqualToConstant:50],
                [textEntry.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
                [textEntry.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            ]];
        }

        [self updateForCurrentOrientation];

        // Detect rotation changes and update text label
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(orientationDidChange:)
                   name:UIDeviceOrientationDidChangeNotification
                 object:nil];
    }
    return self;
}

- (NSString *)_formatValue:(double)val {
    if(!isfinite(val)) return @"—";
    if(self.integralValue || fabs(val - round(val)) < 0.0000001)
        return [NSString stringWithFormat:@"%.0f", val];
    return [self.displayNumberFormatter stringFromNumber:@(val)] ?: @"—";
}

- (double)_effectiveStepValue {
    return ARIEditorStepValues[self.stepIndex];
}

- (NSString *)stepDisplayText {
    if(!self.usesStepButtons) return @"";
    return [NSString stringWithFormat:@"단위 %g", [self _effectiveStepValue]];
}

- (UIMenu *)stepSelectionMenuWithHandler:(void (^)(void))handler {
    if(!self.usesStepButtons) return nil;
    NSUInteger count = self.integralValue ? 4 : ARIEditorStepCount;
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray arrayWithCapacity:count];
    __weak typeof(self) weakSelf = self;
    for(NSUInteger index = 0; index < count; index++) {
        UIAction *action = [UIAction
            actionWithTitle:[NSString stringWithFormat:@"%g×", ARIEditorStepValues[index]]
                      image:nil
                 identifier:nil
                    handler:^(__kindof UIAction *selectedAction) {
                        (void)selectedAction;
                        __strong typeof(weakSelf) self = weakSelf;
                        if(!self) return;
                        self.stepIndex = index;
                        self.decrementButton.accessibilityHint = self.stepDisplayText;
                        self.incrementButton.accessibilityHint = self.stepDisplayText;
                        if(handler) handler();
                    }];
        action.state = index == self.stepIndex
            ? UIMenuElementStateOn
            : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:@"증감 단위"
                           image:nil
                      identifier:nil
                         options:UIMenuOptionsSingleSelection
                        children:actions];
}

- (NSString *)effectiveSettingKey {
    BOOL portrait = UIInterfaceOrientationIsPortrait([ARITweakManager currentDeviceOrientation]);
    if(portrait) return self.targetSetting;
    if([self.targetSetting hasSuffix:@"rows"])
        return [self.targetSetting stringByReplacingOccurrencesOfString:@"rows" withString:@"columns"];
    if([self.targetSetting hasSuffix:@"columns"])
        return [self.targetSetting stringByReplacingOccurrencesOfString:@"columns" withString:@"rows"];
    return self.targetSetting;
}

- (void)setupForSettingKey:(NSString *)key {
    self.targetSetting = key;
    [self updateForCurrentOrientation];
}

- (void)orientationDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateForCurrentOrientation];
}

- (void)updateForCurrentOrientation {
    ARIOption *option = [[ARITweakManager sharedInstance] getSettingByKey:[self effectiveSettingKey]];
    if(option) {
        self.integralValue = option.isIntegralValue;
        if(self.integralValue && ARIEditorStepValues[self.stepIndex] < 1.0)
            self.stepIndex = 3;
        self.currentValueTextEntry.keyboardType =
            self.usesStepButtons && self.integralValue
                ? UIKeyboardTypeNumberPad
                : UIKeyboardTypeDecimalPad;
        self.slider.minimumValue = option.lowerLimit;
        self.slider.maximumValue = option.upperLimit;
    }
    [self _updateNumberEntryToolbar];
    [self updateSliderValue];
}

- (void)_updateNumberEntryToolbar {
    if(!self.numberEntryToolbar) return;
    ARIOption *option = [[ARITweakManager sharedInstance]
        getSettingByKey:[self effectiveSettingKey]];
    BOOL permitsNegative = self.usesStepButtons
        ? option.hardLowerLimit < 0.0
        : self.slider.minimumValue < 0.0F;
    NSArray<UIBarButtonItem *> *items = permitsNegative
        ? @[ self.numberEntryCancelItem, self.numberEntrySignItem,
             self.numberEntrySpacingItem, self.numberEntryDoneItem ]
        : @[ self.numberEntryCancelItem, self.numberEntrySpacingItem,
             self.numberEntryDoneItem ];
    [self.numberEntryToolbar setItems:items animated:NO];
    [self.numberEntryToolbar sizeToFit];
}

- (void)toggleNumberEntrySign {
    NSNumber *number = ARIEditorNumberFromString(self.currentValueTextEntry.text);
    if(number) self.currentValueTextEntry.text = [self _formatValue:-number.doubleValue];
}

- (void)updateSliderValue {
    ARIEditManager *editManager = [ARIEditManager sharedInstance];
    // The page indicator occupies the 10-point strip below the title only in
    // per-page mode. Center the controls in the remaining visual space.
    self.stepStackCenterYConstraint.constant = editManager.singleListMode ? 5.0F : 0.0F;
    SBIconListView *listView = [editManager currentIconListViewIfSinglePage];
    BOOL targetAvailable = !editManager.singleListMode || listView != nil;
    self.slider.enabled = targetAvailable;
    self.currentValueTextEntry.enabled = targetAvailable;
    if(!targetAvailable) {
        self.decrementButton.enabled = self.incrementButton.enabled = NO;
        self.currentValueTextEntry.text = @"—";
        return;
    }

    ARITweakManager *manager = [ARITweakManager sharedInstance];
    NSString *key = [self effectiveSettingKey];
    ARIOption *option = [manager getSettingByKey:key];
    id rawValue = [manager rawValueForKey:key forListView:listView];
    double val = [rawValue respondsToSelector:@selector(doubleValue)]
        ? [rawValue doubleValue]
        : 0.0;
    [self _displayValue:val option:option];
}

- (void)_displayValue:(double)val option:(ARIOption *)option {
    self.slider.value = (float)val;
    self.lowerLabel.text = [self _formatValue:self.slider.minimumValue];
    self.upperLabel.text = [self _formatValue:self.slider.maximumValue];
    self.currentValueTextEntry.text = [self _formatValue:val];
    self.currentValueTextEntry.accessibilityLabel = option.translation;
    self.currentValueTextEntry.accessibilityValue = self.currentValueTextEntry.text;

    if(self.usesStepButtons) {
        self.decrementButton.enabled = isfinite(val) && val > option.hardLowerLimit;
        self.incrementButton.enabled = isfinite(val) && val < option.hardUpperLimit;
        self.decrementButton.accessibilityHint = self.stepDisplayText;
        self.incrementButton.accessibilityHint = self.stepDisplayText;
    }
}

- (void)sliderDidChange:(UISlider *)slider {
    [self _applyEditorValue:slider.value];
}

- (void)_applyEditorValue:(double)value {
    if(!isfinite(value)) {
        [self updateSliderValue];
        return;
    }

    ARITweakManager *manager = [ARITweakManager sharedInstance];
    NSString *key = [self effectiveSettingKey];
    ARIOption *option = [manager getSettingByKey:key];
    if(self.integralValue) value = round(value);
    if(option.hardUpperLimit > option.hardLowerLimit) {
        value = fmax(option.hardLowerLimit,
                     fmin(option.hardUpperLimit, value));
    }
    ARIEditManager *editManager = [ARIEditManager sharedInstance];
    SBIconListView *list = [editManager currentIconListViewIfSinglePage];
    if(editManager.singleListMode && !list) return;
    id currentValue = [manager rawValueForKey:key forListView:list];
    double current = [currentValue respondsToSelector:@selector(doubleValue)]
        ? [currentValue doubleValue]
        : 0.0;
    if(fabs(current - value) > DBL_EPSILON * MAX(1.0, MAX(fabs(current), fabs(value)))) {
        [manager setValue:@(value) forKey:key forListView:list];
        if([key isEqualToString:@"dock_columns"] || [key isEqualToString:@"dock_rows"])
            [editManager setDockLayoutQueued];
        [manager updateLayoutForEditing:YES];
    }
    [self _displayValue:value option:option];
}

- (void)_changeValueBy:(double)delta {
    [[ARITweakManager sharedInstance] feedbackForButton];
    id rawValue = [[ARITweakManager sharedInstance]
        rawValueForKey:[self effectiveSettingKey]
            forListView:[[ARIEditManager sharedInstance] currentIconListViewIfSinglePage]];
    double value = [rawValue respondsToSelector:@selector(doubleValue)]
        ? [rawValue doubleValue]
        : 0.0;
    [self _applyEditorValue:value + delta];
}

- (void)decrementValue:(UIButton *)sender {
    (void)sender;
    [self _changeValueBy:-[self _effectiveStepValue]];
}

- (void)incrementValue:(UIButton *)sender {
    (void)sender;
    [self _changeValueBy:[self _effectiveStepValue]];
}

- (void)sliderDidBegin:(UISlider *)slider {
    [[ARITweakManager sharedInstance] feedbackForButton];
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    [ARITweakManager dismissFloatingDockIfPossible];
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSNumber *number = ARIEditorNumberFromString(self.currentValueTextEntry.text);
    if(number) [self _applyEditorValue:number.doubleValue];
    [self endTextEntry];
    return YES;
}

- (void)endTextEntry {
    [self.currentValueTextEntry resignFirstResponder];
    // Restore/update text
    [self updateSliderValue];
    [ARITweakManager presentFloatingDockIfPossible];
}

@end

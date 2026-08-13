//
// Created by ren7995 on 2021-04-25 17:41:17
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "ARIEditingMainView.h"
#import "../Manager/ARIEditManager.h"
#import "../Manager/ARITweakManager.h"
#import "ARISettingCollectionViewHost.h"

@interface ARIEditorStepSizeButton : UIButton
@end

@implementation ARIEditorStepSizeButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    // Keep the compact top-bar appearance while providing a 44-point-tall
    // touch target on every supported phone size.
    return CGRectContainsPoint(CGRectInset(self.bounds, 0.0F, -10.0F), point);
}
@end

@implementation ARIEditingMainView {
    NSMutableArray *_validsettingsForTarget;
    NSLayoutConstraint *_topAnchor;
    NSLayoutConstraint *_heightAnchor;
    NSLayoutConstraint *_widthAnchor;
    ARISettingCollectionViewHost *_collection;
    UIImageView *_reset;
    UIButton *_stepButton;
    UIImageView *_perPage;
    UIImageView *_xButton;
    UILabel *_instructions;
    BOOL _showTooltips;
    CGFloat _panTouchdownOffset;
    CGFloat _editorSpace;
    BOOL _optionsTransitionInFlight;
    BOOL _hasPresentedOptions;
    CGSize _lastHostSize;
    CGFloat _lastHostBottomInset;
}

@synthesize validsettingsForTarget = _validsettingsForTarget;

- (instancetype)initWithTarget:(NSString *)targetLoc {
    self = [super init];
    if(self) {
        NSOrderedSet *allSettingsKeys = [[ARITweakManager sharedInstance] editorSettingsKeys];
        _validsettingsForTarget = [NSMutableArray new];
        for(NSString *setting in allSettingsKeys) {
            if([setting hasPrefix:targetLoc]) {
                [_validsettingsForTarget addObject:setting];
            }
        }
        _showTooltips = [[ARITweakManager sharedInstance] boolValueForKey:@"showTooltips"];
        BOOL usesStepButtons = [[ARITweakManager sharedInstance]
            boolValueForKey:@"useStepperControls"];

        // Subtle shadow to make the editor pop from the homescreen background
        self.layer.cornerRadius = 12;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowOpacity = 0.5F;
        self.layer.shadowOffset = CGSizeZero;
        self.layer.shadowRadius = 5;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        CGFloat sw = UIScreen.mainScreen.bounds.size.width;
        _widthAnchor = [self.widthAnchor constraintEqualToConstant:sw < 500 ? sw - 25 : 475];
        _heightAnchor = [self.heightAnchor constraintEqualToConstant:[self getBaseHeight]];
        [NSLayoutConstraint activateConstraints:@[
            _widthAnchor,
            _heightAnchor,
        ]];

        // Background blur
        UIVisualEffectView *matEffect = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        [self addSubview:matEffect];
        matEffect.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [matEffect.widthAnchor constraintEqualToAnchor:self.widthAnchor],
            [matEffect.heightAnchor constraintEqualToAnchor:self.heightAnchor],
            [matEffect.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [matEffect.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        matEffect.layer.masksToBounds = YES;
        matEffect.layer.cornerRadius = 12;
        matEffect.layer.cornerCurve = kCACornerCurveContinuous;
        UILabel *currentSettingLabel = [UILabel new];
        currentSettingLabel.text = @"설정을 선택하세요";
        currentSettingLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
        currentSettingLabel.textAlignment = NSTextAlignmentCenter;
        currentSettingLabel.numberOfLines = 1;
        currentSettingLabel.adjustsFontSizeToFitWidth = YES;
        currentSettingLabel.minimumScaleFactor = 0.5F;
        [self addSubview:currentSettingLabel];
        currentSettingLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [currentSettingLabel.heightAnchor constraintEqualToConstant:30],
            [currentSettingLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [currentSettingLabel.topAnchor constraintEqualToAnchor:self.topAnchor
                                                          constant:5],
        ]];
        self.currentSettingLabel = currentSettingLabel;

        UILabel *ppi = [UILabel new];
        ppi.font = [UIFont systemFontOfSize:9 weight:UIFontWeightRegular];
        ppi.textAlignment = NSTextAlignmentCenter;
        [self.currentSettingLabel addSubview:ppi];
        ppi.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [ppi.widthAnchor constraintEqualToAnchor:currentSettingLabel.widthAnchor],
            [ppi.heightAnchor constraintEqualToConstant:10],
            [ppi.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [ppi.topAnchor constraintEqualToAnchor:currentSettingLabel.bottomAnchor],
        ]];
        self.perPageIndicator = ppi;

        _instructions = [UILabel new];
        _instructions.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        [_instructions setLineBreakMode:NSLineBreakByWordWrapping];
        _instructions.textAlignment = NSTextAlignmentCenter;
        [self.currentSettingLabel addSubview:_instructions];
        _instructions.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [_instructions.widthAnchor constraintEqualToAnchor:self.widthAnchor
                                                      constant:-20],
            [_instructions.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                       constant:-5],
            [_instructions.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_instructions.heightAnchor constraintEqualToConstant:15],
        ]];
        if(!_showTooltips) {
            [_instructions setHidden:YES];
        }

        // Close button
        _xButton = [UIImageView new];
        _xButton.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_xButton];
        _xButton.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [_xButton.widthAnchor constraintEqualToConstant:22.5],
            [_xButton.heightAnchor constraintEqualToConstant:22.5],
            [_xButton.topAnchor constraintEqualToAnchor:self.topAnchor
                                               constant:7.5],
            [_xButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                    constant:-7.5],
        ]];
        _xButton.image = [UIImage systemImageNamed:@"xmark"];
        _xButton.tintColor = [UIColor labelColor];

        _reset = [UIImageView new];
        [self addSubview:_reset];
        _reset.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [_reset.widthAnchor constraintEqualToConstant:22.5],
            [_reset.heightAnchor constraintEqualToConstant:22.5],
            [_reset.topAnchor constraintEqualToAnchor:self.topAnchor
                                             constant:7.5],
            [_reset.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                 constant:7.5],
        ]];
        _reset.image = [UIImage systemImageNamed:@"gobackward"];
        _reset.tintColor = [UIColor labelColor];
        _reset.alpha = 0;

        // Step-size selector shown only when the optional −/+ editor is used.
        _stepButton = [ARIEditorStepSizeButton buttonWithType:UIButtonTypeSystem];
        _stepButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        [_stepButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        _stepButton.contentEdgeInsets = UIEdgeInsetsMake(3, 7, 3, 7);
        _stepButton.hidden = YES;
        _stepButton.alpha = 0;
        _stepButton.accessibilityLabel = @"증감 단위";
        _stepButton.showsMenuAsPrimaryAction = YES;
        _stepButton.changesSelectionAsPrimaryAction = YES;
        [self addSubview:_stepButton];
        _stepButton.translatesAutoresizingMaskIntoConstraints = NO;
        if(usesStepButtons) {
            [currentSettingLabel.leadingAnchor
                constraintEqualToAnchor:_stepButton.trailingAnchor
                               constant:4.0F].active = YES;
        } else {
            [currentSettingLabel.leadingAnchor
                constraintEqualToAnchor:self.leadingAnchor
                               constant:45.0F].active = YES;
        }
        [NSLayoutConstraint activateConstraints:@[
            [_stepButton.heightAnchor constraintEqualToConstant:24.0F],
            [_stepButton.widthAnchor constraintLessThanOrEqualToConstant:72.0F],
            [_stepButton.centerYAnchor constraintEqualToAnchor:_reset.centerYAnchor],
            [_stepButton.leadingAnchor constraintEqualToAnchor:_reset.trailingAnchor constant:7.0F]
        ]];

        // Toggle per-page
        _perPage = [UIImageView new];
        [self addSubview:_perPage];
        _perPage.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [_perPage.widthAnchor constraintEqualToConstant:22.5],
            [_perPage.heightAnchor constraintEqualToConstant:22.5],
            [_perPage.topAnchor constraintEqualToAnchor:self.topAnchor
                                               constant:7.5],
            [_perPage.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                   constant:7.5],
        ]];
        _perPage.tintColor = [UIColor labelColor];
        _perPage.alpha = 0;
        // No per-page
        if([targetLoc isEqualToString:@"dock"] || [targetLoc isEqualToString:@"pagedot"]) _perPage.hidden = YES;

        [NSLayoutConstraint activateConstraints:@[
            [currentSettingLabel.trailingAnchor
                constraintLessThanOrEqualToAnchor:_xButton.leadingAnchor
                                          constant:-4.0F]
        ]];

        UITapGestureRecognizer *xTapped = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeButtonTapped:)];
        [_xButton addGestureRecognizer:xTapped];
        _xButton.userInteractionEnabled = YES;

        UITapGestureRecognizer *resetAction = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(resetSetting:)];
        [_reset addGestureRecognizer:resetAction];
        _reset.userInteractionEnabled = NO;

        UITapGestureRecognizer *openOptions = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleOptionsView:)];
        [currentSettingLabel addGestureRecognizer:openOptions];
        currentSettingLabel.userInteractionEnabled = YES;

        UITapGestureRecognizer *togglePerPage = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handePerPageTap:)];
        [_perPage addGestureRecognizer:togglePerPage];
        _perPage.userInteractionEnabled = YES;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(updateForPan:)];
        [self addGestureRecognizer:pan];

        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(keyboardWillShow:)
                   name:UIKeyboardWillChangeFrameNotification
                 object:nil];

        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(keyboardDidHide:)
                   name:UIKeyboardDidHideNotification
                 object:nil];

        [self updateIsSingleListView];
    }
    return self;
}

- (void)setupForSettingKey:(NSString *)key {
    if(![key isKindOfClass:[NSString class]] || key.length == 0 ||
       ![[ARITweakManager sharedInstance] getSettingByKey:key]) return;

    ARITweakManager *manager = [ARITweakManager sharedInstance];

    self.currentSetting = key;
    _reset.userInteractionEnabled = YES;
    self.currentSettingLabel.text = [manager getSettingByKey:key].translation;

    if(!self.currentControls) {
        ARIEditingControlsView *controls = [[ARIEditingControlsView alloc] initWithTargetSetting:key];
        [self addSubview:controls];
        controls.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [controls.widthAnchor constraintEqualToAnchor:self.widthAnchor],
            [controls.heightAnchor constraintEqualToConstant:65],
            [controls.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [controls.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                  constant:_showTooltips ? -15 : 0],
        ]];
        [self layoutIfNeeded];
        self.currentControls = controls;
    } else {
        [self.currentControls setupForSettingKey:key];
    }
    [self _updateStepButton];
}

- (void)_updateStepButton {
    BOOL visible = self.currentControls.usesStepButtons && self.currentSetting.length > 0 &&
                   _heightAnchor.constant == [self getBaseHeight];
    _stepButton.hidden = !self.currentControls.usesStepButtons;
    if(self.currentControls.usesStepButtons) {
        NSString *stepText = [self.currentControls stepDisplayText];
        NSString *compactText = [stepText hasPrefix:@"단위 "]
            ? [[stepText substringFromIndex:3] stringByAppendingString:@"×"]
            : stepText;
        [_stepButton setTitle:compactText forState:UIControlStateNormal];
        _stepButton.accessibilityValue = stepText;
        __weak typeof(self) weakSelf = self;
        _stepButton.menu = [self.currentControls stepSelectionMenuWithHandler:^{
            __strong typeof(weakSelf) self = weakSelf;
            if(!self) return;
            [[ARITweakManager sharedInstance] feedbackForButton];
            self->_stepButton.accessibilityValue = self.currentControls.stepDisplayText;
        }];
    } else {
        [_stepButton setTitle:nil forState:UIControlStateNormal];
        _stepButton.accessibilityValue = nil;
        _stepButton.menu = nil;
    }
    _stepButton.alpha = visible ? 1.0F : 0.0F;
    _stepButton.userInteractionEnabled = visible;
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if(!self.superview) return;
    if(_topAnchor) {
        _topAnchor.active = NO;
        _topAnchor = nil;
    }
    CGFloat hostWidth = CGRectGetWidth(self.superview.bounds);
    if(hostWidth > 0) _widthAnchor.constant = MIN(MAX(hostWidth - 25.0F, 200.0F), 475.0F);
    [self _resetEditorSpace];
    _lastHostSize = self.superview.bounds.size;
    _lastHostBottomInset = self.superview.safeAreaInsets.bottom;
    BOOL openFromTop = [[ARITweakManager sharedInstance] intValueForKey:@"editorOpenFrom"] == 1;
    _topAnchor = [self.topAnchor constraintEqualToAnchor:self.superview.topAnchor
                                                constant:openFromTop ? 50 : _editorSpace - _heightAnchor.constant];
    _topAnchor.active = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *hostView = self.superview;
    if(!hostView) return;

    CGSize hostSize = hostView.bounds.size;
    CGFloat bottomInset = hostView.safeAreaInsets.bottom;
    BOOL hostGeometryChanged =
        fabs(hostSize.width - _lastHostSize.width) > 0.5F ||
        fabs(hostSize.height - _lastHostSize.height) > 0.5F ||
        fabs(bottomInset - _lastHostBottomInset) > 0.5F;
    if(!hostGeometryChanged) return;
    _lastHostSize = hostSize;
    _lastHostBottomInset = bottomInset;

    // SpringBoard can keep this editor alive while its host changes size
    // (rotation, Stage Manager, Split View). Refit the width and preserve a
    // bottom-docked editor; otherwise clamp its dragged position on-screen.
    CGFloat hostWidth = hostSize.width;
    CGFloat desiredWidth = MIN(MAX(hostWidth - 25.0F, 200.0F), 475.0F);
    if(fabs(_widthAnchor.constant - desiredWidth) > 0.5F)
        _widthAnchor.constant = desiredWidth;

    CGFloat oldMaximumTop = _editorSpace - _heightAnchor.constant;
    BOOL wasDockedAtBottom = _topAnchor &&
        fabs(_topAnchor.constant - oldMaximumTop) <= 1.0F;
    CGFloat usableHeight = MAX(hostSize.height - bottomInset,
                               [self getBaseHeight] + 50.0F);
    _editorSpace = fmax(usableHeight * 0.85F, usableHeight - 140.0F);

    if(_topAnchor) {
        CGFloat maximumTop = MAX(50.0F, _editorSpace - _heightAnchor.constant);
        _topAnchor.constant = wasDockedAtBottom
            ? maximumTop
            : fmax(50.0F, fmin(_topAnchor.constant, maximumTop));
    }
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSValue *frameValue = notification.userInfo[UIKeyboardFrameEndUserInfoKey];
    UIView *hostView = self.superview;
    if(![frameValue isKindOfClass:[NSValue class]] || !hostView) {
        [self _resetEditorSpace];
        return;
    }

    CGRect keyboardFrame = frameValue.CGRectValue;
    CGRect hostKeyboardFrame;
    if(self.window) {
        CGRect windowFrame = [self.window convertRect:keyboardFrame fromWindow:nil];
        hostKeyboardFrame = [hostView convertRect:windowFrame fromView:self.window];
    } else {
        hostKeyboardFrame = [hostView convertRect:keyboardFrame fromView:nil];
    }

    BOOL keyboardVisible = CGRectGetMinY(hostKeyboardFrame) < CGRectGetHeight(hostView.bounds);
    if(keyboardVisible) {
        [self setEditorSpace:MAX(CGRectGetMinY(hostKeyboardFrame) - 25.0F,
                                 hostView.safeAreaInsets.top + [self getBaseHeight])];
    } else {
        [self _resetEditorSpace];
    }
}

- (void)keyboardDidHide:(NSNotification *)notification {
    (void)notification;
    [self _resetEditorSpace];
}

- (void)_resetEditorSpace {
    UIView *hostView = self.superview;
    CGFloat height = hostView ? CGRectGetHeight(hostView.bounds) : UIScreen.mainScreen.bounds.size.height;
    CGFloat bottomInset = hostView ? hostView.safeAreaInsets.bottom : 0.0F;
    CGFloat usableHeight = MAX(height - bottomInset, [self getBaseHeight] + 50.0F);
    [self setEditorSpace:fmax(usableHeight * 0.85F, usableHeight - 140.0F)];
}

- (void)updateForPan:(UIPanGestureRecognizer *)recognizer {
    if(!self.superview) return;
    if(recognizer.state == UIGestureRecognizerStateBegan) {
        _panTouchdownOffset = [recognizer locationInView:self.superview].y - self.frame.origin.y;
    } else if(recognizer.state != UIGestureRecognizerStateEnded) {
        CGFloat position = [recognizer locationInView:self.superview].y - _panTouchdownOffset;
        _topAnchor.constant = fmax(50.0F,
            fmin(position, _editorSpace - _heightAnchor.constant));
        [self.superview layoutIfNeeded];
    }
}

- (void)setEditorSpace:(CGFloat)space {
    _editorSpace = space;
    if(_topAnchor.constant + _heightAnchor.constant > _editorSpace) [self _animateToPosition:_editorSpace - _heightAnchor.constant];
}

- (void)_animateToPosition:(CGFloat)position {
    [UIView animateWithDuration:0.1f
                     animations:^{
                         [self.superview layoutIfNeeded];
                         _topAnchor.constant = fmax(50.0F,
                             fmin(position, _editorSpace - _heightAnchor.constant));
                         [self.superview layoutIfNeeded];
                     }];
}

- (void)closeButtonTapped:(UITapGestureRecognizer *)tap {
    [[ARITweakManager sharedInstance] feedbackForButton];
    [[ARIEditManager sharedInstance] toggleEditView:NO withTargetLocation:nil];
}

- (void)resetSetting:(UITapGestureRecognizer *)tap {
    if(![self.currentSetting isKindOfClass:[NSString class]] || self.currentSetting.length == 0) return;

    ARITweakManager *manager = [ARITweakManager sharedInstance];
    ARIEditManager *editManager = [ARIEditManager sharedInstance];
    SBIconListView *listView = [editManager currentIconListViewIfSinglePage];
    if(editManager.singleListMode && !listView) return;
    [manager feedbackForButton];
    NSString *effectiveKey = [self.currentControls effectiveSettingKey] ?: self.currentSetting;
    [manager resetValueForKey:effectiveKey forListView:listView];
    if([effectiveKey isEqualToString:@"dock_columns"] ||
       [effectiveKey isEqualToString:@"dock_rows"])
        [editManager setDockLayoutQueued];
    [self.currentControls updateSliderValue];

    [manager updateLayoutForEditing:YES];
}

- (void)handePerPageTap:(UITapGestureRecognizer *)tap {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    [manager feedbackForButton];
    [[ARIEditManager sharedInstance] toggleSingleListMode];

    [self updateIsSingleListView];
}

- (void)updateIsSingleListView {
    ARIEditManager *editManager = [ARIEditManager sharedInstance];
    SBIconListView *listView = [editManager currentIconListViewIfSinglePage];
    if(listView) {
        // Single list mode
        ARITweakManager *manager = [ARITweakManager sharedInstance];
        NSUInteger index = [manager indexOfListView:listView];
        self.perPageIndicator.text = index == NSNotFound
            ? @""
            : [NSString stringWithFormat:@"Page %lu Only", (unsigned long)index + 1];

        _perPage.image = [UIImage systemImageNamed:@"doc.fill"];
    } else if(editManager.singleListMode) {
        self.perPageIndicator.text = @"Page unavailable";
        _perPage.image = [UIImage systemImageNamed:@"exclamationmark.doc"]
            ?: [UIImage systemImageNamed:@"doc.fill"];
    } else {
        // Global
        self.perPageIndicator.text = @"";

        _perPage.image = [UIImage systemImageNamed:@"doc"];
    }
    [self.currentControls updateSliderValue];
}

- (void)showInitialOptionsIfNeeded {
    if(_hasPresentedOptions || _optionsTransitionInFlight || _collection || self.currentSetting.length > 0) return;
    [self toggleOptionsView:nil];
}

- (void)toggleOptionsView:(UITapGestureRecognizer *)tap {
    if(_optionsTransitionInFlight) return;

    // Present collection view with settings options
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    [manager feedbackForButton];

    if(_heightAnchor.constant == [self getBaseHeight]) {
        // Activate
        _optionsTransitionInFlight = YES;
        _hasPresentedOptions = YES;
        [self.currentSettingLabel setText:@"설정을 선택하세요"];
        [_instructions setText:@"이 페이지만 편집하려면 왼쪽 위 페이지 아이콘을 클릭하세요."];

        if(self.currentControls) {
            [self.currentControls endTextEntry];
        }

        ARISettingCollectionViewHost *collection = [[ARISettingCollectionViewHost alloc] initWithEditor:self];
        _collection = collection;
        collection.userInteractionEnabled = NO;
        collection.translatesAutoresizingMaskIntoConstraints = NO;
        collection.alpha = 0;
        [self addSubview:collection];
        [NSLayoutConstraint activateConstraints:@[
            [collection.widthAnchor constraintEqualToAnchor:self.widthAnchor],
            [collection.topAnchor constraintEqualToAnchor:self.currentSettingLabel.bottomAnchor
                                                  constant:15],
            [collection.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                     constant:_showTooltips ? -20 : -5],
            [collection.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
        [UIView animateWithDuration:0.3f
                         animations:^{
                             collection.alpha = 1;
                             _instructions.alpha = 1;

                             [self.superview layoutIfNeeded];
                             // Set height anchor
                             _heightAnchor.constant = [self getBaseHeight] + 30;
                             [self _resetEditorSpace];
                             [self.superview layoutIfNeeded];

                             // Fade
                             self.currentSettingLabel.alpha = 0.4;
                             self.currentControls.alpha = 0;
                             _reset.alpha = 0;
                             _stepButton.alpha = 0;
                             _stepButton.userInteractionEnabled = NO;
                             _perPage.alpha = 1;
                         }
                         completion:^(BOOL finished) {
                             if(self->_collection == collection) {
                                 collection.userInteractionEnabled = YES;
                             }
                             self->_optionsTransitionInFlight = NO;
                         }];
    } else {
        // End
        _optionsTransitionInFlight = YES;
        ARISettingCollectionViewHost *collection = _collection;
        collection.userInteractionEnabled = NO;
        [_instructions setText:@"상단 레이블을 탭해 전으로 돌아가세요"];

        [UIView animateWithDuration:0.3f
            animations:^{
                collection.alpha = 0;
                _instructions.alpha = 0.5f;

                [self.superview layoutIfNeeded];
                // Set height anchor
                _heightAnchor.constant = [self getBaseHeight];
                [self _resetEditorSpace];
                [self.superview layoutIfNeeded];

                // Unfade
                self.currentSettingLabel.alpha = 1;
                self.currentControls.alpha = 1;
                _reset.alpha = self.currentSetting.length > 0 ? 1 : 0;
                [self _updateStepButton];
                _perPage.alpha = 0;
            }
            completion:^(BOOL finished) {
                [collection removeFromSuperview];
                if(self->_collection == collection) self->_collection = nil;
                self->_optionsTransitionInFlight = NO;
            }];
    }
}

- (float)getBaseHeight {
    return _showTooltips ? 110.0f : 100.0f;
}

@end

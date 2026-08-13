#import "ARIEditManager.h"
#import "ARITweakManager.h"

#include <objc/runtime.h>

static UIViewController *ARIVisibleViewController(UIViewController *controller) {
    UIViewController *current = controller;
    while(current) {
        UIViewController *next = nil;
        if(current.presentedViewController && !current.presentedViewController.isBeingDismissed) {
            next = current.presentedViewController;
        } else if([current isKindOfClass:[UINavigationController class]]) {
            next = ((UINavigationController *)current).visibleViewController;
        } else if([current isKindOfClass:[UITabBarController class]]) {
            next = ((UITabBarController *)current).selectedViewController;
        }

        if(!next || next == current) break;
        current = next;
    }
    return current;
}

static UIViewController *ARIViewControllerForView(UIView *view) {
    UIResponder *responder = view;
    while(responder) {
        if([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

static id ARIIconControllerSharedInstance(void) {
    Class controllerClass = objc_getClass("SBIconController");
    return [controllerClass respondsToSelector:@selector(sharedInstance)]
        ? [controllerClass sharedInstance]
        : nil;
}

UIViewController *ARIHomeScreenPresenter(void) {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    SBRootFolderView *rootFolderView = [manager rootFolderView];
    id iconController = ARIIconControllerSharedInstance();

    // SBIconController stopped inheriting from UIViewController on iOS 17.
    // Preserve the original presenter on iOS 15 and 16, then resolve the
    // controller that actually owns the root-folder view on newer versions.
    UIViewController *controller = [iconController isKindOfClass:[UIViewController class]]
        ? (UIViewController *)iconController
        : nil;
    if(!controller) controller = ARIViewControllerForView(rootFolderView);
    if(!controller) {
        if([iconController respondsToSelector:@selector(_rootFolderController)]) {
            id rootFolderController = [iconController _rootFolderController];
            if([rootFolderController isKindOfClass:[UIViewController class]]) {
                controller = rootFolderController;
            }
        }
    }

    if(!controller) {
        UIApplication *application = [UIApplication sharedApplication];
        UIWindow *fallbackWindow = nil;
        for(UIWindow *window in application.windows) {
            if(rootFolderView.window == window) {
                fallbackWindow = window;
                break;
            }
            if(!fallbackWindow && window.isKeyWindow) fallbackWindow = window;
        }
        controller = fallbackWindow.rootViewController ?: application.windows.firstObject.rootViewController;
    }

    return ARIVisibleViewController(controller);
}

static UIView *ARIHomeScreenEditorHostView(void) {
    id iconController = ARIIconControllerSharedInstance();
    if([iconController isKindOfClass:[UIViewController class]]) {
        UIView *legacyView = ((UIViewController *)iconController).view;
        if(legacyView.window) return legacyView;
    }

    SBRootFolderView *rootFolderView = [[ARITweakManager sharedInstance] rootFolderView];
    if(rootFolderView.window) return rootFolderView;

    UIViewController *presenter = ARIHomeScreenPresenter();
    return presenter.view.window ? presenter.view : nil;
}

@implementation ARIEditManager {
    BOOL _isEditing;
    BOOL _queueDockLayout;
    BOOL _singleList;
    NSString *_editingLocation;
    __weak SBIconListView *_current;
    __weak SBIconListView *_pendingListView;
    __weak UIAlertController *_editAlertController;
}

@synthesize isEditing = _isEditing;
@synthesize singleListMode = _singleList;
@synthesize editingLocation = _editingLocation;

+ (instancetype)sharedInstance {
    static dispatch_once_t token;
    static ARIEditManager *manager;
    dispatch_once(&token, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

// Edit helper

- (void)toggleEditView:(BOOL)toggle withTargetLocation:(NSString *)targetLoc {
    if(toggle) {
        // Start edit
        SBIconListView *requestedListView = _pendingListView;
        _pendingListView = nil;
        if(_isEditing) return;
        _isEditing = YES;
        _editingLocation = targetLoc;

        // Check if this list view has custom config
        _current = requestedListView ?: [[ARITweakManager sharedInstance] currentListView];
        // No per page layout for the following
        if(![targetLoc isEqualToString:@"dock"] && ![targetLoc isEqualToString:@"pagedot"]) {
            _singleList = _current && [[ARITweakManager sharedInstance] doesCustomConfigForListViewExist:_current];
        } else {
            _singleList = NO;
        }

        ARIEditingMainView *view = [[ARIEditingMainView alloc] initWithTarget:targetLoc];
        view.alpha = 0.0F;
        view.transform = CGAffineTransformMakeScale(0.25F, 0.25F);
        UIView *hostView = ARIHomeScreenEditorHostView();
        if(!hostView) {
            _isEditing = NO;
            _editingLocation = nil;
            _current = nil;
            _singleList = NO;
            return;
        }
        [hostView addSubview:view];
        [NSLayoutConstraint activateConstraints:@[
            [view.centerXAnchor constraintEqualToAnchor:hostView.centerXAnchor],
        ]];

        [UIView animateWithDuration:0.2f
            delay:0.25f
            options:UIViewAnimationOptionCurveEaseOut
            animations:^{
                view.alpha = 1.0F;
                view.transform = CGAffineTransformMakeScale(1.0F, 1.0F);
            }
            completion:^(__unused BOOL finished) {
                // A context-menu dismissal or SpringBoard's edit-mode
                // transition can interrupt this purely visual animation on
                // older releases.  The upstream editor did not make opening
                // its controls conditional on the animation's `finished`
                // value, so only validate that this is still the live editor.
                if(self->_isEditing && self.editView == view) {
                    [view showInitialOptionsIfNeeded];
                }
            }];
        self.editView = view;
    } else {
        // End edit
        _pendingListView = nil;
        UIAlertController *alert = _editAlertController;
        if((alert.presentingViewController || alert.view.window) && !alert.isBeingDismissed) {
            [alert dismissViewControllerAnimated:NO completion:nil];
        }
        _editAlertController = nil;
        if(!_isEditing) {
            _current = nil;
            _singleList = NO;
            return;
        }
        _isEditing = NO;
        _editingLocation = nil;

        // Finish layout
        if(_queueDockLayout) {
            [[ARITweakManager sharedInstance] relayoutEntireIconModel];
            _queueDockLayout = NO;
        }

        ARIEditingMainView *viewToRemove = self.editView;
        [viewToRemove.currentControls endTextEntry];
        _current = nil;
        _singleList = NO;
        [UIView animateWithDuration:0.15f
            delay:0.0f
            options:UIViewAnimationOptionCurveEaseIn
            animations:^{
                viewToRemove.alpha = 0.0F;
                viewToRemove.transform = CGAffineTransformMakeScale(0.2F, 0.2F);
            }
            completion:^(BOOL finished) {
                [viewToRemove removeFromSuperview];
                if(self.editView == viewToRemove) self.editView = nil;
            }];
    }
}

- (void)setDockLayoutQueued {
    _queueDockLayout = YES;
}

- (void)presentEditAlertForListView:(SBIconListView *)listView {
    if(_editAlertController.presentingViewController || _editAlertController.view.window) return;
    _editAlertController = nil;
    _pendingListView = listView;
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Atria"
                                                                   message:@"무엇을 수정할까요?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    _editAlertController = alert;

    [alert addAction:[self _createEditAlertAction:@"홈화면" editLocation:@"hs"]];
    [alert addAction:[self _createEditAlertAction:@"독" editLocation:@"dock"]];
    [alert addAction:[self _createEditAlertAction:@"페이지 레이블" editLocation:@"label"]];
    [alert addAction:[self _createEditAlertAction:@"페이지 인디케이터" editLocation:@"pagedot"]];
    if([manager boolValueForKey:@"showBackground"]) {
        [alert addAction:[self _createEditAlertAction:@"배경 블러" editLocation:@"blur"]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"취소"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action){
                                                self->_pendingListView = nil;
                                                self->_editAlertController = nil;
                                            }]];

    UIViewController *presenter = ARIHomeScreenPresenter();
    if(!presenter || presenter.isBeingDismissed) {
        _pendingListView = nil;
        _editAlertController = nil;
        return;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (UIAlertAction *)_createEditAlertAction:(NSString *)title editLocation:(NSString *)location {
    return [UIAlertAction actionWithTitle:title
                                    style:UIAlertActionStyleDefault
                                  handler:^(UIAlertAction *action) {
                                      [self toggleEditView:YES
                                          withTargetLocation:location];
                                  }];
}

- (void)toggleSingleListMode {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    if(!_singleList) {
        NSArray<SBIconListView *> *rootListViews = [manager allRootListViews];
        SBIconListView *candidate = (_current && [rootListViews containsObject:_current])
            ? _current
            : [manager currentListView];
        if(!candidate || ![rootListViews containsObject:candidate]) return;
        _current = candidate;
        _singleList = YES;
        if(![manager doesCustomConfigForListViewExist:_current]) {
            // Freeze config for the page
            [manager createCustomForListView:_current];
        }
        return;
    }

    SBIconListView *liveListView = [self currentIconListViewIfSinglePage];
    if(!liveListView) return;
    [manager deleteCustomForListView:liveListView];
    _singleList = NO;
    _current = nil;
}

- (SBIconListView *)currentIconListViewIfSinglePage {
    if(!_singleList) return nil;
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    NSArray<SBIconListView *> *rootListViews = [manager allRootListViews];
    if(!_current || ![rootListViews containsObject:_current]) {
        // SpringBoard recreates list views during rotation/page rebuilding.
        // Rebind to the live page, but keep single-page mode active if the
        // replacement is not ready yet so callers can block rather than
        // accidentally treating nil as a request to edit global settings.
        SBIconListView *candidate = [manager currentListView];
        if(!candidate || ![rootListViews containsObject:candidate]) return nil;
        _current = candidate;
    }
    return _current;
}

@end

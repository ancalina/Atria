//
// Shared constants used by tweak and prefs.
//

#import <UIKit/UIKit.h>

#define kARIPrefTintColor [UIColor colorWithRed:0.32 green:0.03 blue:0.49 alpha:1.00]
static NSString *const ARIPreferenceDomain = @"me.lau.AtriaPrefs";

// PreferenceLoader asks SpringBoard to perform Dock mutations in-process.
// Every request and completion uses its own top-level defaults key so separate
// PreferenceLoader processes never perform a shared-dictionary read/modify/write.
// The scalar fields remain for an in-place mixed-version upgrade.
static NSString *const ARIDockResetRequestNotification = @"me.lau.Atria/ResetDockArrangement";
static NSString *const ARIDockResetCompletionNotification = @"me.lau.Atria/DockArrangementResetCompleted";
static NSString *const ARIDockResetRequestKeyPrefix = @"_dockResetRequest.";
static NSString *const ARIDockResetCompletionKeyPrefix = @"_dockResetCompletion.";
static NSString *const ARIDockResetRequestTimestampField = @"timestamp";
static NSString *const ARIDockResetRequestDeadlineField = @"deadline";
static NSString *const ARIDockResetCompletionTimestampField = @"timestamp";
static NSString *const ARIDockResetCompletionRequestTimestampField = @"requestTimestamp";
static NSString *const ARIDockResetCompletionLegacyScalarField = @"legacyScalar";
static NSString *const ARIDockResetCompletionRequestIDField = @"requestID";
static NSString *const ARIDockResetCompletionResultField = @"result";
static NSString *const ARIDockResetCompletionMovedCountField = @"movedCount";
static NSString *const ARIDockResetCompletedIDKey = @"_dockResetCompletedID";
static NSString *const ARIDockResetResultKey = @"_dockResetResult";
static NSString *const ARIDockResetMovedCountKey = @"_dockResetMovedCount";
static NSString *const ARIDockResetDeadlineKey = @"_dockResetDeadline";
static NSString *const ARIDockResetRequestIDKey = @"_dockResetRequestID";

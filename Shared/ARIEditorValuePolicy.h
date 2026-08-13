#import <Foundation/Foundation.h>

// Returns the semantic storage/runtime bounds for a numeric home-screen
// editor setting. These bounds are intentionally wider than its UISlider and
// are shared by SpringBoard and the preferences import/export path.
FOUNDATION_EXPORT BOOL ARIEditorValuePolicyForKey(NSString *key,
                                                  double *lowerLimit,
                                                  double *upperLimit,
                                                  BOOL *integralValue);

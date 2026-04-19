//
// Visual editor for label scripts.
//

#import <UIKit/UIKit.h>

@interface ARILabelScriptVisualEditorController : UITableViewController
- (instancetype)initRootControllerWithScript:(NSMutableDictionary *)script;
- (instancetype)initWithSteps:(NSMutableArray *)steps title:(NSString *)title;
@end

//
// Visual editor for label scripts.
//

#import <UIKit/UIKit.h>

@interface ARILabelScriptVisualEditorController : UITableViewController
@property (nonatomic, copy) void (^dismissalHandler)(void);
- (instancetype)initRootControllerWithScript:(NSMutableDictionary *)script;
- (instancetype)initWithSteps:(NSMutableArray *)steps title:(NSString *)title;
@end

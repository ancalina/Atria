//
// Label script runtime.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARILabelScriptRunner : NSObject
@property (nonatomic, readonly, getter=isValid) BOOL valid;
@property (nonatomic, readonly, getter=hasStarted) BOOL started;
@property (nonatomic, copy, readonly) NSString *currentTextTemplate;
@property (nonatomic, copy, readonly) NSString *lastError;
@property (nonatomic, copy) NSDictionary<NSString *, id> *context;
- (BOOL)loadSource:(NSString *)source;
- (void)reset;
- (NSTimeInterval)advance;
@end

NS_ASSUME_NONNULL_END

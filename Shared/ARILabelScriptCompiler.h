//
// Shared label script parser/validator.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ARILabelScriptErrorDomain;

// The same limits are enforced by the preferences editor and SpringBoard runtime.
// Keep them public so an importer does not have to duplicate policy.
FOUNDATION_EXPORT NSUInteger const ARILabelScriptMaximumSourceBytes;
FOUNDATION_EXPORT NSUInteger const ARILabelScriptMaximumBlocks;
FOUNDATION_EXPORT NSUInteger const ARILabelScriptMaximumConditions;
FOUNDATION_EXPORT NSUInteger const ARILabelScriptMaximumNestingDepth;
FOUNDATION_EXPORT NSUInteger const ARILabelScriptMaximumStepsPerContainer;
FOUNDATION_EXPORT NSUInteger const ARILabelScriptMaximumTextLength;
FOUNDATION_EXPORT NSUInteger const ARILabelScriptMaximumQueryLength;
FOUNDATION_EXPORT NSTimeInterval const ARILabelScriptMaximumWaitSeconds;
FOUNDATION_EXPORT NSInteger const ARILabelScriptMaximumRepeatCount;

@interface ARILabelScriptCompiler : NSObject
+ (nullable NSDictionary *)scriptDictionaryFromSource:(NSString *)source error:(NSError **)error;
+ (nullable NSMutableDictionary *)mutableScriptDictionaryFromSource:(NSString *)source error:(NSError **)error;
+ (BOOL)validateScriptDictionary:(NSDictionary *)script error:(NSError **)error;
+ (NSArray<NSString *> *)diagnosticsForScriptDictionary:(NSDictionary *)script;
+ (nullable NSString *)sourceFromScriptDictionary:(NSDictionary *)script error:(NSError **)error;
+ (NSString *)defaultScriptSource;
@end

NS_ASSUME_NONNULL_END

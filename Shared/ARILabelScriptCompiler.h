//
// Shared label script parser/validator.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ARILabelScriptErrorDomain;

@interface ARILabelScriptCompiler : NSObject
+ (nullable NSDictionary *)scriptDictionaryFromSource:(NSString *)source error:(NSError **)error;
+ (nullable NSMutableDictionary *)mutableScriptDictionaryFromSource:(NSString *)source error:(NSError **)error;
+ (BOOL)validateScriptDictionary:(NSDictionary *)script error:(NSError **)error;
+ (nullable NSString *)sourceFromScriptDictionary:(NSDictionary *)script error:(NSError **)error;
+ (NSString *)defaultScriptSource;
@end

NS_ASSUME_NONNULL_END

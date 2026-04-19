//
// Shared storage helpers for custom greeting token schedules.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ARICustomGreetingScheduleErrorDomain;
extern NSString *const ARICustomGreetingTokensPreferenceKey;

@interface ARICustomGreetingScheduleStore : NSObject
+ (NSArray<NSDictionary *> *)tokenDictionariesFromSource:(NSString *)source error:(NSError **)error;
+ (NSArray<NSMutableDictionary *> *)mutableTokenDictionariesFromSource:(NSString *)source error:(NSError **)error;
+ (NSString *)sourceFromTokenDictionaries:(NSArray<NSDictionary *> *)tokens error:(NSError **)error;
+ (NSArray<NSDictionary *> *)effectiveTokensFromPreferences:(NSUserDefaults *)preferences;
+ (NSArray<NSMutableDictionary *> *)editableTokensFromPreferences:(NSUserDefaults *)preferences;
+ (NSString *)newTokenIdentifier;
+ (NSString *)tokenNameForDictionary:(NSDictionary *)token fallback:(NSString *)fallback;
+ (NSString *)formattedTimeValue:(double)value;
+ (NSString *)displayTextForEntry:(NSDictionary *)entry;
@end

NS_ASSUME_NONNULL_END

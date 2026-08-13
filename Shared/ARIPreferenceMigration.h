#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *ARINormalizedPreferenceBaseKey(NSString *key);
FOUNDATION_EXPORT NSString *ARINormalizedPreferenceKey(NSString *key);
FOUNDATION_EXPORT NSString *ARINormalizedPagePrefix(NSString *value);
FOUNDATION_EXPORT BOOL ARIParsePagePreferenceKey(NSString *key,
                                                 NSString **prefix,
                                                 NSString **baseKey);

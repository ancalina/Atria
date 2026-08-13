#import "ARIPreferenceMigration.h"

static BOOL ARIParsePageKeyWithMarker(NSString *key,
                                     NSString *marker,
                                     NSString **prefix,
                                     NSString **baseKey) {
    if(![key isKindOfClass:[NSString class]] || ![key hasPrefix:marker]) return NO;

    NSUInteger cursor = marker.length;
    NSUInteger digitStart = cursor;
    NSUInteger pageNumber = 0;
    while(cursor < key.length) {
        unichar character = [key characterAtIndex:cursor];
        if(character < '0' || character > '9') break;
        NSUInteger digit = (NSUInteger)(character - '0');
        if(pageNumber > (NSUIntegerMax - digit) / 10) return NO;
        pageNumber = pageNumber * 10 + digit;
        cursor++;
    }
    if(cursor == digitStart || cursor >= key.length || [key characterAtIndex:cursor] != '_') {
        return NO;
    }

    if(prefix) *prefix = [NSString stringWithFormat:@"Page%lu_", (unsigned long)pageNumber];
    if(baseKey) *baseKey = [key substringFromIndex:cursor + 1];
    return YES;
}

BOOL ARIParsePagePreferenceKey(NSString *key, NSString **prefix, NSString **baseKey) {
    if(ARIParsePageKeyWithMarker(key, @"Page", prefix, baseKey)) return YES;
    return ARIParsePageKeyWithMarker(key, @"_", prefix, baseKey);
}

NSString *ARINormalizedPagePrefix(NSString *value) {
    NSString *prefix = nil;
    NSString *baseKey = nil;
    if(!ARIParsePagePreferenceKey(value, &prefix, &baseKey) || baseKey.length != 0) return nil;
    return prefix;
}

NSString *ARINormalizedPreferenceBaseKey(NSString *key) {
    if(![key isKindOfClass:[NSString class]] || key.length == 0) return key;

    static NSDictionary<NSString *, NSString *> *renames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        renames = @{
            @"welcomeText": @"labelText",
            @"welcomeTextColor": @"labelTextColor",
            @"background_bg": @"blur_alpha",
            @"background_corner_radius": @"blur_corner_radius",
            @"background_intensity": @"blur_intensity",
        };
    });

    NSString *renamed = renames[key];
    if(renamed) return renamed;
    if([key hasPrefix:@"welcome_"]) {
        return [@"label_" stringByAppendingString:[key substringFromIndex:8]];
    }
    if([key hasPrefix:@"background_inset_"]) {
        return [@"blur_inset_" stringByAppendingString:[key substringFromIndex:17]];
    }
    return key;
}

NSString *ARINormalizedPreferenceKey(NSString *key) {
    if(![key isKindOfClass:[NSString class]] || key.length == 0) return key;
    NSString *prefix = nil;
    NSString *baseKey = nil;
    if(ARIParsePagePreferenceKey(key, &prefix, &baseKey) && baseKey.length > 0) {
        return [prefix stringByAppendingString:ARINormalizedPreferenceBaseKey(baseKey)];
    }
    return ARINormalizedPreferenceBaseKey(key);
}

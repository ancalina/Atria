//
// Shared storage helpers for custom greeting token schedules.
//

#include <math.h>

#import "ARICustomGreetingScheduleStore.h"

NSString *const ARICustomGreetingScheduleErrorDomain = @"me.lau.Atria.CustomGreetingSchedule";
NSString *const ARICustomGreetingTokensPreferenceKey = @"customGreetingTokensSource";

@implementation ARICustomGreetingScheduleStore

+ (NSError *)_errorWithDescription:(NSString *)description {
    return [NSError errorWithDomain:ARICustomGreetingScheduleErrorDomain
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: description ?: @"알 수 없는 오류" }];
}

+ (NSString *)_trimmedStringValue:(id)value fallback:(NSString *)fallback {
    NSString *string = [value isKindOfClass:[NSString class]] ? value : fallback;
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (BOOL)_validateEntry:(NSDictionary *)entry error:(NSError **)error {
    if(![entry isKindOfClass:[NSDictionary class]]) {
        if(error) *error = [self _errorWithDescription:@"Schedule entries must be dictionaries."];
        return NO;
    }

    id startValue = entry[@"start"];
    if(![startValue respondsToSelector:@selector(doubleValue)]) {
        if(error) *error = [self _errorWithDescription:@"Each entry must contain a numeric `start` value."];
        return NO;
    }

    double start = [startValue doubleValue];
    if(start < 0.0 || start > 24.0) {
        if(error) *error = [self _errorWithDescription:@"Entry start values must be between 0 and 24."];
        return NO;
    }

    id textValue = entry[@"text"];
    if(textValue && ![textValue isKindOfClass:[NSString class]]) {
        if(error) *error = [self _errorWithDescription:@"Each entry text must be a string."];
        return NO;
    }

    return YES;
}

+ (NSArray<NSDictionary *> *)_normalizedEntries:(NSArray<NSDictionary *> *)entries {
    NSMutableArray<NSDictionary *> *normalized = [NSMutableArray array];
    for(NSDictionary *entry in entries) {
        double start = [entry[@"start"] respondsToSelector:@selector(doubleValue)] ? [entry[@"start"] doubleValue] : 0.0;
        NSString *text = [entry[@"text"] isKindOfClass:[NSString class]] ? entry[@"text"] : @"";
        [normalized addObject:@{
            @"start": @(MIN(24.0, MAX(0.0, start))),
            @"text": text
        }];
    }

    [normalized sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        double leftValue = [left[@"start"] doubleValue];
        double rightValue = [right[@"start"] doubleValue];
        if(leftValue < rightValue) return NSOrderedAscending;
        if(leftValue > rightValue) return NSOrderedDescending;
        return [left[@"text"] compare:right[@"text"]];
    }];

    return normalized;
}

+ (NSString *)_normalizedIdentifier:(id)value fallback:(NSString *)fallback usedIdentifiers:(NSMutableSet<NSString *> *)usedIdentifiers {
    NSString *identifier = [self _trimmedStringValue:value fallback:fallback];
    if(identifier.length == 0) {
        identifier = fallback.length > 0 ? fallback : [self newTokenIdentifier];
    }

    NSString *uniqueIdentifier = identifier;
    NSUInteger suffix = 2;
    while([usedIdentifiers containsObject:uniqueIdentifier]) {
        uniqueIdentifier = [NSString stringWithFormat:@"%@-%lu", identifier, (unsigned long)suffix];
        suffix++;
    }

    [usedIdentifiers addObject:uniqueIdentifier];
    return uniqueIdentifier;
}

+ (BOOL)_validateToken:(NSDictionary *)token error:(NSError **)error {
    if(![token isKindOfClass:[NSDictionary class]]) {
        if(error) *error = [self _errorWithDescription:@"Tokens must be dictionaries."];
        return NO;
    }

    id nameValue = token[@"name"];
    if(nameValue && ![nameValue isKindOfClass:[NSString class]]) {
        if(error) *error = [self _errorWithDescription:@"Token names must be strings."];
        return NO;
    }

    id entriesValue = token[@"entries"];
    if(entriesValue && ![entriesValue isKindOfClass:[NSArray class]]) {
        if(error) *error = [self _errorWithDescription:@"Token entries must be arrays."];
        return NO;
    }

    for(NSDictionary *entry in (NSArray *)entriesValue ?: @[]) {
        if(![self _validateEntry:entry error:error]) {
            return NO;
        }
    }

    return YES;
}

+ (NSDictionary *)_normalizedToken:(NSDictionary *)token fallbackIdentifier:(NSString *)fallbackIdentifier usedIdentifiers:(NSMutableSet<NSString *> *)usedIdentifiers {
    NSString *identifier = [self _normalizedIdentifier:token[@"id"] fallback:fallbackIdentifier usedIdentifiers:usedIdentifiers];
    NSString *name = [token[@"name"] isKindOfClass:[NSString class]] ? token[@"name"] : @"";
    NSArray *entries = [token[@"entries"] isKindOfClass:[NSArray class]] ? token[@"entries"] : @[];

    return @{
        @"id": identifier,
        @"name": name,
        @"entries": [self _normalizedEntries:entries]
    };
}

+ (NSArray<NSDictionary *> *)tokenDictionariesFromSource:(NSString *)source error:(NSError **)error {
    NSString *trimmed = [source isKindOfClass:[NSString class]] ? [source stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
    if(trimmed.length == 0) {
        return @[];
    }

    NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    if(!data) {
        if(error) *error = [self _errorWithDescription:@"Failed to encode token source as UTF-8."];
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];
    if(![object isKindOfClass:[NSArray class]]) {
        if(error && !*error) *error = [self _errorWithDescription:@"Token source must be a JSON array."];
        return nil;
    }

    NSMutableArray<NSDictionary *> *normalizedTokens = [NSMutableArray array];
    NSMutableSet<NSString *> *usedIdentifiers = [NSMutableSet set];
    NSUInteger index = 0;
    for(NSDictionary *token in (NSArray *)object) {
        if(![self _validateToken:token error:error]) {
            return nil;
        }

        NSString *fallbackIdentifier = [NSString stringWithFormat:@"token-%lu", (unsigned long)(index + 1)];
        [normalizedTokens addObject:[self _normalizedToken:token fallbackIdentifier:fallbackIdentifier usedIdentifiers:usedIdentifiers]];
        index++;
    }

    return normalizedTokens;
}

+ (NSArray<NSMutableDictionary *> *)mutableTokenDictionariesFromSource:(NSString *)source error:(NSError **)error {
    NSArray<NSDictionary *> *tokens = [self tokenDictionariesFromSource:source error:error];
    if(!tokens) {
        return nil;
    }

    NSMutableArray<NSMutableDictionary *> *mutableTokens = [NSMutableArray arrayWithCapacity:tokens.count];
    for(NSDictionary *token in tokens) {
        NSMutableArray<NSMutableDictionary *> *mutableEntries = [NSMutableArray array];
        for(NSDictionary *entry in token[@"entries"]) {
            [mutableEntries addObject:[entry mutableCopy]];
        }

        [mutableTokens addObject:[@{
            @"id": token[@"id"] ?: [self newTokenIdentifier],
            @"name": token[@"name"] ?: @"",
            @"entries": mutableEntries
        } mutableCopy]];
    }

    return mutableTokens;
}

+ (NSString *)sourceFromTokenDictionaries:(NSArray<NSDictionary *> *)tokens error:(NSError **)error {
    NSMutableArray<NSDictionary *> *normalizedTokens = [NSMutableArray arrayWithCapacity:tokens.count];
    NSMutableSet<NSString *> *usedIdentifiers = [NSMutableSet set];
    NSUInteger index = 0;

    for(NSDictionary *token in tokens) {
        if(![self _validateToken:token error:error]) {
            return nil;
        }

        NSString *fallbackIdentifier = [NSString stringWithFormat:@"token-%lu", (unsigned long)(index + 1)];
        [normalizedTokens addObject:[self _normalizedToken:token fallbackIdentifier:fallbackIdentifier usedIdentifiers:usedIdentifiers]];
        index++;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:normalizedTokens options:NSJSONWritingPrettyPrinted error:error];
    if(!data) {
        return nil;
    }

    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (NSArray<NSDictionary *> *)_legacyEntriesForTokenSlot:(NSInteger)slot preferences:(NSUserDefaults *)preferences {
    id morningStartValue = [preferences objectForKey:@"customGreetingMorningStartHour"];
    id afternoonStartValue = [preferences objectForKey:@"customGreetingAfternoonStartHour"];
    id eveningStartValue = [preferences objectForKey:@"customGreetingEveningStartHour"];
    NSInteger morningStart = [morningStartValue respondsToSelector:@selector(integerValue)] ? [morningStartValue integerValue] : 4;
    NSInteger afternoonStart = [afternoonStartValue respondsToSelector:@selector(integerValue)] ? [afternoonStartValue integerValue] : 12;
    NSInteger eveningStart = [eveningStartValue respondsToSelector:@selector(integerValue)] ? [eveningStartValue integerValue] : 18;
    if(!(morningStart < afternoonStart && afternoonStart < eveningStart)) {
        morningStart = 4;
        afternoonStart = 12;
        eveningStart = 18;
    }

    NSString *prefix = [NSString stringWithFormat:@"customGreetingToken%ld", (long)slot];
    id morningTextValue = [preferences objectForKey:[prefix stringByAppendingString:@"MorningText"]];
    id afternoonTextValue = [preferences objectForKey:[prefix stringByAppendingString:@"AfternoonText"]];
    id eveningTextValue = [preferences objectForKey:[prefix stringByAppendingString:@"EveningText"]];
    NSString *morningText = [morningTextValue isKindOfClass:[NSString class]] ? morningTextValue : @"";
    NSString *afternoonText = [afternoonTextValue isKindOfClass:[NSString class]] ? afternoonTextValue : @"";
    NSString *eveningText = [eveningTextValue isKindOfClass:[NSString class]] ? eveningTextValue : @"";

    BOOL hasLegacyText = morningText.length > 0 || afternoonText.length > 0 || eveningText.length > 0;
    if(!hasLegacyText) {
        return @[];
    }

    return [self _normalizedEntries:@[
        @{ @"start": @(morningStart), @"text": morningText ?: @"" },
        @{ @"start": @(afternoonStart), @"text": afternoonText ?: @"" },
        @{ @"start": @(eveningStart), @"text": eveningText ?: @"" }
    ]];
}

+ (NSArray<NSDictionary *> *)_legacyTokensFromPreferences:(NSUserDefaults *)preferences {
    NSMutableArray<NSDictionary *> *tokens = [NSMutableArray array];
    NSMutableSet<NSString *> *usedIdentifiers = [NSMutableSet set];

    for(NSInteger slot = 1; slot <= 3; slot++) {
        NSString *nameKey = [NSString stringWithFormat:@"customGreetingToken%ldName", (long)slot];
        id tokenNameValue = [preferences objectForKey:nameKey];
        NSString *tokenName = [tokenNameValue isKindOfClass:[NSString class]] ? tokenNameValue : @"";
        NSArray<NSDictionary *> *entries = [self _legacyEntriesForTokenSlot:slot preferences:preferences];
        if(tokenName.length == 0 && entries.count == 0) {
            continue;
        }

        [tokens addObject:[self _normalizedToken:@{
            @"id": [NSString stringWithFormat:@"legacy-%ld", (long)slot],
            @"name": tokenName ?: @"",
            @"entries": entries ?: @[]
        } fallbackIdentifier:[NSString stringWithFormat:@"legacy-%ld", (long)slot] usedIdentifiers:usedIdentifiers]];
    }

    return tokens;
}

+ (NSArray<NSDictionary *> *)effectiveTokensFromPreferences:(NSUserDefaults *)preferences {
    id storedSource = [preferences objectForKey:ARICustomGreetingTokensPreferenceKey];
    NSString *source = [storedSource isKindOfClass:[NSString class]] ? storedSource : @"";
    NSString *trimmedSource = [source stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(trimmedSource.length > 0) {
        NSArray<NSDictionary *> *tokens = [self tokenDictionariesFromSource:source error:nil];
        if(tokens) return tokens;
    }

    return [self _legacyTokensFromPreferences:preferences];
}

+ (NSArray<NSMutableDictionary *> *)editableTokensFromPreferences:(NSUserDefaults *)preferences {
    id storedSource = [preferences objectForKey:ARICustomGreetingTokensPreferenceKey];
    NSString *source = [storedSource isKindOfClass:[NSString class]] ? storedSource : @"";
    NSString *trimmedSource = [source stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(trimmedSource.length > 0) {
        NSArray<NSMutableDictionary *> *tokens = [self mutableTokenDictionariesFromSource:source error:nil];
        if(tokens) return tokens;
    }

    NSMutableArray<NSMutableDictionary *> *mutableTokens = [NSMutableArray array];
    for(NSDictionary *token in [self _legacyTokensFromPreferences:preferences]) {
        NSMutableArray<NSMutableDictionary *> *mutableEntries = [NSMutableArray array];
        for(NSDictionary *entry in token[@"entries"]) {
            [mutableEntries addObject:[entry mutableCopy]];
        }

        [mutableTokens addObject:[@{
            @"id": token[@"id"] ?: [self newTokenIdentifier],
            @"name": token[@"name"] ?: @"",
            @"entries": mutableEntries
        } mutableCopy]];
    }

    return mutableTokens;
}

+ (NSString *)newTokenIdentifier {
    return [[[NSUUID UUID] UUIDString] lowercaseString];
}

+ (NSString *)tokenNameForDictionary:(NSDictionary *)token fallback:(NSString *)fallback {
    NSString *name = [token[@"name"] isKindOfClass:[NSString class]] ? token[@"name"] : @"";
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return name.length > 0 ? name : fallback;
}

+ (NSString *)formattedTimeValue:(double)value {
    NSInteger totalMinutes = (NSInteger)llround(value * 60.0);
    if(totalMinutes < 0) totalMinutes = 0;
    if(totalMinutes > 24 * 60) totalMinutes = 24 * 60;

    NSInteger hours = totalMinutes / 60;
    NSInteger minutes = totalMinutes % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)hours, (long)minutes];
}

@end

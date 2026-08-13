//
// Created by ren7995 on 2023-01-05 14:55:49
// Copyright (c) 2023 ren7995. All rights reserved.
//

#import "ARIDynamicView.h"

// https://stackoverflow.com/questions/1560081/how-can-i-create-a-uicolor-from-a-hex-string
#define UIColorFromHexValue(r, a) [UIColor               \
    colorWithRed:((float)((r & 0xFF0000) >> 16)) / 255.0 \
           green:((float)((r & 0xFF00) >> 8)) / 255.0    \
            blue:((float)(r & 0xFF)) / 255.0             \
           alpha:a]

@implementation ARIDynamicView

- (instancetype)init {
    self = [super init];
    if(self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (void)updateView {
}

- (void)updateAnchors {
}

+ (UIColor *)colorFromHexString:(NSString *)str withAlpha:(CGFloat)alpha {
    if(![str isKindOfClass:[NSString class]]) return UIColorFromHexValue(0xFFFFFF, alpha);
    NSString *hex = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    else if([hex hasPrefix:@"0x"] || [hex hasPrefix:@"0X"]) hex = [hex substringFromIndex:2];
    if(hex.length != 6) return UIColorFromHexValue(0xFFFFFF, alpha);

    NSScanner *scanner = [NSScanner scannerWithString:hex];
    unsigned int hexCode = 0xFFFFFF;
    if(![scanner scanHexInt:&hexCode] || !scanner.isAtEnd) {
        return UIColorFromHexValue(0xFFFFFF, alpha);
    }
    return UIColorFromHexValue(hexCode, alpha);
}

@end

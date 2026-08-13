#import "ARIEditorValuePolicy.h"
#import "ARIPreferenceMigration.h"

BOOL ARIEditorValuePolicyForKey(NSString *key,
                                double *lowerLimit,
                                double *upperLimit,
                                BOOL *integralValue) {
    if(![key isKindOfClass:[NSString class]] || key.length == 0) return NO;

    NSString *baseKey = nil;
    if(!ARIParsePagePreferenceKey(key, nil, &baseKey) || baseKey.length == 0)
        baseKey = key;
    baseKey = ARINormalizedPreferenceBaseKey(baseKey);

    static NSSet<NSString *> *gridLayoutKeys;
    static NSSet<NSString *> *geometryKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gridLayoutKeys = [NSSet setWithArray:@[
            @"hs_rows", @"hs_columns", @"dock_rows", @"dock_columns",
            @"hs_iconScale", @"hs_widgetIconScale", @"dock_iconScale"
        ]];
        geometryKeys = [NSSet setWithArray:@[
            @"hs_spacing_x", @"hs_spacing_y",
            @"hs_inset_top", @"hs_inset_left", @"hs_inset_bottom", @"hs_inset_right",
            @"hs_offset_top", @"hs_offset_left",
            @"hs_widgetXOffset", @"hs_widgetYOffset",
            @"dock_spacing_x", @"dock_spacing_y",
            @"dock_inset_top", @"dock_inset_left", @"dock_inset_bottom", @"dock_inset_right",
            @"label_inset_left", @"label_inset_top",
            @"blur_inset_top", @"blur_inset_left", @"blur_inset_bottom", @"blur_inset_right",
            @"pagedot_offsetX", @"pagedot_offsetY"
        ]];
    });

    // Rows/columns are detected by meaning inside the supported editor schema,
    // rather than by a separate UI flag. Restricting the schema prevents an
    // unrelated or future imported key from being silently coerced.
    BOOL isGridLayoutKey = [gridLayoutKeys containsObject:baseKey];
    BOOL integral = isGridLayoutKey &&
                    ([baseKey hasSuffix:@"_rows"] ||
                     [baseKey hasSuffix:@"_columns"]);
    double lower = 0.0;
    double upper = 0.0;

    if(integral) {
        // 64x64 already permits 4096 cells. Larger grids can freeze older
        // SpringBoard releases and exceed any practical home-screen layout.
        lower = 1.0;
        upper = 64.0;
    } else if(isGridLayoutKey &&
              ([baseKey hasSuffix:@"iconScale"] ||
               [baseKey hasSuffix:@"IconScale"])) {
        lower = 0.01;
        upper = 16.0;
    } else if([baseKey isEqualToString:@"dock_bg"] ||
              [baseKey isEqualToString:@"blur_alpha"] ||
              [baseKey isEqualToString:@"blur_intensity"]) {
        lower = 0.0;
        upper = 1.0;
    } else if([baseKey isEqualToString:@"label_textSize"]) {
        lower = 1.0;
        upper = 512.0;
    } else if([baseKey isEqualToString:@"blur_corner_radius"]) {
        lower = 0.0;
        upper = 2048.0;
    } else if([geometryKeys containsObject:baseKey]) {
        lower = -8192.0;
        upper = 8192.0;
    } else {
        return NO;
    }

    if(lowerLimit) *lowerLimit = lower;
    if(upperLimit) *upperLimit = upper;
    if(integralValue) *integralValue = integral;
    return YES;
}

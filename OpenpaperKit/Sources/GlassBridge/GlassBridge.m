#import "GlassBridge.h"

NSDictionary<NSString *, id> *OPReadBlurValues(id filter) {
    @try {
        if (![filter respondsToSelector:NSSelectorFromString(@"inputKeys")]) return nil;
        NSArray *keys = [filter valueForKey:@"inputKeys"];
        if (![keys isKindOfClass:NSArray.class] || ![keys containsObject:@"inputBlurRadius"]) return nil;
        NSMutableDictionary *values = [NSMutableDictionary dictionary];
        for (id key in keys) {
            if (![key isKindOfClass:NSString.class]) continue;
            if ([key isEqual:@"inputBlurRadius"] || [key hasPrefix:@"inputBlurOpacity"]) {
                id value = [filter valueForKey:key];
                if (value && ![value isKindOfClass:NSNumber.class]) return nil;
                values[key] = value ?: NSNull.null;
            }
        }
        return values.count > 1 ? values : nil;
    } @catch (NSException *exception) { return nil; }
}

BOOL OPWriteBlurValues(id filter, NSDictionary<NSString *, id> *values) {
    NSDictionary *before = OPReadBlurValues(filter);
    if (!before || ![[NSSet setWithArray:before.allKeys] isEqual:[NSSet setWithArray:values.allKeys]]) return NO;
    @try {
        for (NSString *key in values) {
            if (![values[key] isKindOfClass:NSNumber.class] && values[key] != NSNull.null) return NO;
        }
        for (NSString *key in values) [filter setValue:(values[key] == NSNull.null ? nil : values[key]) forKey:key];
        return YES;
    } @catch (NSException *exception) {
        @try { for (NSString *key in before) [filter setValue:(before[key] == NSNull.null ? nil : before[key]) forKey:key]; }
        @catch (NSException *rollbackException) {}
        return NO;
    }
}

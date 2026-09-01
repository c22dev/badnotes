// BadNotes - v0.2
// A nice tweak for GoodNotes
// c22dev (Constantin Clerc)

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *randomTransactionID(void) {
    static NSString *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableString *s = [NSMutableString stringWithFormat:@"%u", (arc4random_uniform(9) + 1)];
        for (int i = 0; i < 14; i++) [s appendFormat:@"%u", arc4random_uniform(10)];
        cached = [s copy];
    });
    return cached;
}

static NSString *subscriberUID(NSString *u) {
    if (!u) return nil;
    NSRange r = [u rangeOfString:@"/v1/subscribers/"];
    if (r.location == NSNotFound) return nil;
    NSString *tail = [u substringFromIndex:r.location + r.length];
    NSRange q = [tail rangeOfString:@"?"];
    if (q.location != NSNotFound) tail = [tail substringToIndex:q.location];
    if (tail.length == 0 || [tail rangeOfString:@"/"].location != NSNotFound) return nil;
    return tail;
}

static NSData *injectEntitlements(NSData *original, NSString *uid) {
    NSString *farFuture = @"2099-12-31T23:59:59Z";
    NSString *past = @"2025-01-01T00:00:00Z";
    NSString *planKey = @"pro";
    NSString *productId = @"com.goodnotes.pro_7dt_1y_3599";
    NSString *mgmtURL = @"https://apps.apple.com/account/subscriptions";
    NSDictionary *forMyCita = @{ @"ai": @{ @"quota": @525, @"period": @"P1M" } };

    NSMutableDictionary *root = nil;
    if (original.length) {
        id parsed = [NSJSONSerialization JSONObjectWithData:original options:0 error:nil];
        if ([parsed isKindOfClass:[NSDictionary class]]) root = [parsed mutableCopy];
    }
    if (!root) root = [NSMutableDictionary dictionary];

    NSMutableDictionary *sub = [root[@"subscriber"] isKindOfClass:[NSDictionary class]] ? [root[@"subscriber"] mutableCopy] : [NSMutableDictionary dictionary];
    if (!sub[@"original_app_user_id"]) sub[@"original_app_user_id"] = uid ?: @"app_user";
    if (!sub[@"first_seen"]) sub[@"first_seen"] = past;
    if (!sub[@"non_subscriptions"]) sub[@"non_subscriptions"] = @{};
    if (!sub[@"other_purchases"]) sub[@"other_purchases"] = @{};

    NSDictionary *access = @{ @"expires_date": farFuture,
                              @"grace_period_expires_date": [NSNull null],
                              @"product_identifier": productId,
                              @"purchase_date": past,
                              @"plan_key": planKey };
    sub[@"entitlements"] = @{ @"apple_access": access, @"crossplatform_access": access };

    sub[@"current_plans"] = @{
        @"base": @{ @"product_identifier": productId,
                    @"type": @"subscription",
                    @"plan_key": planKey },
        @"ai": [NSNull null] };

    sub[@"subscriptions"] = @{ productId: @{
        @"is_sandbox": @NO,
        @"ownership_type": @"PURCHASED",
        @"expires_date": farFuture,
        @"original_purchase_date": past,
        @"period_type": @"normal",
        @"purchase_date": past,
        @"store": @"app_store",
        @"store_transaction_id": randomTransactionID(),
        @"unsubscribe_detected_at": [NSNull null],
        @"grace_period_expires_date": [NSNull null],
        @"billing_issues_detected_at": [NSNull null],
        @"refunded_at": [NSNull null],
        @"auto_resume_date": [NSNull null],
        @"plan_key": planKey,
        @"pending_product_id": productId,
        @"pending_product_plan_key": planKey,
        @"pending_subscription_period": @"P1Y",
        @"quotas": forMyCita,
        @"management_url": mgmtURL,
        @"renewal_type": @"auto",
        @"subscription_period": @"P1Y",
        @"app_type": @"ios",
    } };

    sub[@"quotas"] = forMyCita;
    sub[@"management_url"] = mgmtURL;

    root[@"subscriber"] = sub;

    NSData *out = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
    return out ?: original;
}

static void installStringPatch(void) {
    Class cls = objc_getClass("NSBundle");
    if (!cls) return;
    SEL sel = sel_registerName("localizedStringForKey:value:table:");
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    typedef NSString *(*OrigT)(id, SEL, NSString *, NSString *, NSString *);
    OrigT orig = (OrigT)method_getImplementation(m);
    NSDictionary *map = @{
        @"subscription_billing_period_yearly": @"BadNotes",
        @"subscription_details_subtitle_pro": @"Cracked by Constantin Clerc (c22dev) :)",
    };

    IMP newImp = imp_implementationWithBlock(^NSString *(id self, NSString *key, NSString *value, NSString *table) {
        NSString *override = map[key];
        if (override) return override;
        return orig(self, sel, key, value, table);
    });
    method_setImplementation(m, newImp);
}

static void installNetworkPatch(void) {
    Class sess = objc_getClass("NSURLSession");
    if (!sess) return;
    SEL sel = sel_registerName("dataTaskWithRequest:completionHandler:");
    Method m = class_getInstanceMethod(sess, sel);
    if (!m) return;
    typedef id (*OrigT)(id, SEL, id, void(^)(id,id,id));
    OrigT orig = (OrigT)method_getImplementation(m);

    IMP newImp = imp_implementationWithBlock(^id(id self, id request, void(^handler)(id,id,id)) {
        NSString *uid = subscriberUID([[request URL] absoluteString]);
        id reqToUse = request;
        if (uid) {
            NSMutableURLRequest *mr = [request mutableCopy];
            [mr setValue:nil forHTTPHeaderField:@"If-None-Match"];
            [mr setValue:nil forHTTPHeaderField:@"If-Modified-Since"];
            mr.cachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
            reqToUse = mr;
        }
        void (^wrapped)(id,id,id) = ^(id dataObj, id resp, id err) {
            if (uid && !err) {
                NSData *src = [dataObj isKindOfClass:[NSData class]] ? dataObj : nil;
                NSData *newData = injectEntitlements(src, uid);
                id respToUse = resp;
                if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
                    NSHTTPURLResponse *hr = resp;
                    NSMutableDictionary *hdrs = [[hr allHeaderFields] mutableCopy] ?: [NSMutableDictionary dictionary];
                    for (NSString *k in [hdrs allKeys])
                        if ([k caseInsensitiveCompare:@"ETag"] == NSOrderedSame)
                            [hdrs removeObjectForKey:k];
                    hdrs[@"Content-Type"] = @"application/json";
                    hdrs[@"Content-Length"] = [NSString stringWithFormat:@"%lu", (unsigned long)newData.length];
                    respToUse = [[NSHTTPURLResponse alloc] initWithURL:hr.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:hdrs];
                }
                if (handler) handler(newData, respToUse, err);
                return;
            }
            if (handler) handler(dataObj, resp, err);
        };
        return orig(self, sel, reqToUse, wrapped);
    });
    method_setImplementation(m, newImp);
}

__attribute__((constructor))
static void tweak_init(void) {
    @autoreleasepool {
        installStringPatch();
        installNetworkPatch();
    }
}

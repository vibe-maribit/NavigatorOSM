#import "TollGuruService.h"
#import "RoutingService.h"
#import "VoiceGuidanceService.h"
#import "LocalizationManager.h"

NSString *const kTollPricesUpdatedNotification = @"kTollPricesUpdatedNotification";

static NSString *const kDefaultsTollGuruApiKey = @"TollGuru_API_Key";
static NSString *const kDefaultsTollGuruQuotaDate = @"TollGuru_QuotaExceededDate";
static NSString *const kDefaultsTollGuruDailyCount = @"TollGuru_DailyCount";
static NSString *const kDefaultsTollGuruCountDate = @"TollGuru_CountDate";

@interface TollGuruService ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) BOOL hasSpokenQuotaWarningToday;
@end

@implementation TollGuruService

+ (instancetype)sharedService {
    static TollGuruService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TollGuruService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 8.0;
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"NavigatoreOSM/1.3.6 (iPad Mini 1; iOS 9.3.5)"
        };
        _session = [NSURLSession sessionWithConfiguration:config];
        _hasSpokenQuotaWarningToday = NO;
        [self checkAndResetDailyCounterIfNeeded];
    }
    return self;
}

#pragma mark - Gestione Chiave API

- (NSString *)apiKey {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsTollGuruApiKey] ?: @"";
}

- (void)setApiKey:(NSString *)apiKey {
    NSString *trimmed = [apiKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:kDefaultsTollGuruApiKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)hasValidApiKey {
    return (self.apiKey.length > 5);
}

#pragma mark - Quota e Limiti

- (NSString *)todayDateString {
    static NSDateFormatter *df = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"yyyy-MM-dd";
        df.timeZone = [NSTimeZone systemTimeZone];
    });
    return [df stringFromDate:[NSDate date]];
}

- (void)checkAndResetDailyCounterIfNeeded {
    NSString *savedDate = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsTollGuruCountDate];
    NSString *today = [self todayDateString];
    if (![savedDate isEqualToString:today]) {
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:kDefaultsTollGuruDailyCount];
        [[NSUserDefaults standardUserDefaults] setObject:today forKey:kDefaultsTollGuruCountDate];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (NSUInteger)dailyRequestsCount {
    [self checkAndResetDailyCounterIfNeeded];
    return (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:kDefaultsTollGuruDailyCount];
}

- (void)incrementDailyRequestsCount {
    [self checkAndResetDailyCounterIfNeeded];
    NSInteger count = [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultsTollGuruDailyCount] + 1;
    [[NSUserDefaults standardUserDefaults] setInteger:count forKey:kDefaultsTollGuruDailyCount];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSDate *)lastQuotaExceededDate {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsTollGuruQuotaDate];
}

- (BOOL)isQuotaExceeded {
    NSDate *exceeded = self.lastQuotaExceededDate;
    if (!exceeded) return NO;

    NSCalendar *cal = [NSCalendar currentCalendar];
    if ([cal respondsToSelector:@selector(isDateInToday:)]) {
        return [cal isDateInToday:exceeded];
    }
    NSDateComponents *c1 = [cal components:NSCalendarUnitDay|NSCalendarUnitMonth|NSCalendarUnitYear fromDate:exceeded];
    NSDateComponents *c2 = [cal components:NSCalendarUnitDay|NSCalendarUnitMonth|NSCalendarUnitYear fromDate:[NSDate date]];
    return (c1.year == c2.year && c1.month == c2.month && c1.day == c2.day);
}

- (void)markQuotaExceeded {
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kDefaultsTollGuruQuotaDate];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (!self.hasSpokenQuotaWarningToday) {
        self.hasSpokenQuotaWarningToday = YES;
        BOOL isIt = [[LocalizationManager sharedManager] isItalian];
        NSString *warnMsg = isIt
            ? @"Attenzione: quota giornaliera TollGuru superata. Verrà usata la stima chilometrica."
            : @"Warning: TollGuru daily quota exceeded. Falling back to toll estimation.";
        [[VoiceGuidanceService sharedService] speak:warnMsg];
    }
}

- (void)resetQuotaStatus {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultsTollGuruQuotaDate];
    [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:kDefaultsTollGuruDailyCount];
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.hasSpokenQuotaWarningToday = NO;
}

- (NSString *)quotaStatusDescription {
    if (!self.hasValidApiKey) {
        return NLString(@"TOLLGURU_NOT_CONFIGURED", @"Non configurato (stima km)");
    }
    if (self.isQuotaExceeded) {
        return NLString(@"TOLLGURU_QUOTA_EXCEEDED", @"Quota superata (fallback stima)");
    }
    return [NSString stringWithFormat:NLString(@"TOLLGURU_ACTIVE_FMT", @"Attivo (%lu chiamate oggi)"), (unsigned long)self.dailyRequestsCount];
}

#pragma mark - Richieste API TollGuru

- (void)requestTollForRoutes:(NSArray<RouteInfo *> *)routes
                        from:(CLLocationCoordinate2D)start
                          to:(CLLocationCoordinate2D)destination {
    if (routes.count == 0) return;
    if (!self.hasValidApiKey || self.isQuotaExceeded) {
        // Fallback già calcolato in updateTripCosts
        return;
    }

    [self fetchTollsFrom:start to:destination completion:^(NSArray<NSNumber *> *tollCosts, NSError *error) {
        if (error || tollCosts.count == 0) {
            NSLog(@"[TollGuruService] Errore calcolo pedaggi TollGuru: %@", error.localizedDescription);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL anyUpdated = NO;
            for (NSUInteger i = 0; i < routes.count; i++) {
                RouteInfo *r = routes[i];
                if (i < tollCosts.count) {
                    double cost = [tollCosts[i] doubleValue];
                    r.tollCost = cost;
                    r.isTollCostExact = YES;
                    r.hasToll = (cost > 0.05);
                    [r updateTripCosts];
                    anyUpdated = YES;
                }
            }

            if (anyUpdated) {
                NSLog(@"[TollGuruService] Aggiornati costi reali di pedaggio per %lu percorsi", (unsigned long)routes.count);
                [[NSNotificationCenter defaultCenter] postNotificationName:kTollPricesUpdatedNotification object:nil];
            }
        });
    }];
}

- (void)fetchTollsFrom:(CLLocationCoordinate2D)start
                    to:(CLLocationCoordinate2D)destination
            completion:(void (^)(NSArray<NSNumber *> *tollCosts, NSError *error))completion {

    if (!self.hasValidApiKey) {
        if (completion) completion(nil, [NSError errorWithDomain:@"TollGuruService" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"API Key mancante"}]);
        return;
    }

    if (self.isQuotaExceeded) {
        if (completion) completion(nil, [NSError errorWithDomain:@"TollGuruService" code:429 userInfo:@{NSLocalizedDescriptionKey: @"Quota giornaliera superata"}]);
        return;
    }

    [self incrementDailyRequestsCount];

    NSURL *url = [NSURL URLWithString:@"https://apis.tollguru.com/toll/v2/origin-destination-waypoints"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:self.apiKey forHTTPHeaderField:@"x-api-key"];

    NSDictionary *payload = @{
        @"from": @{
            @"lat": @(start.latitude),
            @"lng": @(start.longitude)
        },
        @"to": @{
            @"lat": @(destination.latitude),
            @"lng": @(destination.longitude)
        },
        @"vehicleType": @"2AxlesAuto"
    };

    NSError *encErr = nil;
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&encErr];

    __weak TollGuruService *weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode == 429) {
            NSLog(@"[TollGuruService] Ricevuto HTTP 429 (Too Many Requests / Quota Exceeded)");
            [weakSelf markQuotaExceeded];
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:@"TollGuruService" code:429 userInfo:@{NSLocalizedDescriptionKey: @"HTTP 429: Quota giornaliera TollGuru esaurita"}]);
                });
            }
            return;
        }

        if (error || !data) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error ?: [NSError errorWithDomain:@"TollGuruService" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Nessuna risposta"}]);
                });
            }
            return;
        }

        NSError *parseErr = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseErr];
        if (parseErr || ![root isKindOfClass:[NSDictionary class]]) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, parseErr);
                });
            }
            return;
        }

        // Verifica messaggio d'errore nel body
        if (root[@"message"] && [root[@"message"] isKindOfClass:[NSString class]]) {
            NSString *msg = root[@"message"];
            if ([msg rangeOfString:@"quota" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [msg rangeOfString:@"limit" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [weakSelf markQuotaExceeded];
            }
        }

        NSArray *rawRoutes = root[@"routes"];
        if (![rawRoutes isKindOfClass:[NSArray class]] || rawRoutes.count == 0) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(@[], nil);
                });
            }
            return;
        }

        NSMutableArray<NSNumber *> *results = [NSMutableArray array];
        for (NSDictionary *rDict in rawRoutes) {
            double toll = 0.0;
            NSDictionary *costs = rDict[@"costs"];
            if ([costs isKindOfClass:[NSDictionary class]]) {
                NSNumber *val = costs[@"tag"] ?: costs[@"cash"] ?: costs[@"minimum"] ?: costs[@"prepaidCard"];
                if (val && [val isKindOfClass:[NSNumber class]]) {
                    toll = [val doubleValue];
                }
            }
            [results addObject:@(toll)];
        }

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([results copy], nil);
            });
        }
    }];
    [task resume];
}

@end

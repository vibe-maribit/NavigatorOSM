#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@class RouteInfo;

extern NSString *const kTollPricesUpdatedNotification;

@interface TollGuruService : NSObject

+ (instancetype)sharedService;

/// Chiave API TollGuru (salvata in NSUserDefaults)
@property (nonatomic, copy) NSString *apiKey;

/// Indica se è configurata una chiave API non vuota
@property (nonatomic, readonly) BOOL hasValidApiKey;

/// Indica se la quota giornaliera (~15 chiamate/giorno per account free) è stata superata oggi (HTTP 429)
@property (nonatomic, readonly) BOOL isQuotaExceeded;

/// Numero di richieste inviate oggi
@property (nonatomic, readonly) NSUInteger dailyRequestsCount;

/// Data in cui è stato rilevato l'ultimo superamento quota HTTP 429
@property (nonatomic, readonly) NSDate *lastQuotaExceededDate;

/// Descrizione testuale dello stato quota (es. "Attiva (3/15 oggi)" oppure "Quota superata (Fallback stima)")
- (NSString *)quotaStatusDescription;

/// Azzera manualmente il blocco quota (per test o nuovo ciclo)
- (void)resetQuotaStatus;

/// Richiede il calcolo dei pedaggi per una lista di percorsi
- (void)requestTollForRoutes:(NSArray<RouteInfo *> *)routes
                        from:(CLLocationCoordinate2D)start
                          to:(CLLocationCoordinate2D)destination;

/// Richiesta diretta alle API TollGuru per origine e destinazione
- (void)fetchTollsFrom:(CLLocationCoordinate2D)start
                    to:(CLLocationCoordinate2D)destination
            completion:(void (^)(NSArray<NSNumber *> *tollCosts, NSError *error))completion;

@end

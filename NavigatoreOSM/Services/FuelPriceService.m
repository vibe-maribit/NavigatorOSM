#import "FuelPriceService.h"
#import "LocalizationManager.h"

NSString *const kFuelPricesUpdatedNotification = @"FuelPricesUpdatedNotification";

static NSString *const kPrefFuelType = @"FuelTypePreference";
static NSString *const kPrefCustomConsumptionPrefix = @"FuelCustomConsumption_";
static NSString *const kPrefCustomPricePrefix = @"FuelCustomPrice_";
static NSString *const kPrefOnlinePricePrefix = @"FuelOnlinePrice_";
static NSString *const kPrefOnlineFetchDate = @"FuelOnlineFetchTimestamp";

@interface FuelPriceService ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation FuelPriceService

+ (instancetype)sharedService {
    static FuelPriceService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FuelPriceService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 12.0;
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"NavigatoreOSM/1.3 (iPad; iOS 9.3.5; CarburantiClient)",
            @"Content-Type": @"application/json"
        };
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - Tipo Carburante Selezionato

- (FuelType)selectedFuelType {
    NSInteger val = [[NSUserDefaults standardUserDefaults] integerForKey:kPrefFuelType];
    if (val < 0 || val > 3) return FuelTypePetrol;
    return (FuelType)val;
}

- (void)setSelectedFuelType:(FuelType)selectedFuelType {
    [[NSUserDefaults standardUserDefaults] setInteger:selectedFuelType forKey:kPrefFuelType];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kFuelPricesUpdatedNotification object:self];
}

- (NSString *)nameForFuelType:(FuelType)type {
    BOOL isIt = [[LocalizationManager sharedManager] isItalian];
    switch (type) {
        case FuelTypePetrol:   return isIt ? @"Benzina" : @"Petrol";
        case FuelTypeDiesel:   return isIt ? @"Diesel (Gasolio)" : @"Diesel";
        case FuelTypeLPG:      return @"GPL";
        case FuelTypeElectric: return isIt ? @"Elettrico" : @"Electric";
    }
    return @"Carburante";
}

- (NSString *)unitForFuelType:(FuelType)type {
    return (type == FuelTypeElectric) ? @"kWh" : @"L";
}

- (NSString *)consumptionUnitForFuelType:(FuelType)type {
    return (type == FuelTypeElectric) ? @"kWh/100km" : @"L/100km";
}

#pragma mark - Consumi

- (double)defaultConsumptionForFuelType:(FuelType)type {
    switch (type) {
        case FuelTypePetrol:   return 6.5;  // 6.5 L / 100km
        case FuelTypeDiesel:   return 5.2;  // 5.2 L / 100km
        case FuelTypeLPG:      return 8.2;  // 8.2 L / 100km
        case FuelTypeElectric: return 16.0; // 16.0 kWh / 100km
    }
    return 6.5;
}

- (double)effectiveConsumptionForFuelType:(FuelType)type {
    NSString *key = [NSString stringWithFormat:@"%@%ld", kPrefCustomConsumptionPrefix, (long)type];
    double custom = [[NSUserDefaults standardUserDefaults] doubleForKey:key];
    if (custom > 0.05) {
        return custom;
    }
    return [self defaultConsumptionForFuelType:type];
}

- (void)setCustomConsumption:(double)consumption forFuelType:(FuelType)type {
    NSString *key = [NSString stringWithFormat:@"%@%ld", kPrefCustomConsumptionPrefix, (long)type];
    if (consumption > 0.05) {
        [[NSUserDefaults standardUserDefaults] setDouble:consumption forKey:key];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kFuelPricesUpdatedNotification object:self];
}

- (BOOL)hasCustomConsumptionForFuelType:(FuelType)type {
    NSString *key = [NSString stringWithFormat:@"%@%ld", kPrefCustomConsumptionPrefix, (long)type];
    return ([[NSUserDefaults standardUserDefaults] doubleForKey:key] > 0.05);
}

#pragma mark - Prezzi

- (double)defaultPriceForFuelType:(FuelType)type {
    switch (type) {
        case FuelTypePetrol:   return 1.820; // € 1.820 / L
        case FuelTypeDiesel:   return 1.720; // € 1.720 / L
        case FuelTypeLPG:      return 0.720; // € 0.720 / L
        case FuelTypeElectric: return 0.400; // € 0.400 / kWh
    }
    return 1.800;
}

- (double)onlinePriceForFuelType:(FuelType)type {
    NSString *key = [NSString stringWithFormat:@"%@%ld", kPrefOnlinePricePrefix, (long)type];
    return [[NSUserDefaults standardUserDefaults] doubleForKey:key];
}

- (double)effectivePriceForFuelType:(FuelType)type {
    // 1. Se l'utente ha impostato un prezzo personalizzato (override), ha la massima priorità
    NSString *customKey = [NSString stringWithFormat:@"%@%ld", kPrefCustomPricePrefix, (long)type];
    double custom = [[NSUserDefaults standardUserDefaults] doubleForKey:customKey];
    if (custom > 0.05) {
        return custom;
    }

    // 2. Se è disponibile il prezzo online aggiornato MIMIT, usalo
    double online = [self onlinePriceForFuelType:type];
    if (online > 0.05) {
        return online;
    }

    // 3. Fallback sul prezzo predefinito
    return [self defaultPriceForFuelType:type];
}

- (void)setCustomPrice:(double)price forFuelType:(FuelType)type {
    NSString *key = [NSString stringWithFormat:@"%@%ld", kPrefCustomPricePrefix, (long)type];
    if (price > 0.05) {
        [[NSUserDefaults standardUserDefaults] setDouble:price forKey:key];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kFuelPricesUpdatedNotification object:self];
}

- (BOOL)hasCustomPriceForFuelType:(FuelType)type {
    NSString *key = [NSString stringWithFormat:@"%@%ld", kPrefCustomPricePrefix, (long)type];
    return ([[NSUserDefaults standardUserDefaults] doubleForKey:key] > 0.05);
}

- (BOOL)isUsingOnlinePriceForFuelType:(FuelType)type {
    if ([self hasCustomPriceForFuelType:type]) return NO;
    return ([self onlinePriceForFuelType:type] > 0.05);
}

- (NSDate *)lastOnlinePriceFetchDate {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kPrefOnlineFetchDate];
}

#pragma mark - Recupero Prezzi Online (MIMIT Carburanti API)

- (void)fetchOnlinePricesAroundCoordinate:(CLLocationCoordinate2D)coordinate
                               completion:(void (^)(BOOL success, NSString *statusMessage))completion {

    CLLocationCoordinate2D target = coordinate;
    if (!CLLocationCoordinate2DIsValid(target) || (fabs(target.latitude) < 1.0 && fabs(target.longitude) < 1.0)) {
        // Fallback sul centro Italia / Roma o Milano se GPS non attivo
        target = CLLocationCoordinate2DMake(45.4642, 9.1900);
    }

    NSURL *url = [NSURL URLWithString:@"https://carburanti.mise.gov.it/ospzApi/search/zone"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *payload = @{
        @"points": @[
            @{ @"lat": @(target.latitude), @"lng": @(target.longitude) }
        ],
        @"radius": @(25) // 25 km intorno alle coordinate
    };

    NSError *err = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&err];
    if (err) {
        if (completion) completion(NO, @"Errore preparazione richiesta");
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            NSLog(@"[FuelPriceService] Errore connessione API MIMIT: %@", error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, error.localizedDescription ?: @"Errore rete");
            });
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || ![json isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[FuelPriceService] Errore JSON API MIMIT: %@", jsonErr.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, @"Risposta MIMIT non valida");
            });
            return;
        }

        NSArray *results = json[@"results"];
        if (![results isKindOfClass:[NSArray class]] || results.count == 0) {
            NSLog(@"[FuelPriceService] Nessun distributore restituito per (%.4f, %.4f)", target.latitude, target.longitude);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, @"Nessun distributore trovato in zona");
            });
            return;
        }

        // Raccogli prezzi per Benzina, Gasolio, GPL (preferendo self-service se presente)
        NSMutableArray<NSNumber *> *petrolSelf = [NSMutableArray array];
        NSMutableArray<NSNumber *> *petrolAll = [NSMutableArray array];

        NSMutableArray<NSNumber *> *dieselSelf = [NSMutableArray array];
        NSMutableArray<NSNumber *> *dieselAll = [NSMutableArray array];

        NSMutableArray<NSNumber *> *lpgPrices = [NSMutableArray array];

        for (NSDictionary *st in results) {
            NSArray *fuels = st[@"fuels"];
            if (![fuels isKindOfClass:[NSArray class]]) continue;

            for (NSDictionary *f in fuels) {
                NSString *name = [f[@"name"] lowercaseString] ?: @"";
                double price = [f[@"price"] doubleValue];
                if (price < 0.30 || price > 4.50) continue; // Scarta valori anomali

                BOOL isSelf = [f[@"isSelf"] boolValue];

                if ([name containsString:@"benzina"] && ![name containsString:@"speciale"] && ![name containsString:@"100"]) {
                    [petrolAll addObject:@(price)];
                    if (isSelf) [petrolSelf addObject:@(price)];
                } else if ([name containsString:@"gasolio"] || [name containsString:@"diesel"]) {
                    [dieselAll addObject:@(price)];
                    if (isSelf) [dieselSelf addObject:@(price)];
                } else if ([name containsString:@"gpl"]) {
                    [lpgPrices addObject:@(price)];
                }
            }
        }

        auto double (^calcAvg)(NSArray<NSNumber *> *) = ^double(NSArray<NSNumber *> *list) {
            if (list.count == 0) return 0.0;
            double sum = 0;
            for (NSNumber *n in list) sum += [n doubleValue];
            return sum / (double)list.count;
        };

        double avgPetrol = (petrolSelf.count > 0) ? calcAvg(petrolSelf) : calcAvg(petrolAll);
        double avgDiesel = (dieselSelf.count > 0) ? calcAvg(dieselSelf) : calcAvg(dieselAll);
        double avgLPG = calcAvg(lpgPrices);

        if (avgPetrol > 0.5) {
            [[NSUserDefaults standardUserDefaults] setDouble:avgPetrol
                                                      forKey:[NSString stringWithFormat:@"%@%ld", kPrefOnlinePricePrefix, (long)FuelTypePetrol]];
        }
        if (avgDiesel > 0.5) {
            [[NSUserDefaults standardUserDefaults] setDouble:avgDiesel
                                                      forKey:[NSString stringWithFormat:@"%@%ld", kPrefOnlinePricePrefix, (long)FuelTypeDiesel]];
        }
        if (avgLPG > 0.3) {
            [[NSUserDefaults standardUserDefaults] setDouble:avgLPG
                                                      forKey:[NSString stringWithFormat:@"%@%ld", kPrefOnlinePricePrefix, (long)FuelTypeLPG]];
        }

        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kPrefOnlineFetchDate];
        [[NSUserDefaults standardUserDefaults] synchronize];

        NSLog(@"[FuelPriceService] Prezzi MIMIT aggiornati: Benzina=%.3f€, Diesel=%.3f€, GPL=%.3f€ (campioni: %lu stazioni)",
              avgPetrol, avgDiesel, avgLPG, (unsigned long)results.count);

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:kFuelPricesUpdatedNotification object:self];
            if (completion) {
                NSString *msg = [NSString stringWithFormat:@"Prezzi MIMIT aggiornati (Benzina %.3f€, Diesel %.3f€, GPL %.3f€)",
                                 avgPetrol, avgDiesel, avgLPG];
                completion(YES, msg);
            }
        });
    }];
    [task resume];
}

#pragma mark - Calcolo Costi di Viaggio

- (double)fuelCostForDistance:(CLLocationDistance)distanceMeters {
    return [self fuelCostForDistance:distanceMeters fuelType:[self selectedFuelType]];
}

- (double)fuelCostForDistance:(CLLocationDistance)distanceMeters fuelType:(FuelType)type {
    if (distanceMeters <= 0) return 0.0;

    double distanceKm = distanceMeters / 1000.0;
    double consumptionPer100 = [self effectiveConsumptionForFuelType:type];
    double pricePerUnit = [self effectivePriceForFuelType:type];

    // Quantità consumata = (distanza / 100) * consumo
    double quantityUsed = (distanceKm / 100.0) * consumptionPer100;
    return quantityUsed * pricePerUnit;
}

- (double)estimatedTollCostForDistance:(CLLocationDistance)distanceMeters hasTolls:(BOOL)hasTolls {
    if (!hasTolls || distanceMeters <= 0) return 0.0;

    // Tariffa media autostradale italiana rete ASPI (Classe A): circa 0.075 €/km
    // La quota di autostrada sul percorso complessivo per itinerari a pedaggio è tipicamente il 75-85%
    double km = distanceMeters / 1000.0;
    double tollKm = km * 0.80;
    return tollKm * 0.075;
}

- (NSString *)formattedCostSummaryForFuelCost:(double)fuelCost tollCost:(double)tollCost {
    double total = fuelCost + tollCost;
    if (tollCost > 0.05) {
        return [NSString stringWithFormat:@"⛽ %.2f € • 🛣️ %.2f € • Tot. %.2f €", fuelCost, tollCost, total];
    } else {
        return [NSString stringWithFormat:@"⛽ %.2f € • 🛣️ 0.00 € (Tot. %.2f €)", fuelCost, total];
    }
}

@end

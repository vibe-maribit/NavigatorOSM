#import "FuelPriceService.h"
#import "LocalizationManager.h"

NSString *const kFuelPricesUpdatedNotification = @"FuelPricesUpdatedNotification";

static NSString *const kPrefFuelType = @"FuelTypePreference";
static NSString *const kPrefCustomConsumptionPrefix = @"FuelCustomConsumption_";
static NSString *const kPrefCustomPricePrefix = @"FuelCustomPrice_";
static NSString *const kPrefOnlinePricePrefix = @"FuelOnlinePrice_";
static NSString *const kPrefOnlineFetchDate = @"FuelOnlineFetchTimestamp";

#pragma mark - FuelStation Model

@implementation FuelStation

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInt64:self.stationId forKey:@"id"];
    [coder encodeObject:self.brand forKey:@"brand"];
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeObject:self.address forKey:@"addr"];
    [coder encodeDouble:self.coordinate.latitude forKey:@"lat"];
    [coder encodeDouble:self.coordinate.longitude forKey:@"lon"];
    [coder encodeDouble:self.petrolPriceSelf forKey:@"petrolSelf"];
    [coder encodeDouble:self.petrolPriceServed forKey:@"petrolServed"];
    [coder encodeDouble:self.dieselPriceSelf forKey:@"dieselSelf"];
    [coder encodeDouble:self.dieselPriceServed forKey:@"dieselServed"];
    [coder encodeDouble:self.lpgPrice forKey:@"lpg"];
    [coder encodeDouble:self.methanePrice forKey:@"methane"];
    [coder encodeDouble:self.distanceFromQuery forKey:@"dist"];
    [coder encodeObject:self.lastUpdated forKey:@"date"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _stationId = [coder decodeInt64ForKey:@"id"];
        _brand = [coder decodeObjectOfClass:[NSString class] forKey:@"brand"];
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        _address = [coder decodeObjectOfClass:[NSString class] forKey:@"addr"];
        double lat = [coder decodeDoubleForKey:@"lat"];
        double lon = [coder decodeDoubleForKey:@"lon"];
        _coordinate = CLLocationCoordinate2DMake(lat, lon);
        _petrolPriceSelf = [coder decodeDoubleForKey:@"petrolSelf"];
        _petrolPriceServed = [coder decodeDoubleForKey:@"petrolServed"];
        _dieselPriceSelf = [coder decodeDoubleForKey:@"dieselSelf"];
        _dieselPriceServed = [coder decodeDoubleForKey:@"dieselServed"];
        _lpgPrice = [coder decodeDoubleForKey:@"lpg"];
        _methanePrice = [coder decodeDoubleForKey:@"methane"];
        _distanceFromQuery = [coder decodeDoubleForKey:@"dist"];
        _lastUpdated = [coder decodeObjectOfClass:[NSDate class] forKey:@"date"];
    }
    return self;
}

- (double)effectivePriceForFuelType:(FuelType)type {
    switch (type) {
        case FuelTypePetrol:
            return (self.petrolPriceSelf > 0.1) ? self.petrolPriceSelf : self.petrolPriceServed;
        case FuelTypeDiesel:
            return (self.dieselPriceSelf > 0.1) ? self.dieselPriceSelf : self.dieselPriceServed;
        case FuelTypeLPG:
            return self.lpgPrice;
        case FuelTypeElectric:
            return 0.0;
    }
    return 0.0;
}

- (NSString *)displayTitleForFuelType:(FuelType)type {
    double p = [self effectivePriceForFuelType:type];
    NSString *bName = (self.brand && self.brand.length > 0) ? self.brand : (self.name ?: @"Distributore");
    if (p > 0.1) {
        return [NSString stringWithFormat:@"⛽ %@ • %.3f €", bName, p];
    }
    return [NSString stringWithFormat:@"⛽ %@", bName];
}

- (NSString *)formattedSubtitle {
    NSMutableArray *parts = [NSMutableArray array];
    if (self.petrolPriceSelf > 0.1) {
        [parts addObject:[NSString stringWithFormat:@"Benzina: %.3f€", self.petrolPriceSelf]];
    } else if (self.petrolPriceServed > 0.1) {
        [parts addObject:[NSString stringWithFormat:@"Benzina (serv.): %.3f€", self.petrolPriceServed]];
    }

    if (self.dieselPriceSelf > 0.1) {
        [parts addObject:[NSString stringWithFormat:@"Diesel: %.3f€", self.dieselPriceSelf]];
    } else if (self.dieselPriceServed > 0.1) {
        [parts addObject:[NSString stringWithFormat:@"Diesel (serv.): %.3f€", self.dieselPriceServed]];
    }

    if (self.lpgPrice > 0.1) {
        [parts addObject:[NSString stringWithFormat:@"GPL: %.3f€", self.lpgPrice]];
    }

    if (self.address && self.address.length > 0) {
        [parts addObject:self.address];
    }

    if (parts.count == 0) {
        return @"Distributore di carburante";
    }
    return [parts componentsJoinedByString:@" | "];
}

@end

#pragma mark - FuelStationAnnotation

@implementation FuelStationAnnotation

- (instancetype)initWithStation:(FuelStation *)station fuelType:(FuelType)fuelType {
    self = [super init];
    if (self) {
        _station = station;
        _fuelType = fuelType;
        self.coordinate = station.coordinate;
        self.title = [station displayTitleForFuelType:fuelType];
        self.subtitle = [station formattedSubtitle];
    }
    return self;
}

@end

#pragma mark - FuelPriceService

@interface FuelPriceService ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, readwrite) NSArray<FuelStation *> *cachedStations;
@property (nonatomic, copy) NSString *cacheFilePath;
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
        config.timeoutIntervalForRequest = 14.0;
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"NavigatoreOSM/1.3.7 (iPad; iOS 9.3.5; CarburantiClient)",
            @"Content-Type": @"application/json"
        };
        _session = [NSURLSession sessionWithConfiguration:config];

        NSString *cachesDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        _cacheFilePath = [cachesDir stringByAppendingPathComponent:@"fuel_stations_cache.plist"];
        [self loadCachedStationsFromDisk];
    }
    return self;
}

- (void)loadCachedStationsFromDisk {
    if (![[NSFileManager defaultManager] fileExistsAtPath:_cacheFilePath]) return;
    @try {
        NSData *data = [NSData dataWithContentsOfFile:_cacheFilePath];
        if (data) {
            NSArray *loaded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            if ([loaded isKindOfClass:[NSArray class]]) {
                _cachedStations = loaded;
                NSLog(@"[FuelPriceService] Caricati %lu distributori dalla cache su disco", (unsigned long)_cachedStations.count);
            }
        }
    } @catch (NSException *ex) {
        NSLog(@"[FuelPriceService] Errore lettura cache distributori: %@", ex);
    }
}

- (void)saveCachedStationsToDisk {
    if (!_cachedStations || _cachedStations.count == 0) return;
    @try {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:_cachedStations];
        [data writeToFile:_cacheFilePath atomically:YES];
    } @catch (NSException *ex) {
        NSLog(@"[FuelPriceService] Errore salvataggio cache distributori: %@", ex);
    }
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
        case FuelTypePetrol:   return 1.829; // ~1.83 €/L
        case FuelTypeDiesel:   return 1.719; // ~1.72 €/L
        case FuelTypeLPG:      return 0.729; // ~0.73 €/L
        case FuelTypeElectric: return 0.450; // ~0.45 €/kWh
    }
    return 1.800;
}

- (double)onlinePriceForFuelType:(FuelType)type {
    NSString *key = [NSString stringWithFormat:@"%@%ld", kPrefOnlinePricePrefix, (long)type];
    return [[NSUserDefaults standardUserDefaults] doubleForKey:key];
}

- (double)effectivePriceForFuelType:(FuelType)type {
    NSString *customKey = [NSString stringWithFormat:@"%@%ld", kPrefCustomPricePrefix, (long)type];
    double custom = [[NSUserDefaults standardUserDefaults] doubleForKey:customKey];
    if (custom > 0.05) {
        return custom;
    }
    double online = [self onlinePriceForFuelType:type];
    if (online > 0.05) {
        return online;
    }
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

#pragma mark - Recupero Distributori da API MIMIT (Carburanti / Prezzi Benzina)

- (void)fetchStationsAroundCoordinate:(CLLocationCoordinate2D)coordinate
                             radiusKm:(int)radiusKm
                           completion:(void (^)(NSArray<FuelStation *> *stations, NSError *error))completion {

    CLLocationCoordinate2D target = coordinate;
    if (!CLLocationCoordinate2DIsValid(target) || (fabs(target.latitude) < 0.1 && fabs(target.longitude) < 0.1)) {
        target = CLLocationCoordinate2DMake(45.4642, 9.1900); // Default Milano centro
    }

    int clampedRadius = (radiusKm < 3) ? 3 : ((radiusKm > 30) ? 30 : radiusKm);

    NSURL *url = [NSURL URLWithString:@"https://carburanti.mise.gov.it/ospzApi/search/zone"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    NSDictionary *payload = @{
        @"points": @[
            @{ @"lat": @(target.latitude), @"lng": @(target.longitude) }
        ],
        @"radius": @(clampedRadius)
    };

    NSError *err = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&err];
    if (err) {
        if (completion) completion(self.cachedStations ?: @[], err);
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            NSLog(@"[FuelPriceService] Errore connessione API MIMIT: %@", error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(self.cachedStations ?: @[], error);
            });
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || ![json isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[FuelPriceService] Errore JSON API MIMIT: %@", jsonErr.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(self.cachedStations ?: @[], jsonErr);
            });
            return;
        }

        NSArray *results = json[@"results"];
        if (![results isKindOfClass:[NSArray class]] || results.count == 0) {
            NSLog(@"[FuelPriceService] Nessun distributore restituito per (%.4f, %.4f)", target.latitude, target.longitude);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(self.cachedStations ?: @[], nil);
            });
            return;
        }

        NSMutableArray<FuelStation *> *stationList = [NSMutableArray array];
        NSMutableArray<NSNumber *> *petrolSelf = [NSMutableArray array];
        NSMutableArray<NSNumber *> *petrolAll = [NSMutableArray array];
        NSMutableArray<NSNumber *> *dieselSelf = [NSMutableArray array];
        NSMutableArray<NSNumber *> *dieselAll = [NSMutableArray array];
        NSMutableArray<NSNumber *> *lpgPrices = [NSMutableArray array];

        for (NSDictionary *st in results) {
            NSDictionary *loc = st[@"location"];
            if (![loc isKindOfClass:[NSDictionary class]]) continue;

            double lat = [loc[@"lat"] doubleValue];
            double lon = [loc[@"lng"] doubleValue];
            if (lat == 0.0 && lon == 0.0) continue;

            FuelStation *station = [[FuelStation alloc] init];
            station.stationId = [st[@"id"] longLongValue];
            station.coordinate = CLLocationCoordinate2DMake(lat, lon);
            station.brand = [st[@"brand"] isKindOfClass:[NSString class]] ? st[@"brand"] : nil;
            station.name = [st[@"name"] isKindOfClass:[NSString class]] ? st[@"name"] : nil;
            station.address = [st[@"address"] isKindOfClass:[NSString class]] ? st[@"address"] : nil;
            station.distanceFromQuery = [st[@"distance"] doubleValue];
            station.lastUpdated = [NSDate date];

            NSArray *fuels = st[@"fuels"];
            if ([fuels isKindOfClass:[NSArray class]]) {
                for (NSDictionary *f in fuels) {
                    NSString *fuelName = [[f[@"name"] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
                    double price = [f[@"price"] doubleValue];
                    if (price < 0.30 || price > 4.50) continue;

                    BOOL isSelf = [f[@"isSelf"] boolValue];

                    if ([fuelName containsString:@"benzina"] && ![fuelName containsString:@"speciale"] && ![fuelName containsString:@"100"]) {
                        [petrolAll addObject:@(price)];
                        if (isSelf) {
                            [petrolSelf addObject:@(price)];
                            if (station.petrolPriceSelf <= 0 || price < station.petrolPriceSelf) {
                                station.petrolPriceSelf = price;
                            }
                        } else {
                            if (station.petrolPriceServed <= 0 || price < station.petrolPriceServed) {
                                station.petrolPriceServed = price;
                            }
                        }
                    } else if ([fuelName containsString:@"gasolio"] || [fuelName containsString:@"diesel"]) {
                        [dieselAll addObject:@(price)];
                        if (isSelf) {
                            [dieselSelf addObject:@(price)];
                            if (station.dieselPriceSelf <= 0 || price < station.dieselPriceSelf) {
                                station.dieselPriceSelf = price;
                            }
                        } else {
                            if (station.dieselPriceServed <= 0 || price < station.dieselPriceServed) {
                                station.dieselPriceServed = price;
                            }
                        }
                    } else if ([fuelName containsString:@"gpl"]) {
                        [lpgPrices addObject:@(price)];
                        if (station.lpgPrice <= 0 || price < station.lpgPrice) {
                            station.lpgPrice = price;
                        }
                    } else if ([fuelName containsString:@"metano"]) {
                        if (station.methanePrice <= 0 || price < station.methanePrice) {
                            station.methanePrice = price;
                        }
                    }
                }
            }

            [stationList addObject:station];
        }

        // Calcolo medie zonali MIMIT
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

        // Memorizza e unisci nella cache locale
        NSMutableDictionary<NSNumber *, FuelStation *> *dict = [NSMutableDictionary dictionary];
        for (FuelStation *s in self.cachedStations) {
            dict[@(s.stationId)] = s;
        }
        for (FuelStation *s in stationList) {
            dict[@(s.stationId)] = s;
        }
        self.cachedStations = [dict allValues];
        [self saveCachedStationsToDisk];

        NSLog(@"[FuelPriceService] MIMIT aggiornato: %lu distributori caricati. Medie: Benzina=%.3f, Diesel=%.3f, GPL=%.3f",
              (unsigned long)stationList.count, avgPetrol, avgDiesel, avgLPG);

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:kFuelPricesUpdatedNotification object:self];
            if (completion) {
                completion(stationList, nil);
            }
        });
    }];
    [task resume];
}

- (void)fetchOnlinePricesAroundCoordinate:(CLLocationCoordinate2D)coordinate
                               completion:(void (^)(BOOL success, NSString *statusMessage))completion {
    [self fetchStationsAroundCoordinate:coordinate radiusKm:15 completion:^(NSArray<FuelStation *> *stations, NSError *error) {
        if (error || stations.count == 0) {
            if (completion) completion(NO, error.localizedDescription ?: @"Nessun distributore trovato in zona");
            return;
        }
        double p = [self onlinePriceForFuelType:FuelTypePetrol];
        double d = [self onlinePriceForFuelType:FuelTypeDiesel];
        double g = [self onlinePriceForFuelType:FuelTypeLPG];
        NSString *msg = [NSString stringWithFormat:@"Prezzi MIMIT aggiornati (Benzina %.3f€, Diesel %.3f€, GPL %.3f€ su %lu distributori)",
                         p, d, g, (unsigned long)stations.count];
        if (completion) completion(YES, msg);
    }];
}

#pragma mark - Calcolo Costi di Viaggio

- (double)fuelCostForDistance:(CLLocationDistance)distanceMeters {
    return [self fuelCostForDistance:distanceMeters fuelType:self.selectedFuelType];
}

- (double)fuelCostForDistance:(CLLocationDistance)distanceMeters fuelType:(FuelType)type {
    if (distanceMeters <= 0.0) return 0.0;
    double km = distanceMeters / 1000.0;
    double consumption = [self effectiveConsumptionForFuelType:type];
    double price = [self effectivePriceForFuelType:type];
    double totalUnits = (km / 100.0) * consumption;
    return totalUnits * price;
}

- (double)estimatedTollCostForDistance:(CLLocationDistance)distanceMeters hasTolls:(BOOL)hasTolls {
    if (!hasTolls || distanceMeters <= 0.0) return 0.0;
    double highwayKm = (distanceMeters / 1000.0) * 0.70;
    const double kAverageTollRatePerKm = 0.075;
    return highwayKm * kAverageTollRatePerKm;
}

- (NSString *)formattedCostSummaryForFuelCost:(double)fuelCost tollCost:(double)tollCost {
    double total = fuelCost + tollCost;
    if (tollCost > 0.05) {
        return [NSString stringWithFormat:@"⛽ %.2f € • 🛣️ %.2f € (Tot. %.2f €)", fuelCost, tollCost, total];
    } else {
        return [NSString stringWithFormat:@"⛽ %.2f €", fuelCost];
    }
}

- (NSArray<FuelStationAnnotation *> *)annotationsForCachedStations {
    NSMutableArray *list = [NSMutableArray array];
    FuelType curType = self.selectedFuelType;
    for (FuelStation *st in self.cachedStations) {
        [list addObject:[[FuelStationAnnotation alloc] initWithStation:st fuelType:curType]];
    }
    return list;
}

@end

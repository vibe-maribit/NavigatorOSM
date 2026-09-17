#import "RoutingService.h"
#import "LocalizationManager.h"
#import "FuelPriceService.h"
#import "TollGuruService.h"

@implementation ManeuverStep
@end

@implementation RouteInfo

- (void)updateTripCosts {
    FuelPriceService *fuel = [FuelPriceService sharedService];
    self.fuelCost = [fuel fuelCostForDistance:self.totalDistance];
    if (!self.isTollCostExact) {
        self.tollCost = [fuel estimatedTollCostForDistance:self.totalDistance hasTolls:self.hasToll];
    }
    self.totalTripCost = self.fuelCost + self.tollCost;
}

- (NSString *)formattedCostSummary {
    return [[FuelPriceService sharedService] formattedCostSummaryForFuelCost:self.fuelCost tollCost:self.tollCost];
}

@end


@interface RoutingService ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation RoutingService

+ (instancetype)sharedService {
    static RoutingService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RoutingService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 15.0;
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"NavigatoreOSM/1.0 (iPad Mini 1; iOS 9.3.5)"
        };
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

static NSString *FormatManeuverLocalized(NSString *type, NSString *modifier, NSString *name) {
    BOOL isIt = [[LocalizationManager sharedManager] isItalian];
    NSString *base = @"";
    if ([type isEqualToString:@"depart"]) {
        base = isIt ? @"Parti verso" : @"Head towards";
    } else if ([type isEqualToString:@"arrive"]) {
        return isIt ? @"Destinazione raggiunta" : @"Destination reached";
    } else if ([type isEqualToString:@"turn"]) {
        if ([modifier isEqualToString:@"left"]) base = isIt ? @"Gira a sinistra" : @"Turn left";
        else if ([modifier isEqualToString:@"right"]) base = isIt ? @"Gira a destra" : @"Turn right";
        else if ([modifier isEqualToString:@"sharp left"]) base = isIt ? @"Svolta stretta a sinistra" : @"Sharp left";
        else if ([modifier isEqualToString:@"sharp right"]) base = isIt ? @"Svolta stretta a destra" : @"Sharp right";
        else if ([modifier isEqualToString:@"slight left"]) base = isIt ? @"Tieni la sinistra" : @"Keep left";
        else if ([modifier isEqualToString:@"slight right"]) base = isIt ? @"Tieni la destra" : @"Keep right";
        else if ([modifier isEqualToString:@"uturn"]) return isIt ? @"Fai inversione a U" : @"Make a U-turn";
        else base = isIt ? @"Svolta" : @"Turn";
    } else if ([type isEqualToString:@"roundabout"]) {
        base = isIt ? @"Alla rotonda prendi l'uscita" : @"At the roundabout take the exit";
    } else if ([type isEqualToString:@"fork"]) {
        if ([modifier isEqualToString:@"left"]) return isIt ? @"Al bivio tieni la sinistra" : @"Keep left at the fork";
        else return isIt ? @"Al bivio tieni la destra" : @"Keep right at the fork";
    } else if ([type isEqualToString:@"on ramp"] || [type isEqualToString:@"off ramp"]) {
        base = isIt ? @"Prendi l'uscita" : @"Take the exit";
    } else {
        base = isIt ? @"Continua" : @"Continue";
    }

    if (name && name.length > 0) {
        return isIt ? [NSString stringWithFormat:@"%@ su %@", base, name]
                    : [NSString stringWithFormat:@"%@ onto %@", base, name];
    }
    return base;
}

static NSString *EvaluateTrafficDescription(NSDictionary *leg) {
    BOOL isIt = [[LocalizationManager sharedManager] isItalian];
    NSString *smooth = isIt ? @"Scorrevole 🟢" : @"Smooth Flow 🟢";
    NSString *slow = isIt ? @"Rallentamenti 🟡" : @"Slowdowns 🟡";
    NSString *heavy = isIt ? @"Traffico intenso 🔴" : @"Heavy Traffic 🔴";

    NSDictionary *annotation = leg[@"annotation"];
    if (!annotation) return smooth;

    NSArray *speeds = annotation[@"speed"];
    if (![speeds isKindOfClass:[NSArray class]] || speeds.count == 0) {
        return smooth;
    }

    NSUInteger slowCount = 0;
    NSUInteger total = speeds.count;
    for (NSNumber *spd in speeds) {
        double val = [spd doubleValue];
        // Sotto i 15 km/h (circa 4.2 m/s) è considerato traffico lento/coda
        if (val < 4.2) {
            slowCount++;
        }
    }

    double slowRatio = (double)slowCount / (double)total;
    if (slowRatio > 0.30) {
        return heavy;
    } else if (slowRatio > 0.12) {
        return slow;
    } else {
        return smooth;
    }
}

- (NSArray<RouteInfo *> *)parseRoutesData:(NSData *)data
                               destination:(CLLocationCoordinate2D)destination
                                     title:(NSString *)title
                                     error:(NSError **)outError {
    NSError *jsonError = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (jsonError) {
        if (outError) *outError = jsonError;
        return nil;
    }

    NSString *code = json[@"code"];
    if (![code isEqualToString:@"Ok"]) {
        NSString *desc = [NSString stringWithFormat:@"OSRM code: %@", code ?: @"Sconosciuto"];
        if (outError) *outError = [NSError errorWithDomain:@"RoutingService" code:-2 userInfo:@{NSLocalizedDescriptionKey: desc}];
        return nil;
    }

    NSArray *rawRoutes = json[@"routes"];
    if (rawRoutes.count == 0) {
        if (outError) *outError = [NSError errorWithDomain:@"RoutingService" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Nessun percorso disponibile"}];
        return nil;
    }

    NSMutableArray<RouteInfo *> *results = [NSMutableArray array];

    for (NSUInteger rIdx = 0; rIdx < rawRoutes.count; rIdx++) {
        NSDictionary *rDict = rawRoutes[rIdx];
        CLLocationDistance totalDistance = [rDict[@"distance"] doubleValue];
        NSTimeInterval totalDuration = [rDict[@"duration"] doubleValue];

        // Filtro Deduplicazione: evita di mostrare due itinerari identici
        BOOL isDuplicate = NO;
        for (RouteInfo *existing in results) {
            if (fabs(existing.totalDistance - totalDistance) < 60.0 &&
                fabs(existing.totalDuration - totalDuration) < 25.0) {
                isDuplicate = YES;
                break;
            }
        }
        if (isDuplicate) {
            NSLog(@"[RoutingService] Scartato itinerario duplicato (distanza: %.0fm, tempo: %.0fs)", totalDistance, totalDuration);
            continue;
        }

        // 1. Geometria GeoJSON [lon, lat]
        NSDictionary *geometry = rDict[@"geometry"];
        NSArray *coordinates = geometry[@"coordinates"];
        NSUInteger count = coordinates.count;
        if (count == 0) continue;

        CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);
        for (NSUInteger i = 0; i < count; i++) {
            NSArray *pt = coordinates[i];
            coords[i] = CLLocationCoordinate2DMake([pt[1] doubleValue], [pt[0] doubleValue]);
        }

        MKPolyline *polyline = [MKPolyline polylineWithCoordinates:coords count:count];
        free(coords);

        // 2. Passaggi di manovra e calcolo strade principali
        NSMutableArray<ManeuverStep *> *steps = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSNumber *> *roadDistances = [NSMutableDictionary dictionary];
        NSString *trafficStatus = @"Scorrevole 🟢";

        NSArray *legs = rDict[@"legs"];
        if (legs.count > 0) {
            NSDictionary *firstLeg = legs[0];
            trafficStatus = EvaluateTrafficDescription(firstLeg);

            NSArray *rawSteps = firstLeg[@"steps"];
            for (NSDictionary *raw in rawSteps) {
                ManeuverStep *step = [[ManeuverStep alloc] init];
                step.distance = [raw[@"distance"] doubleValue];
                step.duration = [raw[@"duration"] doubleValue];
                step.streetName = raw[@"name"] ?: @"";

                if (step.streetName.length > 2) {
                    double currentDist = [roadDistances[step.streetName] doubleValue];
                    roadDistances[step.streetName] = @(currentDist + step.distance);
                }

                NSDictionary *maneuver = raw[@"maneuver"];
                step.type = maneuver[@"type"] ?: @"";
                step.modifier = maneuver[@"modifier"] ?: @"";
                NSArray *loc = maneuver[@"location"];
                if (loc.count >= 2) {
                    step.coordinate = CLLocationCoordinate2DMake([loc[1] doubleValue], [loc[0] doubleValue]);
                }
                step.instruction = FormatManeuverLocalized(step.type, step.modifier, step.streetName);
                [steps addObject:step];
            }
        }

        // Trova le 2 strade con percorrenza maggiore per il riassunto reale
        NSArray *sortedRoads = [roadDistances keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *obj1, NSNumber *obj2) {
            return [obj2 compare:obj1];
        }];

        NSString *summaryStr = nil;
        if (sortedRoads.count >= 2) {
            summaryStr = [NSString stringWithFormat:@"via %@ / %@", sortedRoads[0], sortedRoads[1]];
        } else if (sortedRoads.count == 1) {
            summaryStr = [NSString stringWithFormat:@"via %@", sortedRoads[0]];
        } else {
            summaryStr = (results.count == 0) ? @"Percorso principale" : [NSString stringWithFormat:@"Alternativa %lu", (unsigned long)results.count];
        }

        RouteInfo *info = [[RouteInfo alloc] init];
        info.polyline = polyline;
        info.steps = steps;
        info.totalDistance = totalDistance;
        info.totalDuration = totalDuration;
        info.destinationCoordinate = destination;
        info.destinationTitle = title ?: @"Destinazione";
        info.routeSummary = summaryStr;
        info.trafficDescription = trafficStatus;
        info.routeIndex = results.count;
        info.isPrimary = (results.count == 0);

        BOOL hasHwy = NO;
        BOOL hasToll = NO;
        for (ManeuverStep *st in steps) {
            NSString *lower = [st.streetName lowercaseString];
            if ([lower containsString:@"autostrada"] || [lower containsString:@"tangenziale"] ||
                [lower containsString:@"pedaggio"] || [lower containsString:@"toll"] ||
                [lower hasPrefix:@"a1"] || [lower hasPrefix:@"a4"] || [lower hasPrefix:@"a8"] ||
                [lower hasPrefix:@"a7"] || [lower hasPrefix:@"a9"] || [lower hasPrefix:@"a14"] ||
                [lower hasPrefix:@"a22"] || [lower hasPrefix:@"a35"]) {
                hasHwy = YES;
                hasToll = YES;
            }
        }
        info.hasHighway = hasHwy;
        info.hasToll = hasToll;
        [info updateTripCosts];

        [results addObject:info];
    }

    [self reindexAndClassifyRoutes:results];
    return results;
}

- (void)appendUniqueRoute:(RouteInfo *)newRoute toRoutes:(NSMutableArray<RouteInfo *> *)routes {
    if (!newRoute || !newRoute.polyline) return;
    if (routes.count == 0) {
        [routes addObject:newRoute];
        return;
    }
    RouteInfo *primary = routes[0];
    // Scarta se deviazione eccessiva (> 1.7x tempo del percorso primario)
    if (newRoute.totalDuration > primary.totalDuration * 1.75) {
        return;
    }
    for (RouteInfo *existing in routes) {
        if (fabs(existing.totalDistance - newRoute.totalDistance) < 250.0 &&
            fabs(existing.totalDuration - newRoute.totalDuration) < 120.0) {
            return; // Duplicato
        }
    }
    [routes addObject:newRoute];
}

- (void)reindexAndClassifyRoutes:(NSMutableArray<RouteInfo *> *)results
                      avoidTolls:(BOOL)avoidTolls
                   avoidHighways:(BOOL)avoidHighways {
    if (results.count == 0) return;

    // Ordina per rispetto delle preferenze utente, poi per durata crescente
    [results sortUsingComparator:^NSComparisonResult(RouteInfo *r1, RouteInfo *r2) {
        if (avoidTolls) {
            if (!r1.hasToll && r2.hasToll) return NSOrderedAscending;
            if (r1.hasToll && !r2.hasToll) return NSOrderedDescending;
        }
        if (avoidHighways) {
            if (!r1.hasHighway && r2.hasHighway) return NSOrderedAscending;
            if (r1.hasHighway && !r2.hasHighway) return NSOrderedDescending;
        }
        if (r1.totalDuration < r2.totalDuration) return NSOrderedAscending;
        if (r1.totalDuration > r2.totalDuration) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSTimeInterval minDuration = DBL_MAX;
    CLLocationDistance minDistance = DBL_MAX;
    for (RouteInfo *r in results) {
        if (r.totalDuration < minDuration) minDuration = r.totalDuration;
        if (r.totalDistance < minDistance) minDistance = r.totalDistance;
    }

    RouteInfo *primary = results[0];
    for (NSUInteger i = 0; i < results.count; i++) {
        RouteInfo *r = results[i];
        r.routeIndex = i;
        r.isPrimary = (i == 0);

        BOOL isIt = [[LocalizationManager sharedManager] isItalian];

        // Assegna badge strategico
        if (avoidTolls && !r.hasToll) {
            r.badgeTitle = NLString(@"BADGE_NO_TOLLS", @"🌿 No Pedaggio");
        } else if (avoidHighways && !r.hasHighway) {
            r.badgeTitle = NLString(@"BADGE_NO_HIGHWAYS", @"🍃 No Autostrada");
        } else if (fabs(r.totalDuration - minDuration) < 15.0 && fabs(r.totalDistance - minDistance) < 100.0) {
            r.badgeTitle = NLString(@"BADGE_OPTIMAL", @"⭐ Ottimale");
        } else if (fabs(r.totalDuration - minDuration) < 15.0) {
            r.badgeTitle = NLString(@"BADGE_FASTEST", @"🚀 Più Veloce");
        } else if (fabs(r.totalDistance - minDistance) < 100.0) {
            r.badgeTitle = NLString(@"BADGE_SHORTEST", @"🍃 Più Breve");
        } else {
            r.badgeTitle = (i == 1) ? NLString(@"BADGE_ALTERNATIVE", @"⚖️ Alternativa") : NLString(@"BADGE_SCENIC", @"🍃 Panoramica");
        }

        // Assegna delta
        if (i == 0) {
            r.deltaDescription = NLString(@"RECOMMENDED", @"Consigliato");
        } else {
            int deltaMins = (int)round((r.totalDuration - primary.totalDuration) / 60.0);
            double deltaKm = (r.totalDistance - primary.totalDistance) / 1000.0;

            NSString *sameTimeStr = isIt ? @"Stesso tempo" : @"Same time";
            NSString *sameDistStr = isIt ? @"Stessa dist." : @"Same dist.";

            NSString *timeDelta = (deltaMins == 0) ? sameTimeStr : (deltaMins > 0 ? [NSString stringWithFormat:@"+%d min", deltaMins] : [NSString stringWithFormat:@"%d min", deltaMins]);
            NSString *distDelta = (fabs(deltaKm) < 0.1) ? sameDistStr : (deltaKm > 0 ? [NSString stringWithFormat:@"+%.1f km", deltaKm] : [NSString stringWithFormat:@"%.1f km", deltaKm]);

            r.deltaDescription = [NSString stringWithFormat:@"%@ • %@", timeDelta, distDelta];
        }
    }
}

- (void)reindexAndClassifyRoutes:(NSMutableArray<RouteInfo *> *)results {
    [self reindexAndClassifyRoutes:results avoidTolls:NO avoidHighways:NO];
}

- (void)enrichWithAlternativeCorridors:(NSMutableArray<RouteInfo *> *)routes
                                 start:(CLLocationCoordinate2D)start
                           destination:(CLLocationCoordinate2D)destination
                                 title:(NSString *)title
                           offsetRatio:(double)offsetRatio
                            completion:(void (^)(NSArray<RouteInfo *> *finalRoutes))done {
    // Non inventiamo waypoint perpendicolari arbitrari in mezzo ai campi/boschi
    // che costringevano il motore a deviazioni illogiche.
    // Usiamo unicamente le alternative reali fornite dal grafo stradale OSRM/Valhalla.
    [self reindexAndClassifyRoutes:routes];
    if (done) done(routes);
}

static NSArray<NSValue *> *DecodePolyline6(NSString *encoded) {
    if (!encoded || encoded.length == 0) return @[];
    NSMutableArray<NSValue *> *coordsArray = [NSMutableArray array];
    const char *bytes = [encoded UTF8String];
    NSUInteger len = strlen(bytes);
    NSUInteger idx = 0;
    int lat = 0;
    int lng = 0;
    double precision = 1e6;

    while (idx < len) {
        int result = 0;
        int shift = 0;
        while (idx < len) {
            int b = bytes[idx++] - 63;
            result |= (b & 0x1f) << shift;
            shift += 5;
            if (b < 0x20) break;
        }
        int dlat = ((result & 1) ? ~(result >> 1) : (result >> 1));
        lat += dlat;

        result = 0;
        shift = 0;
        while (idx < len) {
            int b = bytes[idx++] - 63;
            result |= (b & 0x1f) << shift;
            shift += 5;
            if (b < 0x20) break;
        }
        int dlng = ((result & 1) ? ~(result >> 1) : (result >> 1));
        lng += dlng;

        CLLocationCoordinate2D coord = CLLocationCoordinate2DMake((double)lat / precision, (double)lng / precision);
        [coordsArray addObject:[NSValue valueWithBytes:&coord objCType:@encode(CLLocationCoordinate2D)]];
    }
    return coordsArray;
}

static MKPolyline *PolylineFromCoords(NSArray<NSValue *> *coordsArray) {
    NSUInteger count = coordsArray.count;
    if (count == 0) return nil;
    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);
    for (NSUInteger i = 0; i < count; i++) {
        [coordsArray[i] getValue:&coords[i]];
    }
    MKPolyline *polyline = [MKPolyline polylineWithCoordinates:coords count:count];
    free(coords);
    return polyline;
}

- (RouteInfo *)routeFromValhallaTrip:(NSDictionary *)trip
                          destination:(CLLocationCoordinate2D)destination
                                title:(NSString *)title {
    if (![trip isKindOfClass:[NSDictionary class]]) return nil;

    NSDictionary *summary = trip[@"summary"];
    NSArray *legs = trip[@"legs"];
    if (![legs isKindOfClass:[NSArray class]] || legs.count == 0) return nil;

    NSDictionary *leg = legs[0];
    NSString *shape = leg[@"shape"];
    NSArray<NSValue *> *decodedCoords = DecodePolyline6(shape);
    if (decodedCoords.count == 0) return nil;

    MKPolyline *polyline = PolylineFromCoords(decodedCoords);

    double lengthKm = [summary[@"length"] doubleValue];
    double totalDistance = lengthKm * 1000.0;
    double totalDuration = [summary[@"time"] doubleValue];
    BOOL hasToll = [summary[@"has_toll"] boolValue];
    BOOL hasHighway = [summary[@"has_highway"] boolValue];

    NSMutableArray<ManeuverStep *> *steps = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *roadDistances = [NSMutableDictionary dictionary];

    NSArray *rawManeuvers = leg[@"maneuvers"];
    for (NSDictionary *m in rawManeuvers) {
        ManeuverStep *step = [[ManeuverStep alloc] init];
        step.distance = [m[@"length"] doubleValue] * 1000.0;
        step.duration = [m[@"time"] doubleValue];
        step.instruction = m[@"instruction"] ?: @"";

        NSArray *names = m[@"street_names"];
        if ([names isKindOfClass:[NSArray class]] && names.count > 0) {
            step.streetName = names[0];
        } else {
            step.streetName = @"";
        }

        if (step.streetName.length > 2) {
            double cur = [roadDistances[step.streetName] doubleValue];
            roadDistances[step.streetName] = @(cur + step.distance);
        }

        NSInteger shapeIdx = [m[@"begin_shape_index"] integerValue];
        if (shapeIdx >= 0 && shapeIdx < (NSInteger)decodedCoords.count) {
            CLLocationCoordinate2D c;
            [decodedCoords[shapeIdx] getValue:&c];
            step.coordinate = c;
        }

        NSInteger mType = [m[@"type"] integerValue];
        if (mType == 4 || mType == 5 || mType == 6) {
            step.type = @"arrive";
        } else if (mType == 1 || mType == 2 || mType == 3) {
            step.type = @"depart";
        } else if (mType == 26 || mType == 27) {
            step.type = @"roundabout";
        } else if (mType == 14 || mType == 15 || mType == 16) {
            step.type = @"turn";
            step.modifier = @"left";
        } else if (mType == 9 || mType == 10 || mType == 11) {
            step.type = @"turn";
            step.modifier = @"right";
        } else if (mType == 12 || mType == 13) {
            step.type = @"turn";
            step.modifier = @"uturn";
        } else {
            step.type = @"continue";
        }

        [steps addObject:step];
    }

    NSArray *sortedRoads = [roadDistances keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *o1, NSNumber *o2) {
        return [o2 compare:o1];
    }];

    NSString *summaryStr = nil;
    if (sortedRoads.count >= 2) {
        summaryStr = [NSString stringWithFormat:@"via %@ / %@", sortedRoads[0], sortedRoads[1]];
    } else if (sortedRoads.count == 1) {
        summaryStr = [NSString stringWithFormat:@"via %@", sortedRoads[0]];
    } else {
        summaryStr = hasToll ? @"Percorso Autostradale" : @"Percorso Statale";
    }

    RouteInfo *info = [[RouteInfo alloc] init];
    info.polyline = polyline;
    info.steps = steps;
    info.totalDistance = totalDistance;
    info.totalDuration = totalDuration;
    info.destinationCoordinate = destination;
    info.destinationTitle = title ?: @"Destinazione";
    info.routeSummary = summaryStr;
    info.trafficDescription = @"Scorrevole 🟢";
    info.hasToll = hasToll;
    info.hasHighway = hasHighway;
    [info updateTripCosts];

    return info;
}

- (NSArray<RouteInfo *> *)parseValhallaResponseData:(NSData *)data
                                        destination:(CLLocationCoordinate2D)destination
                                              title:(NSString *)title
                                         avoidTolls:(BOOL)avoidTolls
                                      avoidHighways:(BOOL)avoidHighways
                                              error:(NSError **)outError {
    NSError *jsonError = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
        if (outError) *outError = jsonError ?: [NSError errorWithDomain:@"RoutingService" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Risposta Valhalla non valida"}];
        return nil;
    }

    NSMutableArray<RouteInfo *> *results = [NSMutableArray array];

    NSDictionary *primaryTrip = json[@"trip"];
    RouteInfo *r0 = [self routeFromValhallaTrip:primaryTrip destination:destination title:title];
    if (r0) {
        [results addObject:r0];
    }

    NSArray *alts = json[@"alternates"];
    if ([alts isKindOfClass:[NSArray class]]) {
        for (NSDictionary *alt in alts) {
            NSDictionary *altTrip = alt[@"trip"];
            RouteInfo *rAlt = [self routeFromValhallaTrip:altTrip destination:destination title:title];
            if (rAlt) {
                [self appendUniqueRoute:rAlt toRoutes:results];
            }
        }
    }

    if (results.count == 0) {
        if (outError) *outError = [NSError errorWithDomain:@"RoutingService" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Nessun percorso restituito da Valhalla"}];
        return nil;
    }

    [self reindexAndClassifyRoutes:results avoidTolls:avoidTolls avoidHighways:avoidHighways];
    return results;
}

- (void)calculateRoutesFrom:(CLLocationCoordinate2D)start
                         to:(CLLocationCoordinate2D)destination
           destinationTitle:(NSString *)title
                 avoidTolls:(BOOL)avoidTolls
              avoidHighways:(BOOL)avoidHighways
             corridorOffset:(double)offsetRatio
                 completion:(RoutesCompletionBlock)completion {

    NSLog(@"[RoutingService] Calcolo itinerario da (%.4f, %.4f) a (%.4f, %.4f) [Pedaggi: %@, Autostrade: %@]",
          start.latitude, start.longitude, destination.latitude, destination.longitude,
          avoidTolls ? @"NO" : @"SI", avoidHighways ? @"NO" : @"SI");

    __weak RoutingService *weakSelf = self;

    // Se l'utente ha richiesto esplicitamente di evitare pedaggi o autostrade, usiamo il motore avanzato Valhalla
    if (avoidTolls || avoidHighways) {
        NSURL *url = [NSURL URLWithString:@"https://valhalla1.openstreetmap.de/route"];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"POST";
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

        BOOL isIt = [[LocalizationManager sharedManager] isItalian];
        NSDictionary *body = @{
            @"locations": @[
                @{ @"lat": @(start.latitude), @"lon": @(start.longitude) },
                @{ @"lat": @(destination.latitude), @"lon": @(destination.longitude) }
            ],
            @"costing": @"auto",
            @"costing_options": @{
                @"auto": @{
                    @"use_highways": avoidHighways ? @(0.0) : @(1.0),
                    @"use_tolls": avoidTolls ? @(0.0) : @(1.0),
                    @"toll_booth_penalty": avoidTolls ? @(2000.0) : @(0.0)
                }
            },
            @"alternates": @(3),
            @"directions_options": @{
                @"units": @"kilometers",
                @"language": isIt ? @"it-IT" : @"en-US"
            }
        };

        NSError *encErr = nil;
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&encErr];

        NSURLSessionDataTask *vTask = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (!err && data) {
                NSError *parseErr = nil;
                NSArray<RouteInfo *> *valhallaRoutes = [weakSelf parseValhallaResponseData:data destination:destination title:title avoidTolls:avoidTolls avoidHighways:avoidHighways error:&parseErr];
                if (valhallaRoutes.count > 0) {
                    NSLog(@"[RoutingService] Valhalla ha calcolato %lu itinerari con successo", (unsigned long)valhallaRoutes.count);
                    [[TollGuruService sharedService] requestTollForRoutes:valhallaRoutes from:start to:destination];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(valhallaRoutes, nil);
                    });
                    return;
                }
                NSLog(@"[RoutingService] Valhalla parse fallito: %@, tento fallback OSRM", parseErr);
            } else {
                NSLog(@"[RoutingService] Valhalla network err: %@, tento fallback OSRM", err);
            }

            // Fallback su OSRM standard in caso di errore Valhalla
            [weakSelf calculateRoutesFrom:start to:destination destinationTitle:title corridorOffset:offsetRatio completion:completion];
        }];
        [vTask resume];
        return;
    }

    // Modalità standard: OSRM primario con corridoi alternativi
    [self calculateRoutesFrom:start to:destination destinationTitle:title corridorOffset:offsetRatio completion:completion];
}

- (void)calculateRoutesFrom:(CLLocationCoordinate2D)start
                         to:(CLLocationCoordinate2D)destination
            destinationTitle:(NSString *)title
                  completion:(RoutesCompletionBlock)completion {
    [self calculateRoutesFrom:start to:destination destinationTitle:title avoidTolls:NO avoidHighways:NO corridorOffset:0.22 completion:completion];
}

- (void)calculateRoutesFrom:(CLLocationCoordinate2D)start
                         to:(CLLocationCoordinate2D)destination
            destinationTitle:(NSString *)title
             corridorOffset:(double)offsetRatio
                  completion:(RoutesCompletionBlock)completion {

    NSString *coordsParam = [NSString stringWithFormat:@"%.6f,%.6f;%.6f,%.6f",
                             start.longitude, start.latitude,
                             destination.longitude, destination.latitude];

    NSString *primaryUrlStr = [NSString stringWithFormat:
                              @"http://router.project-osrm.org/route/v1/driving/%@?overview=full&geometries=geojson&steps=true&alternatives=3&annotations=true",
                              coordsParam];

    NSString *fallbackUrlStr = [NSString stringWithFormat:
                               @"http://routing.openstreetmap.de/routed-car/route/v1/driving/%@?overview=full&geometries=geojson&steps=true&alternatives=3&annotations=true",
                               coordsParam];

    NSLog(@"[RoutingService] Richiesta itinerari OSRM da (%.4f, %.4f) a (%.4f, %.4f) con offset %.2f",
          start.latitude, start.longitude, destination.latitude, destination.longitude, offsetRatio);

    __weak RoutingService *weakSelf = self;
    NSURL *primaryUrl = [NSURL URLWithString:primaryUrlStr];
    NSURLSessionDataTask *task1 = [self.session dataTaskWithURL:primaryUrl completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            NSError *parseErr = nil;
            NSArray<RouteInfo *> *parsed = [weakSelf parseRoutesData:data destination:destination title:title error:&parseErr];
            if (parsed.count > 0) {
                NSMutableArray<RouteInfo *> *routesMut = [parsed mutableCopy];
                [weakSelf enrichWithAlternativeCorridors:routesMut start:start destination:destination title:title offsetRatio:offsetRatio completion:^(NSArray<RouteInfo *> *finalRoutes) {
                    NSLog(@"[RoutingService] Itinerari finali OSRM calcolati: %lu percorsi", (unsigned long)finalRoutes.count);
                    [[TollGuruService sharedService] requestTollForRoutes:finalRoutes from:start to:destination];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(finalRoutes, nil);
                    });
                }];
                return;
            }
            NSLog(@"[RoutingService] Server primario OSRM ha restituito errore di parsing: %@", parseErr);
        } else {
            NSLog(@"[RoutingService] Errore server primario OSRM: %@, tento server secondario...", error.localizedDescription);
        }

        // Tentativo su server secondario (OSM DE router)
        NSURL *fallbackUrl = [NSURL URLWithString:fallbackUrlStr];
        NSURLSessionDataTask *task2 = [weakSelf.session dataTaskWithURL:fallbackUrl completionHandler:^(NSData *data2, NSURLResponse *resp2, NSError *err2) {
            if (!err2 && data2) {
                NSError *parseErr2 = nil;
                NSArray<RouteInfo *> *parsed2 = [weakSelf parseRoutesData:data2 destination:destination title:title error:&parseErr2];
                if (parsed2.count > 0) {
                    NSMutableArray<RouteInfo *> *routesMut2 = [parsed2 mutableCopy];
                    [weakSelf enrichWithAlternativeCorridors:routesMut2 start:start destination:destination title:title offsetRatio:offsetRatio completion:^(NSArray<RouteInfo *> *finalRoutes2) {
                        NSLog(@"[RoutingService] Itinerari finali secondario: %lu percorsi", (unsigned long)finalRoutes2.count);
                        [[TollGuruService sharedService] requestTollForRoutes:finalRoutes2 from:start to:destination];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (completion) completion(finalRoutes2, nil);
                        });
                    }];
                    return;
                }
                NSLog(@"[RoutingService] Server secondario errore parsing: %@", parseErr2);
            } else {
                NSLog(@"[RoutingService] Errore anche su server secondario: %@", err2.localizedDescription);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, err2 ?: error ?: [NSError errorWithDomain:@"RoutingService" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Nessun itinerario trovato"}]);
                }
            });
        }];
        [task2 resume];
    }];
    [task1 resume];
}

- (void)calculateRouteFrom:(CLLocationCoordinate2D)start
                        to:(CLLocationCoordinate2D)destination
               destinationTitle:(NSString *)title
                completion:(RouteCompletionBlock)completion {
    [self calculateRoutesFrom:start to:destination destinationTitle:title completion:^(NSArray<RouteInfo *> *routes, NSError *error) {
        if (error || routes.count == 0) {
            if (completion) completion(nil, error);
        } else {
            if (completion) completion(routes[0], nil);
        }
    }];
}

@end

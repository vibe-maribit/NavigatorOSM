#import "RoutingService.h"

@implementation ManeuverStep
@end

@implementation RouteInfo
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

static NSString *FormatManeuverItalian(NSString *type, NSString *modifier, NSString *name) {
    NSString *base = @"";
    if ([type isEqualToString:@"depart"]) {
        base = @"Parti verso";
    } else if ([type isEqualToString:@"arrive"]) {
        base = @"Destinazione raggiunta";
    } else if ([type isEqualToString:@"turn"]) {
        if ([modifier isEqualToString:@"left"]) base = @"Gira a sinistra";
        else if ([modifier isEqualToString:@"right"]) base = @"Gira a destra";
        else if ([modifier isEqualToString:@"sharp left"]) base = @"Svolta stretta a sinistra";
        else if ([modifier isEqualToString:@"sharp right"]) base = @"Svolta stretta a destra";
        else if ([modifier isEqualToString:@"slight left"]) base = @"Tieni la sinistra";
        else if ([modifier isEqualToString:@"slight right"]) base = @"Tieni la destra";
        else if ([modifier isEqualToString:@"uturn"]) base = @"Fai inversione a U";
        else base = @"Svolta";
    } else if ([type isEqualToString:@"roundabout"]) {
        base = @"Alla rotonda prendi l'uscita";
    } else if ([type isEqualToString:@"fork"]) {
        if ([modifier isEqualToString:@"left"]) base = @"Al bivio tieni la sinistra";
        else base = @"Al bivio tieni la destra";
    } else if ([type isEqualToString:@"on ramp"] || [type isEqualToString:@"off ramp"]) {
        base = @"Prendi l'uscita";
    } else {
        base = @"Continua";
    }

    if (name && name.length > 0) {
        return [NSString stringWithFormat:@"%@ su %@", base, name];
    }
    return base;
}

static NSString *EvaluateTrafficDescription(NSDictionary *leg) {
    NSDictionary *annotation = leg[@"annotation"];
    if (!annotation) return @"Scorrevole 🟢";

    NSArray *speeds = annotation[@"speed"];
    if (![speeds isKindOfClass:[NSArray class]] || speeds.count == 0) {
        return @"Scorrevole 🟢";
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
        return @"Traffico intenso 🔴";
    } else if (slowRatio > 0.12) {
        return @"Rallentamenti 🟡";
    } else {
        return @"Scorrevole 🟢";
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
                step.instruction = FormatManeuverItalian(step.type, step.modifier, step.streetName);
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

- (void)reindexAndClassifyRoutes:(NSMutableArray<RouteInfo *> *)results {
    if (results.count == 0) return;

    // Ordina per durata crescente (il più veloce per primo)
    [results sortUsingComparator:^NSComparisonResult(RouteInfo *r1, RouteInfo *r2) {
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

        // Assegna badge strategico
        if (fabs(r.totalDuration - minDuration) < 15.0 && fabs(r.totalDistance - minDistance) < 100.0) {
            r.badgeTitle = @"⭐ Ottimale";
        } else if (fabs(r.totalDuration - minDuration) < 15.0) {
            r.badgeTitle = @"🚀 Più Veloce";
        } else if (fabs(r.totalDistance - minDistance) < 100.0) {
            r.badgeTitle = @"🍃 Più Breve";
        } else {
            r.badgeTitle = (i == 1) ? @"⚖️ Alternativa" : @"🍃 Panoramica";
        }

        // Assegna delta
        if (i == 0) {
            r.deltaDescription = @"Consigliato";
        } else {
            int deltaMins = (int)round((r.totalDuration - primary.totalDuration) / 60.0);
            double deltaKm = (r.totalDistance - primary.totalDistance) / 1000.0;

            NSString *timeDelta = (deltaMins == 0) ? @"Stesso tempo" : (deltaMins > 0 ? [NSString stringWithFormat:@"+%d min", deltaMins] : [NSString stringWithFormat:@"%d min", deltaMins]);
            NSString *distDelta = (fabs(deltaKm) < 0.1) ? @"Stessa dist." : (deltaKm > 0 ? [NSString stringWithFormat:@"+%.1f km", deltaKm] : [NSString stringWithFormat:@"%.1f km", deltaKm]);

            r.deltaDescription = [NSString stringWithFormat:@"%@ • %@", timeDelta, distDelta];
        }
    }
}

- (void)enrichWithAlternativeCorridors:(NSMutableArray<RouteInfo *> *)routes
                                 start:(CLLocationCoordinate2D)start
                           destination:(CLLocationCoordinate2D)destination
                                 title:(NSString *)title
                            completion:(void (^)(NSArray<RouteInfo *> *finalRoutes))done {
    // Se abbiamo già 3 o più itinerari distinti, completiamo subito
    if (routes.count >= 3) {
        done(routes);
        return;
    }

    double dLat = destination.latitude - start.latitude;
    double dLon = destination.longitude - start.longitude;
    double len = sqrt(dLat * dLat + dLon * dLon);

    // Se la distanza lineare è minore di circa 15 km, non ha senso cercare corridoi autostradali alternativi
    if (len < 0.15) {
        done(routes);
        return;
    }

    double midLat = (start.latitude + destination.latitude) / 2.0;
    double midLon = (start.longitude + destination.longitude) / 2.0;

    // Vettore perpendicolare normalizzato
    double pLat = dLon / len;
    double pLon = -dLat / len;

    // Due corridoi laterali simmetrici (22% della distanza totale)
    double offset = len * 0.22;
    CLLocationCoordinate2D via1 = CLLocationCoordinate2DMake(midLat + pLat * offset, midLon + pLon * offset);
    CLLocationCoordinate2D via2 = CLLocationCoordinate2DMake(midLat - pLat * offset, midLon - pLon * offset);

    dispatch_group_t group = dispatch_group_create();

    // Query Corridoio Laterale 1
    dispatch_group_enter(group);
    NSString *via1UrlStr = [NSString stringWithFormat:
                            @"http://router.project-osrm.org/route/v1/driving/%.6f,%.6f;%.6f,%.6f;%.6f,%.6f?overview=full&geometries=geojson&steps=true&annotations=true",
                            start.longitude, start.latitude,
                            via1.longitude, via1.latitude,
                            destination.longitude, destination.latitude];
    NSURLSessionDataTask *t1 = [self.session dataTaskWithURL:[NSURL URLWithString:via1UrlStr] completionHandler:^(NSData *d1, NSURLResponse *r1, NSError *e1) {
        if (!e1 && d1) {
            NSArray<RouteInfo *> *extra1 = [self parseRoutesData:d1 destination:destination title:title error:nil];
            if (extra1.count > 0) {
                @synchronized (routes) {
                    [self appendUniqueRoute:extra1[0] toRoutes:routes];
                }
            }
        }
        dispatch_group_leave(group);
    }];
    [t1 resume];

    // Query Corridoio Laterale 2
    dispatch_group_enter(group);
    NSString *via2UrlStr = [NSString stringWithFormat:
                            @"http://router.project-osrm.org/route/v1/driving/%.6f,%.6f;%.6f,%.6f;%.6f,%.6f?overview=full&geometries=geojson&steps=true&annotations=true",
                            start.longitude, start.latitude,
                            via2.longitude, via2.latitude,
                            destination.longitude, destination.latitude];
    NSURLSessionDataTask *t2 = [self.session dataTaskWithURL:[NSURL URLWithString:via2UrlStr] completionHandler:^(NSData *d2, NSURLResponse *r2, NSError *e2) {
        if (!e2 && d2) {
            NSArray<RouteInfo *> *extra2 = [self parseRoutesData:d2 destination:destination title:title error:nil];
            if (extra2.count > 0) {
                @synchronized (routes) {
                    [self appendUniqueRoute:extra2[0] toRoutes:routes];
                }
            }
        }
        dispatch_group_leave(group);
    }];
    [t2 resume];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self reindexAndClassifyRoutes:routes];
        done(routes);
    });
}

- (void)calculateRoutesFrom:(CLLocationCoordinate2D)start
                         to:(CLLocationCoordinate2D)destination
            destinationTitle:(NSString *)title
                  completion:(RoutesCompletionBlock)completion {

    NSString *coordsParam = [NSString stringWithFormat:@"%.6f,%.6f;%.6f,%.6f",
                             start.longitude, start.latitude,
                             destination.longitude, destination.latitude];

    NSString *primaryUrlStr = [NSString stringWithFormat:
                              @"http://router.project-osrm.org/route/v1/driving/%@?overview=full&geometries=geojson&steps=true&alternatives=true&annotations=true",
                              coordsParam];

    NSString *fallbackUrlStr = [NSString stringWithFormat:
                               @"http://routing.openstreetmap.de/routed-car/route/v1/driving/%@?overview=full&geometries=geojson&steps=true&alternatives=true&annotations=true",
                               coordsParam];

    NSLog(@"[RoutingService] Richiesta itinerari da (%.4f, %.4f) a (%.4f, %.4f)",
          start.latitude, start.longitude, destination.latitude, destination.longitude);

    __weak RoutingService *weakSelf = self;
    NSURL *primaryUrl = [NSURL URLWithString:primaryUrlStr];
    NSURLSessionDataTask *task1 = [self.session dataTaskWithURL:primaryUrl completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            NSError *parseErr = nil;
            NSArray<RouteInfo *> *parsed = [weakSelf parseRoutesData:data destination:destination title:title error:&parseErr];
            if (parsed.count > 0) {
                NSMutableArray<RouteInfo *> *routesMut = [parsed mutableCopy];
                [weakSelf enrichWithAlternativeCorridors:routesMut start:start destination:destination title:title completion:^(NSArray<RouteInfo *> *finalRoutes) {
                    NSLog(@"[RoutingService] Itinerari finali calcolati: %lu percorsi", (unsigned long)finalRoutes.count);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(finalRoutes, nil);
                    });
                }];
                return;
            }
            NSLog(@"[RoutingService] Server primario ha restituito errore di parsing: %@", parseErr);
        } else {
            NSLog(@"[RoutingService] Errore server primario: %@, tento server secondario...", error.localizedDescription);
        }

        // Tentativo su server secondario (OSM DE router)
        NSURL *fallbackUrl = [NSURL URLWithString:fallbackUrlStr];
        NSURLSessionDataTask *task2 = [weakSelf.session dataTaskWithURL:fallbackUrl completionHandler:^(NSData *data2, NSURLResponse *resp2, NSError *err2) {
            if (!err2 && data2) {
                NSError *parseErr2 = nil;
                NSArray<RouteInfo *> *parsed2 = [weakSelf parseRoutesData:data2 destination:destination title:title error:&parseErr2];
                if (parsed2.count > 0) {
                    NSMutableArray<RouteInfo *> *routesMut2 = [parsed2 mutableCopy];
                    [weakSelf enrichWithAlternativeCorridors:routesMut2 start:start destination:destination title:title completion:^(NSArray<RouteInfo *> *finalRoutes2) {
                        NSLog(@"[RoutingService] Itinerari finali secondario: %lu percorsi", (unsigned long)finalRoutes2.count);
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

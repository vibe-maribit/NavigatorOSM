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

- (void)calculateRoutesFrom:(CLLocationCoordinate2D)start
                         to:(CLLocationCoordinate2D)destination
            destinationTitle:(NSString *)title
                 completion:(RoutesCompletionBlock)completion {

    // OSRM API con alternative=true e annotations=true per analisi traffico/velocità
    NSString *urlString = [NSString stringWithFormat:
                           @"https://router.project-osrm.org/route/v1/driving/%.6f,%.6f;%.6f,%.6f?overview=full&geometries=geojson&steps=true&alternatives=true&annotations=true",
                           start.longitude, start.latitude,
                           destination.longitude, destination.latitude];

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"RoutingService" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"URL non valido"}]);
        }
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || ![json[@"code"] isEqualToString:@"Ok"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, jsonError ?: [NSError errorWithDomain:@"RoutingService" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Nessun percorso trovato"}]);
            });
            return;
        }

        NSArray *rawRoutes = json[@"routes"];
        if (rawRoutes.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, [NSError errorWithDomain:@"RoutingService" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Nessun percorso disponibile"}]);
            });
            return;
        }

        NSMutableArray<RouteInfo *> *results = [NSMutableArray array];

        for (NSUInteger rIdx = 0; rIdx < rawRoutes.count; rIdx++) {
            NSDictionary *rDict = rawRoutes[rIdx];
            CLLocationDistance totalDistance = [rDict[@"distance"] doubleValue];
            NSTimeInterval totalDuration = [rDict[@"duration"] doubleValue];

            // 1. Geometria GeoJSON [lon, lat]
            NSDictionary *geometry = rDict[@"geometry"];
            NSArray *coordinates = geometry[@"coordinates"];
            NSUInteger count = coordinates.count;
            CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);

            for (NSUInteger i = 0; i < count; i++) {
                NSArray *pt = coordinates[i];
                coords[i] = CLLocationCoordinate2DMake([pt[1] doubleValue], [pt[0] doubleValue]);
            }

            MKPolyline *polyline = [MKPolyline polylineWithCoordinates:coords count:count];
            free(coords);

            // 2. Passaggi di manovra e sintesi strade
            NSMutableArray<ManeuverStep *> *steps = [NSMutableArray array];
            NSString *summaryStr = nil;
            NSString *trafficStatus = @"Scorrevole 🟢";

            NSArray *legs = rDict[@"legs"];
            if (legs.count > 0) {
                NSDictionary *firstLeg = legs[0];
                summaryStr = firstLeg[@"summary"];
                trafficStatus = EvaluateTrafficDescription(firstLeg);

                NSArray *rawSteps = firstLeg[@"steps"];
                for (NSDictionary *raw in rawSteps) {
                    ManeuverStep *step = [[ManeuverStep alloc] init];
                    step.distance = [raw[@"distance"] doubleValue];
                    step.duration = [raw[@"duration"] doubleValue];
                    step.streetName = raw[@"name"] ?: @"";

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

            if (!summaryStr || summaryStr.length == 0) {
                summaryStr = (rIdx == 0) ? @"Percorso più veloce" : [NSString stringWithFormat:@"Itinerario alternativo %lu", (unsigned long)rIdx];
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
            info.routeIndex = rIdx;
            info.isPrimary = (rIdx == 0);

            [results addObject:info];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(results, nil);
        });
    }];
    [task resume];
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

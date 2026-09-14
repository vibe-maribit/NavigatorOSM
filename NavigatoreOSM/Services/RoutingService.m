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
        base = @"Alla rotonda";
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

- (void)calculateRouteFrom:(CLLocationCoordinate2D)start
                        to:(CLLocationCoordinate2D)destination
               destinationTitle:(NSString *)title
                completion:(RouteCompletionBlock)completion {
    
    // OSRM richiede lon,lat;lon,lat
    NSString *urlString = [NSString stringWithFormat:
                           @"https://router.project-osrm.org/route/v1/driving/%.6f,%.6f;%.6f,%.6f?overview=full&geometries=geojson&steps=true",
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

        NSArray *routes = json[@"routes"];
        if (routes.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, [NSError errorWithDomain:@"RoutingService" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Nessun percorso disponibile"}]);
            });
            return;
        }

        NSDictionary *firstRoute = routes[0];
        CLLocationDistance totalDistance = [firstRoute[@"distance"] doubleValue];
        NSTimeInterval totalDuration = [firstRoute[@"duration"] doubleValue];

        // 1. Decodifica la geometria (GeoJSON linestring: [lon, lat])
        NSDictionary *geometry = firstRoute[@"geometry"];
        NSArray *coordinates = geometry[@"coordinates"];
        NSUInteger count = coordinates.count;
        CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);

        for (NSUInteger i = 0; i < count; i++) {
            NSArray *pt = coordinates[i];
            coords[i] = CLLocationCoordinate2DMake([pt[1] doubleValue], [pt[0] doubleValue]);
        }

        MKPolyline *polyline = [MKPolyline polylineWithCoordinates:coords count:count];
        free(coords);

        // 2. Decodifica i passaggi di manovra
        NSMutableArray<ManeuverStep *> *steps = [NSMutableArray array];
        NSArray *legs = firstRoute[@"legs"];
        if (legs.count > 0) {
            NSArray *rawSteps = legs[0][@"steps"];
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

        RouteInfo *info = [[RouteInfo alloc] init];
        info.polyline = polyline;
        info.steps = steps;
        info.totalDistance = totalDistance;
        info.totalDuration = totalDuration;
        info.destinationCoordinate = destination;
        info.destinationTitle = title ?: @"Destinazione";

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(info, nil);
        });
    }];
    [task resume];
}

@end

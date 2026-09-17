#import "SpeedCameraService.h"
#import "LocalizationManager.h"
#import "RoutingService.h"

@implementation SpeedCamera

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeDouble:self.coordinate.latitude forKey:@"lat"];
    [coder encodeDouble:self.coordinate.longitude forKey:@"lon"];
    [coder encodeInt:self.speedLimit forKey:@"limit"];
    [coder encodeDouble:self.direction forKey:@"dir"];
    [coder encodeInteger:self.type forKey:@"type"];
    [coder encodeObject:self.roadDescription forKey:@"desc"];
    [coder encodeObject:self.operatorName forKey:@"op"];
    [coder encodeInt64:self.osmId forKey:@"osmid"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        double lat = [coder decodeDoubleForKey:@"lat"];
        double lon = [coder decodeDoubleForKey:@"lon"];
        _coordinate = CLLocationCoordinate2DMake(lat, lon);
        _speedLimit = [coder decodeIntForKey:@"limit"];
        _direction = [coder decodeDoubleForKey:@"dir"];
        _type = (SpeedCameraType)[coder decodeIntegerForKey:@"type"];
        _roadDescription = [coder decodeObjectOfClass:[NSString class] forKey:@"desc"];
        _operatorName = [coder decodeObjectOfClass:[NSString class] forKey:@"op"];
        _osmId = [coder decodeInt64ForKey:@"osmid"];
    }
    return self;
}

- (NSString *)typeDescription {
    BOOL isIt = [[LocalizationManager sharedManager] isItalian];
    switch (self.type) {
        case SpeedCameraTypeFixed:
            return isIt ? @"Autovelox Fisso" : @"Fixed Speed Camera";
        case SpeedCameraTypeTutor:
            return isIt ? @"Tutor (Velocità Media)" : @"Average Speed Check";
        case SpeedCameraTypeTrafficLight:
            return isIt ? @"Telecamera Semaforica" : @"Red Light Camera";
        case SpeedCameraTypeMobile:
            return isIt ? @"Postazione Mobile" : @"Mobile Camera";
    }
    return isIt ? @"Autovelox" : @"Speed Camera";
}

- (NSString *)formattedTitle {
    if (self.speedLimit > 0) {
        return [NSString stringWithFormat:@"📸 %@ (%d km/h)", [self typeDescription], self.speedLimit];
    }
    return [NSString stringWithFormat:@"📸 %@", [self typeDescription]];
}

- (NSString *)formattedSubtitle {
    if (self.roadDescription && self.roadDescription.length > 0) {
        return self.roadDescription;
    }
    if (self.operatorName && self.operatorName.length > 0) {
        return self.operatorName;
    }
    if (self.speedLimit > 0) {
        return [NSString stringWithFormat:@"Limite di velocità: %d km/h", self.speedLimit];
    }
    return @"Controllo elettronico della velocità";
}

@end

@implementation SpeedCameraAnnotation

- (instancetype)initWithCamera:(SpeedCamera *)camera {
    self = [super init];
    if (self) {
        _camera = camera;
        _coordinate = camera.coordinate;
        _title = [camera formattedTitle];
        _subtitle = [camera formattedSubtitle];
    }
    return self;
}

@end

@interface SpeedCameraService ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, readwrite) NSArray<SpeedCamera *> *cachedCameras;
@property (nonatomic, strong, readwrite) NSDate *lastFetchDate;
@property (nonatomic, copy) NSString *cacheFilePath;
@end

@implementation SpeedCameraService

+ (instancetype)sharedService {
    static SpeedCameraService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SpeedCameraService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 14.0;
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"NavigatoreOSM/1.3.6 (iPad; iOS 9.3.5; SpeedCameraModule)"
        };
        _session = [NSURLSession sessionWithConfiguration:config];

        NSString *cachesDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        _cacheFilePath = [cachesDir stringByAppendingPathComponent:@"speed_cameras_cache.plist"];

        [self loadCachedCamerasFromDisk];
    }
    return self;
}

- (void)loadCachedCamerasFromDisk {
    if (![[NSFileManager defaultManager] fileExistsAtPath:_cacheFilePath]) return;
    @try {
        NSData *data = [NSData dataWithContentsOfFile:_cacheFilePath];
        if (data) {
            NSArray *loaded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            if ([loaded isKindOfClass:[NSArray class]]) {
                _cachedCameras = loaded;
                _lastFetchDate = [[NSFileManager defaultManager] attributesOfItemAtPath:_cacheFilePath error:nil][NSFileModificationDate];
                NSLog(@"[SpeedCameraService] Caricati %lu autovelox dalla cache su disco", (unsigned long)_cachedCameras.count);
            }
        }
    } @catch (NSException *ex) {
        NSLog(@"[SpeedCameraService] Errore lettura cache velox: %@", ex);
    }
}

- (void)saveCachedCamerasToDisk {
    if (!_cachedCameras || _cachedCameras.count == 0) return;
    @try {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:_cachedCameras];
        [data writeToFile:_cacheFilePath atomically:YES];
    } @catch (NSException *ex) {
        NSLog(@"[SpeedCameraService] Errore salvataggio cache velox: %@", ex);
    }
}

#pragma mark - Download Autovelox via Overpass API

- (void)fetchCamerasAroundCoordinate:(CLLocationCoordinate2D)coord
                        radiusMeters:(double)radius
                          completion:(void (^)(NSArray<SpeedCamera *> *cameras, NSError *error))completion {

    if (!CLLocationCoordinate2DIsValid(coord) || (fabs(coord.latitude) < 0.1 && fabs(coord.longitude) < 0.1)) {
        if (completion) completion(self.cachedCameras ?: @[], nil);
        return;
    }

    double r = (radius > 1000.0) ? radius : 15000.0; // Default 15 km

    NSString *query = [NSString stringWithFormat:
        @"[out:json][timeout:15];("
        @"node(around:%.0f,%.6f,%.6f)[highway=speed_camera];"
        @"node(around:%.0f,%.6f,%.6f)[enforcement=maxspeed];"
        @");out body;",
        r, coord.latitude, coord.longitude,
        r, coord.latitude, coord.longitude];

    [self executeOverpassQuery:query completion:^(NSArray<SpeedCamera *> *cameras, NSError *error) {
        if (!error && cameras) {
            [self mergeNewCameras:cameras];
            if (completion) completion(self.cachedCameras, nil);
        } else {
            if (completion) completion(self.cachedCameras ?: @[], error);
        }
    }];
}

- (void)fetchCamerasAlongRoute:(RouteInfo *)route
                    completion:(void (^)(NSArray<SpeedCamera *> *cameras, NSError *error))completion {
    if (!route || route.steps.count == 0) {
        if (completion) completion(self.cachedCameras ?: @[], nil);
        return;
    }

    // Costruisci query corridor intorno ai passaggi del percorso (max 10 punti campionati per non sovraccaricare la query)
    NSMutableArray<NSString *> *subQueries = [NSMutableArray array];
    NSUInteger stepInterval = MAX(1, route.steps.count / 8);

    for (NSUInteger i = 0; i < route.steps.count; i += stepInterval) {
        ManeuverStep *step = route.steps[i];
        if (CLLocationCoordinate2DIsValid(step.coordinate)) {
            NSString *q = [NSString stringWithFormat:@"node(around:10000,%.6f,%.6f)[highway=speed_camera];"
                                                     @"node(around:10000,%.6f,%.6f)[enforcement=maxspeed];",
                           step.coordinate.latitude, step.coordinate.longitude,
                           step.coordinate.latitude, step.coordinate.longitude];
            [subQueries addObject:q];
        }
    }

    // Aggiungi destinazione
    NSString *destQ = [NSString stringWithFormat:@"node(around:10000,%.6f,%.6f)[highway=speed_camera];"
                                                 @"node(around:10000,%.6f,%.6f)[enforcement=maxspeed];",
                       route.destinationCoordinate.latitude, route.destinationCoordinate.longitude,
                       route.destinationCoordinate.latitude, route.destinationCoordinate.longitude];
    [subQueries addObject:destQ];

    NSString *combinedSub = [subQueries componentsJoinedByString:@""];
    NSString *query = [NSString stringWithFormat:@"[out:json][timeout:20];(%@);out body;", combinedSub];

    [self executeOverpassQuery:query completion:^(NSArray<SpeedCamera *> *cameras, NSError *error) {
        if (!error && cameras) {
            [self mergeNewCameras:cameras];
            if (completion) completion(self.cachedCameras, nil);
        } else {
            if (completion) completion(self.cachedCameras ?: @[], error);
        }
    }];
}

- (void)executeOverpassQuery:(NSString *)query completion:(void (^)(NSArray<SpeedCamera *> *cameras, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:@"https://overpass-api.de/api/interpreter"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    NSString *postBody = [NSString stringWithFormat:@"data=%@", [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]]];
    req.HTTPBody = [postBody dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            NSLog(@"[SpeedCameraService] Errore richiesta Overpass: %@", error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }

        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || ![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, jsonErr);
            });
            return;
        }

        NSArray *elements = json[@"elements"];
        if (![elements isKindOfClass:[NSArray class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(@[], nil);
            });
            return;
        }

        NSMutableArray<SpeedCamera *> *parsed = [NSMutableArray array];
        for (NSDictionary *el in elements) {
            double lat = [el[@"lat"] doubleValue];
            double lon = [el[@"lon"] doubleValue];
            if (lat == 0.0 && lon == 0.0) continue;

            NSDictionary *tags = el[@"tags"];
            SpeedCamera *cam = [[SpeedCamera alloc] init];
            cam.osmId = [el[@"id"] longLongValue];
            cam.coordinate = CLLocationCoordinate2DMake(lat, lon);

            // Parsing limite di velocità
            NSString *maxspeedStr = tags[@"maxspeed"];
            if (maxspeedStr && maxspeedStr.length > 0) {
                cam.speedLimit = [maxspeedStr intValue];
            } else {
                cam.speedLimit = 0;
            }

            // Parsing direzione
            NSString *dirStr = tags[@"direction"];
            if (dirStr && dirStr.length > 0) {
                cam.direction = [dirStr doubleValue];
            } else {
                cam.direction = -1.0;
            }

            // Tipo autovelox
            NSString *enforcement = tags[@"enforcement"];
            NSString *trafficSignal = tags[@"traffic_signals"];
            if ([enforcement isEqualToString:@"traffic_signals"] || (trafficSignal && trafficSignal.length > 0)) {
                cam.type = SpeedCameraTypeTrafficLight;
            } else if ([enforcement isEqualToString:@"average_speed"]) {
                cam.type = SpeedCameraTypeTutor;
            } else {
                cam.type = SpeedCameraTypeFixed;
            }

            cam.roadDescription = tags[@"description"] ?: tags[@"name"] ?: tags[@"note"];
            cam.operatorName = tags[@"operator"];

            [parsed addObject:cam];
        }

        NSLog(@"[SpeedCameraService] Scaricati %lu autovelox da Overpass API", (unsigned long)parsed.count);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(parsed, nil);
        });
    }];
    [task resume];
}

- (void)mergeNewCameras:(NSArray<SpeedCamera *> *)newCameras {
    NSMutableDictionary<NSNumber *, SpeedCamera *> *camDict = [NSMutableDictionary dictionary];
    for (SpeedCamera *c in self.cachedCameras) {
        camDict[@(c.osmId)] = c;
    }
    for (SpeedCamera *c in newCameras) {
        camDict[@(c.osmId)] = c;
    }

    self.cachedCameras = [camDict allValues];
    self.lastFetchDate = [NSDate date];
    [self saveCachedCamerasToDisk];
}

#pragma mark - Proximity Detection Engine

- (SpeedCamera *)checkApproachingCameraFromLocation:(CLLocation *)location
                                            heading:(CLLocationDirection)heading
                                        outDistance:(CLLocationDistance *)outDistance {
    if (!location || self.cachedCameras.count == 0) return nil;

    CLLocationCoordinate2D userCoord = location.coordinate;
    double userSpeedMs = location.speed;

    // Distanza di preallarme: 450m a velocità urbana, 750m se velocità > 70 km/h (~20 m/s)
    double alertDistanceThreshold = (userSpeedMs > 20.0) ? 750.0 : 450.0;

    SpeedCamera *closestCam = nil;
    CLLocationDistance minDistance = DBL_MAX;

    for (SpeedCamera *cam in self.cachedCameras) {
        CLLocation *camLoc = [[CLLocation alloc] initWithLatitude:cam.coordinate.latitude longitude:cam.coordinate.longitude];
        CLLocationDistance dist = [location distanceFromLocation:camLoc];

        if (dist <= alertDistanceThreshold) {
            // Verifica che il velox si trovi DAVANTI al veicolo (entro un cono di ±60 gradi rispetto all'angolo di marcia)
            if (heading >= 0) {
                double bearingToCam = [self calculateHeadingFrom:userCoord to:cam.coordinate];
                double angleDiff = fabs(bearingToCam - heading);
                if (angleDiff > 180.0) angleDiff = 360.0 - angleDiff;

                if (angleDiff > 60.0) {
                    // La telecamera è alle spalle o troppo di lato: non è in avvicinamento
                    continue;
                }

                // Se la telecamera ha una direzione specifica di scatto, verifica compatibilità
                if (cam.direction >= 0) {
                    double dirDiff = fabs(cam.direction - heading);
                    if (dirDiff > 180.0) dirDiff = 360.0 - dirDiff;
                    // Scartiamo se la telecamera guarda la direzione diametralmente opposta (es. senso opposto)
                    if (dirDiff > 80.0 && dirDiff < 280.0) {
                        continue;
                    }
                }
            }

            if (dist < minDistance) {
                minDistance = dist;
                closestCam = cam;
            }
        }
    }

    if (closestCam && outDistance) {
        *outDistance = minDistance;
    }
    return closestCam;
}

- (double)calculateHeadingFrom:(CLLocationCoordinate2D)from to:(CLLocationCoordinate2D)to {
    double lat1 = from.latitude * (M_PI / 180.0);
    double lon1 = from.longitude * (M_PI / 180.0);
    double lat2 = to.latitude * (M_PI / 180.0);
    double lon2 = to.longitude * (M_PI / 180.0);
    double dLon = lon2 - lon1;

    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double brng = atan2(y, x) * (180.0 / M_PI);
    return fmod((brng + 360.0), 360.0);
}

- (NSArray<SpeedCameraAnnotation *> *)annotationsForCachedCameras {
    NSMutableArray *annList = [NSMutableArray array];
    for (SpeedCamera *c in self.cachedCameras) {
        [annList addObject:[[SpeedCameraAnnotation alloc] initWithCamera:c]];
    }
    return annList;
}

@end

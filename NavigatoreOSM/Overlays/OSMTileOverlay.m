#import "OSMTileOverlay.h"
#import <UIKit/UIKit.h>

@interface OSMTileOverlay ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) NSString *cacheDirectory;
@property (nonatomic, strong) NSCache *memoryCache;
@property (nonatomic, strong) NSOperationQueue *prefetchQueue;
@property (nonatomic, strong) NSMutableSet<NSString *> *prefetchInProgressKeys;
@property (nonatomic, strong) NSDate *lastAheadPrefetchDate;
@end

@implementation OSMTileOverlay

static NSString *URLTemplateForTheme(OSMMapTheme theme) {
    switch (theme) {
        case OSMMapThemeDark:
            // Esri World Dark Gray Base: sfondo scuro perfetto per guida notturna, 100% gratuito e NESSUNA API key richiesta!
            return @"https://services.arcgisonline.com/arcgis/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}";
        case OSMMapThemeSatellite:
            // Esri World Imagery: satellite fotografico ad alta definizione globale, 100% gratuito e NESSUNA API key richiesta!
            return @"https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}";
        case OSMMapThemeStandard:
        default:
            // OpenStreetMap Standard ufficiale
            return @"https://tile.openstreetmap.org/{z}/{x}/{y}.png";
    }
}

static inline MKTileOverlayPath TilePathForCoordinate(CLLocationCoordinate2D coord, NSUInteger zoom) {
    MKTileOverlayPath p;
    p.z = zoom;
    p.contentScaleFactor = 1.0;
    int n = 1 << zoom;
    int x = (int)floor((coord.longitude + 180.0) / 360.0 * (double)n);
    double latRad = coord.latitude * M_PI / 180.0;
    int y = (int)floor((1.0 - asinh(tan(latRad)) / M_PI) / 2.0 * (double)n);
    p.x = MAX(0, MIN(n - 1, x));
    p.y = MAX(0, MIN(n - 1, y));
    return p;
}

- (instancetype)init {
    return [self initWithTheme:OSMMapThemeStandard];
}

- (instancetype)initWithTheme:(OSMMapTheme)theme {
    NSString *template = URLTemplateForTheme(theme);
    self = [super initWithURLTemplate:template];
    if (self) {
        _theme = theme;
        self.canReplaceMapContent = YES;
        self.maximumZ = 19;
        self.minimumZ = 3;
        self.tileSize = CGSizeMake(256, 256);

        // Prepara la sessione HTTP con User-Agent conforme e throughput multi-socket aumentato
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"NavigatoreOSM/1.3.15 (iPad Mini 1; iOS 9.3.5; TileEngine)"
        };
        config.timeoutIntervalForRequest = 8.0;
        config.HTTPMaximumConnectionsPerHost = 6;
        _session = [NSURLSession sessionWithConfiguration:config];

        // Cache in memoria RAM ad alte prestazioni (350 tile = circa 8.5 MB RAM)
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = 350;

        _prefetchQueue = [[NSOperationQueue alloc] init];
        _prefetchQueue.maxConcurrentOperationCount = 3; // Throughput rapido ma senza saturare la CPU A5
        _prefetchInProgressKeys = [NSMutableSet set];

        // Prepara la cartella cache su disco
        NSString *baseCache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        _cacheDirectory = [baseCache stringByAppendingPathComponent:@"OSMTiles"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];

        // Pulizia una tantum della vecchia cartella dark/voyager di Carto e di vecchie tile dark non conformi
        NSString *oldDark = [_cacheDirectory stringByAppendingPathComponent:@"dark"];
        NSString *oldVoyager = [_cacheDirectory stringByAppendingPathComponent:@"voyager"];
        NSString *esriDark = [_cacheDirectory stringByAppendingPathComponent:@"dark_esri"];
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DidClearOldEsriDarkCache_v13"]) {
            [[NSFileManager defaultManager] removeItemAtPath:oldDark error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:oldVoyager error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:esriDark error:nil];
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DidClearOldEsriDarkCache_v13"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }

        // Ascolta avviso di memoria per liberare subito la RAM cache se necessario
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(clearMemoryCache)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_session invalidateAndCancel];
}

- (NSURL *)URLForTilePath:(MKTileOverlayPath)path {
    switch (self.theme) {
        case OSMMapThemeDark: {
            // Esri World Dark Gray Base: /tile/{z}/{y}/{x}
            NSString *urlStr = [NSString stringWithFormat:@"https://services.arcgisonline.com/arcgis/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/%ld/%ld/%ld",
                                (long)path.z, (long)path.y, (long)path.x];
            return [NSURL URLWithString:urlStr];
        }
        case OSMMapThemeSatellite: {
            // Esri World Imagery: /tile/{z}/{y}/{x}
            NSString *urlStr = [NSString stringWithFormat:@"https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/%ld/%ld/%ld",
                                (long)path.z, (long)path.y, (long)path.x];
            return [NSURL URLWithString:urlStr];
        }
        case OSMMapThemeStandard:
        default: {
            // OpenStreetMap Standard con round-robin su {a,b,c}.tile.openstreetmap.org
            // per moltiplicare i socket TCP e superare i limiti di connessione per singolo host
            static const char cdnSubdomains[] = "abc";
            char sub = cdnSubdomains[(labs((long)path.x) + labs((long)path.y)) % 3];
            NSString *urlStr = [NSString stringWithFormat:@"https://%c.tile.openstreetmap.org/%ld/%ld/%ld.png",
                                sub, (long)path.z, (long)path.x, (long)path.y];
            return [NSURL URLWithString:urlStr];
        }
    }
}

- (void)switchTheme:(OSMMapTheme)newTheme {
    _theme = newTheme;
    NSString *template = URLTemplateForTheme(newTheme);
    [self setValue:template forKey:@"URLTemplate"];
}

- (NSString *)tileFilePathForPath:(MKTileOverlayPath)path theme:(OSMMapTheme)theme {
    NSString *themeName;
    NSString *ext;
    if (theme == OSMMapThemeDark) {
        themeName = @"dark_esri";
        ext = @"jpg";
    } else if (theme == OSMMapThemeSatellite) {
        themeName = @"satellite_esri";
        ext = @"jpg";
    } else {
        themeName = @"standard";
        ext = @"png";
    }
    return [self.cacheDirectory stringByAppendingFormat:@"/%@/%ld/%ld/%ld.%@",
            themeName, (long)path.z, (long)path.x, (long)path.y, ext];
}

- (NSString *)cacheKeyForPath:(MKTileOverlayPath)path theme:(OSMMapTheme)theme {
    return [NSString stringWithFormat:@"%ld_%ld_%ld_%ld", (long)theme, (long)path.z, (long)path.x, (long)path.y];
}

- (void)clearMemoryCache {
    [self.memoryCache removeAllObjects];
}

- (void)loadTileAtPath:(MKTileOverlayPath)path result:(void (^)(NSData *tileData, NSError *error))result {
    if (!result) return;

    NSString *cacheKey = [self cacheKeyForPath:path theme:self.theme];

    // 1. Cache RAM: se presente in memoria, restituisci all'istante (0.1 ms)
    NSData *memData = [self.memoryCache objectForKey:cacheKey];
    if (memData && memData.length > 0) {
        result(memData, nil);
        return;
    }

    // 2. Cache su disco: lettura sicura heap con NSData dataWithContentsOfFile (immune da SIGBUS)
    NSString *filePath = [self tileFilePathForPath:path theme:self.theme];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSData *diskData = [NSData dataWithContentsOfFile:filePath];
        if (diskData && diskData.length > 0) {
            [self.memoryCache setObject:diskData forKey:cacheKey];
            result(diskData, nil);
            return;
        }
    }

    // 3. Altrimenti, scarica la tile dal server
    NSURL *tileURL = [self URLForTilePath:path];
    if (!tileURL) {
        result(nil, [NSError errorWithDomain:@"OSMTileOverlayError" code:-1 userInfo:nil]);
        return;
    }

    __weak OSMTileOverlay *weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:tileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error && data.length > 100) {
            // Salva in RAM
            [weakSelf.memoryCache setObject:data forKey:cacheKey];

            // Salva su disco in background a bassa priorità I/O
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                NSString *folder = [filePath stringByDeletingLastPathComponent];
                [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
                [data writeToFile:filePath atomically:YES];
            });

            result(data, nil);
        } else {
            result(nil, error);
        }
    }];
    [task resume];
}

#pragma mark - Prefetching Predittivo On-Demand in Background

- (void)prefetchTilePath:(MKTileOverlayPath)path {
    NSString *cacheKey = [self cacheKeyForPath:path theme:self.theme];
    if ([self.memoryCache objectForKey:cacheKey]) return;

    NSString *filePath = [self tileFilePathForPath:path theme:self.theme];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) return;

    @synchronized (self.prefetchInProgressKeys) {
        if ([self.prefetchInProgressKeys containsObject:cacheKey]) return;
        [self.prefetchInProgressKeys addObject:cacheKey];
    }

    NSURL *tileURL = [self URLForTilePath:path];
    if (!tileURL) {
        @synchronized (self.prefetchInProgressKeys) {
            [self.prefetchInProgressKeys removeObject:cacheKey];
        }
        return;
    }

    __weak OSMTileOverlay *weakSelf = self;
    __block NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
        if (op.isCancelled) {
            @synchronized (weakSelf.prefetchInProgressKeys) {
                [weakSelf.prefetchInProgressKeys removeObject:cacheKey];
            }
            return;
        }

        NSURLRequest *req = [NSURLRequest requestWithURL:tileURL cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:8.0];
        NSURLSessionDataTask *task = [weakSelf.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data && !error && data.length > 100) {
                [weakSelf.memoryCache setObject:data forKey:cacheKey];
                NSString *folder = [filePath stringByDeletingLastPathComponent];
                [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
                [data writeToFile:filePath atomically:YES];
            }
            @synchronized (weakSelf.prefetchInProgressKeys) {
                [weakSelf.prefetchInProgressKeys removeObject:cacheKey];
            }
        }];
        [task resume];
    }];

    [self.prefetchQueue addOperation:op];
}

- (void)prefetchTilesAlongRoute:(RouteInfo *)route currentDistance:(double)currentDistance lookaheadMeters:(double)lookahead {
    if (!route || !route.polyline || route.polyline.pointCount < 2) return;

    NSUInteger totalPoints = route.polyline.pointCount;
    MKMapPoint *points = route.polyline.points;
    if (!points || totalPoints < 2) return;

    // Distanze del corridoio da precaricare:
    // startDist: posizione attuale dell'auto lungo la rotta
    // endDist: orizzonte in anticipo (es. 2.000 metri avanti)
    double startDist = MAX(0.0, currentDistance);
    double endDist = MIN(route.totalDistance, startDist + lookahead);
    if (endDist <= startDist) return;

    // Cancella prefetch pendenti ormai superati dalla marcia
    [self.prefetchQueue cancelAllOperations];

    // Troviamo i punti lungo la polyline compresi tra startDist ed endDist,
    // campionando a passo geometrico regolare di ~130 metri.
    // Una tile a Zoom 17 è di ~216m, quindi 130m garantisce che OGNI tile sul percorso venga campionata!
    double sampleStepMeters = 130.0;
    double currentAccumulatedDist = 0.0;
    double nextTargetDist = startDist;

    // Set per evitare duplicati nella stessa sessione di prefetch
    NSMutableSet<NSString *> *queuedKeys = [NSMutableSet set];

    for (NSUInteger i = 0; i < totalPoints - 1 && nextTargetDist <= endDist; i++) {
        MKMapPoint p1 = points[i];
        MKMapPoint p2 = points[i + 1];
        CLLocationDistance segLen = MKMetersBetweenMapPoints(p1, p2);
        if (segLen <= 0.001) continue;

        double segStartDist = currentAccumulatedDist;
        double segEndDist = currentAccumulatedDist + segLen;

        while (nextTargetDist >= segStartDist && nextTargetDist <= segEndDist && nextTargetDist <= endDist) {
            double ratio = (nextTargetDist - segStartDist) / segLen;
            MKMapPoint sampledPoint = MKMapPointMake(p1.x + (p2.x - p1.x) * ratio,
                                                     p1.y + (p2.y - p1.y) * ratio);
            CLLocationCoordinate2D coord = MKCoordinateForMapPoint(sampledPoint);

            double distFromCar = nextTargetDist - startDist;

            // 1. Nei prossimi 1.800 metri: prefetch a Zoom 17 (primo piano ad altissima definizione attorno all'auto)
            if (distFromCar <= 1800.0) {
                MKTileOverlayPath p17 = TilePathForCoordinate(coord, 17);
                NSString *k17 = [self cacheKeyForPath:p17 theme:self.theme];
                if (![queuedKeys containsObject:k17]) {
                    [queuedKeys addObject:k17];
                    [self prefetchTilePath:p17];
                }
            }

            // 2. Nei prossimi 3.000 metri: prefetch a Zoom 16 (media distanza e curve)
            if (distFromCar <= 3000.0) {
                MKTileOverlayPath p16 = TilePathForCoordinate(coord, 16);
                NSString *k16 = [self cacheKeyForPath:p16 theme:self.theme];
                if (![queuedKeys containsObject:k16]) {
                    [queuedKeys addObject:k16];
                    [self prefetchTilePath:p16];
                }
            }

            // 3. Fino alla fine del lookahead: prefetch a Zoom 15 (sfondo orizzonte 3D)
            MKTileOverlayPath p15 = TilePathForCoordinate(coord, 15);
            NSString *k15 = [self cacheKeyForPath:p15 theme:self.theme];
            if (![queuedKeys containsObject:k15]) {
                [queuedKeys addObject:k15];
                [self prefetchTilePath:p15];
            }

            nextTargetDist += sampleStepMeters;
        }

        currentAccumulatedDist = segEndDist;
    }
}

- (void)prefetchTilesAheadOfCoordinate:(CLLocationCoordinate2D)coord heading:(double)heading speed:(double)speed {
    if (speed < 3.5) return; // Meno di ~13 km/h: veicolo fermo o manovra da fermo, prefetch rapido non necessario

    NSDate *now = [NSDate date];
    if (self.lastAheadPrefetchDate && [now timeIntervalSinceDate:self.lastAheadPrefetchDate] < 4.0) {
        return; // Throttle a 4 secondi
    }
    self.lastAheadPrefetchDate = now;

    double rEarth = 6371000.0; // raggio terrestre in metri
    double lat1 = coord.latitude * M_PI / 180.0;
    double lon1 = coord.longitude * M_PI / 180.0;
    double brng = heading * M_PI / 180.0;

    // Distanze di proiezione avanti lungo l'azimuth di marcia:
    // 160m (~10s a 50 km/h), 380m (~25s), 700m (~45s), 1100m (~70s)
    double distances[] = { 160.0, 380.0, 700.0, 1100.0 };
    NSUInteger numDists = sizeof(distances) / sizeof(distances[0]);

    NSMutableSet<NSString *> *queuedKeys = [NSMutableSet set];

    for (NSUInteger i = 0; i < numDists; i++) {
        double d = distances[i];
        double lat2 = asin(sin(lat1) * cos(d / rEarth) + cos(lat1) * sin(d / rEarth) * cos(brng));
        double lon2 = lon1 + atan2(sin(brng) * sin(d / rEarth) * cos(lat1), cos(d / rEarth) - sin(lat1) * sin(lat2));

        CLLocationCoordinate2D forwardCoord = CLLocationCoordinate2DMake(lat2 * 180.0 / M_PI, lon2 * 180.0 / M_PI);

        // Per i primi 400m: scarica Zoom 17 (centro + 1 tile laterale per curve/incroci)
        if (d <= 400.0) {
            MKTileOverlayPath centerPath = TilePathForCoordinate(forwardCoord, 17);
            for (NSInteger dx = -1; dx <= 1; dx++) {
                for (NSInteger dy = -1; dy <= 1; dy++) {
                    MKTileOverlayPath p = centerPath;
                    NSInteger nx = (NSInteger)p.x + dx;
                    NSInteger ny = (NSInteger)p.y + dy;
                    int maxN = 1 << 17;
                    if (nx >= 0 && nx < maxN && ny >= 0 && ny < maxN) {
                        p.x = (NSUInteger)nx;
                        p.y = (NSUInteger)ny;
                        NSString *k = [self cacheKeyForPath:p theme:self.theme];
                        if (![queuedKeys containsObject:k]) {
                            [queuedKeys addObject:k];
                            [self prefetchTilePath:p];
                        }
                    }
                }
            }
        }

        // Per tutti i punti fino a 1100m: scarica Zoom 16
        MKTileOverlayPath p16 = TilePathForCoordinate(forwardCoord, 16);
        NSString *k16 = [self cacheKeyForPath:p16 theme:self.theme];
        if (![queuedKeys containsObject:k16]) {
            [queuedKeys addObject:k16];
            [self prefetchTilePath:p16];
        }

        // Per i punti lontani (700m - 1100m): scarica Zoom 15 (orizzonte)
        if (d >= 700.0) {
            MKTileOverlayPath p15 = TilePathForCoordinate(forwardCoord, 15);
            NSString *k15 = [self cacheKeyForPath:p15 theme:self.theme];
            if (![queuedKeys containsObject:k15]) {
                [queuedKeys addObject:k15];
                [self prefetchTilePath:p15];
            }
        }
    }
}

@end

#import "OSMTileOverlay.h"

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

        // Prepara la sessione HTTP con User-Agent identificativo conforme alla Tile Policy OSM
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"NavigatoreOSM/1.3.7 (iPad Mini 1; iOS 9.3.5; TileEngine)"
        };
        config.timeoutIntervalForRequest = 10.0;
        _session = [NSURLSession sessionWithConfiguration:config];

        // Cache in memoria RAM ad alte prestazioni (120 tile = circa 3.5 MB RAM)
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = 120;

        _prefetchQueue = [[NSOperationQueue alloc] init];
        _prefetchQueue.maxConcurrentOperationCount = 2; // Bassa priorità per non bloccare la visuale attiva
        _prefetchInProgressKeys = [NSMutableSet set];

        // Prepara la cartella cache su disco ed elimina eventuali vecchie tile Carto con watermark o cache scura corrotta
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
    }
    return self;
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
            // OpenStreetMap Standard: /{z}/{x}/{y}.png
            NSString *urlStr = [NSString stringWithFormat:@"https://tile.openstreetmap.org/%ld/%ld/%ld.png",
                                (long)path.z, (long)path.x, (long)path.y];
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
    NSString *cacheKey = [self cacheKeyForPath:path theme:self.theme];

    // 1. Cache RAM: se presente in memoria, restituisci all'istante (0.1 ms)
    NSData *memData = [self.memoryCache objectForKey:cacheKey];
    if (memData && memData.length > 0) {
        result(memData, nil);
        return;
    }

    // 2. Cache su disco: se presente, salva in RAM e restituisci immediatamente i dati offline
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
        if (data && !error) {
            // Salva in RAM
            [weakSelf.memoryCache setObject:data forKey:cacheKey];

            // Salva su disco in background
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

#pragma mark - Prefetching Predittivo in Background

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
    if (!tileURL) return;

    __weak OSMTileOverlay *weakSelf = self;
    [self.prefetchQueue addOperationWithBlock:^{
        NSURLRequest *req = [NSURLRequest requestWithURL:tileURL cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:8.0];
        NSURLSessionDataTask *task = [weakSelf.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data && !error) {
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
}

- (void)prefetchTilesAlongRoute:(RouteInfo *)route currentDistance:(double)currentDistance lookaheadMeters:(double)lookahead {
    if (!route || !route.polyline || route.polyline.pointCount < 2) return;

    NSUInteger totalPoints = route.polyline.pointCount;

    // Campiona punti lungo il tracciato nei prossimi 3–5 km
    double startDist = MAX(0.0, currentDistance);
    double endDist = MIN(route.totalDistance, startDist + lookahead);
    if (endDist <= startDist) return;

    // Seleziona livelli di zoom tipici della guida turn-by-turn
    NSArray<NSNumber *> *zooms = @[@(15), @(16)];

    // Stimiamo l'indice di partenza
    double fracStart = startDist / MAX(1.0, route.totalDistance);
    double fracEnd = endDist / MAX(1.0, route.totalDistance);
    NSUInteger startIdx = (NSUInteger)floor(fracStart * (double)(totalPoints - 1));
    NSUInteger endIdx = (NSUInteger)ceil(fracEnd * (double)(totalPoints - 1));
    if (endIdx >= totalPoints) endIdx = totalPoints - 1;

    NSUInteger step = MAX(1, (NSUInteger)floor((double)(endIdx - startIdx) / 12.0));

    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * totalPoints);
    if (!coords) return;
    [route.polyline getCoordinates:coords range:NSMakeRange(0, totalPoints)];

    for (NSUInteger i = startIdx; i <= endIdx; i += step) {
        CLLocationCoordinate2D coord = coords[i];
        for (NSNumber *zNum in zooms) {
            NSUInteger z = [zNum unsignedIntegerValue];
            MKTileOverlayPath p = TilePathForCoordinate(coord, z);
            [self prefetchTilePath:p];
        }
    }
    free(coords);
}

- (void)prefetchTilesAheadOfCoordinate:(CLLocationCoordinate2D)coord heading:(double)heading speed:(double)speed {
    if (speed < 4.0) return; // Meno di 15 km/h: prefetching non necessario

    NSDate *now = [NSDate date];
    if (self.lastAheadPrefetchDate && [now timeIntervalSinceDate:self.lastAheadPrefetchDate] < 6.0) {
        return; // Throttle ogni 6 secondi
    }
    self.lastAheadPrefetchDate = now;

    // Proietta una coordinata avanti di 15–20 secondi di marcia (500m - 1200m)
    double distKm = MIN(1.2, MAX(0.5, (speed * 18.0) / 1000.0));
    double rEarth = 6371.0;
    double lat1 = coord.latitude * M_PI / 180.0;
    double lon1 = coord.longitude * M_PI / 180.0;
    double brng = heading * M_PI / 180.0;
    double lat2 = asin(sin(lat1) * cos(distKm / rEarth) + cos(lat1) * sin(distKm / rEarth) * cos(brng));
    double lon2 = lon1 + atan2(sin(brng) * sin(distKm / rEarth) * cos(lat1), cos(distKm / rEarth) - sin(lat1) * sin(lat2));

    CLLocationCoordinate2D forwardCoord = CLLocationCoordinate2DMake(lat2 * 180.0 / M_PI, lon2 * 180.0 / M_PI);

    // Scarica la tile centrale e le tile adiacenti (griglia 3x3) a zoom 15 e 16
    for (NSUInteger z = 15; z <= 16; z++) {
        MKTileOverlayPath centerPath = TilePathForCoordinate(forwardCoord, z);
        for (NSInteger dx = -1; dx <= 1; dx++) {
            for (NSInteger dy = -1; dy <= 1; dy++) {
                MKTileOverlayPath p = centerPath;
                NSInteger nx = (NSInteger)p.x + dx;
                NSInteger ny = (NSInteger)p.y + dy;
                int maxN = 1 << z;
                if (nx >= 0 && nx < maxN && ny >= 0 && ny < maxN) {
                    p.x = (NSUInteger)nx;
                    p.y = (NSUInteger)ny;
                    [self prefetchTilePath:p];
                }
            }
        }
    }
}

@end

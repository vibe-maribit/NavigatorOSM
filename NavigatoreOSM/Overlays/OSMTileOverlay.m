#import "OSMTileOverlay.h"

@interface OSMTileOverlay ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) NSString *cacheDirectory;
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
            @"User-Agent": @"NavigatoreOSM/1.2 (iPad Mini 1; iOS 9.3.5; OSM Navigation Client)"
        };
        config.timeoutIntervalForRequest = 10.0;
        _session = [NSURLSession sessionWithConfiguration:config];

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

- (void)loadTileAtPath:(MKTileOverlayPath)path result:(void (^)(NSData *tileData, NSError *error))result {
    NSString *filePath = [self tileFilePathForPath:path theme:self.theme];

    // 1. Cache su disco: se presente, restituisci immediatamente i dati offline
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSData *cached = [NSData dataWithContentsOfFile:filePath];
        if (cached && cached.length > 0) {
            result(cached, nil);
            return;
        }
    }

    // 2. Altrimenti, scarica la tile dal server
    NSURL *tileURL = [self URLForTilePath:path];
    if (!tileURL) {
        result(nil, [NSError errorWithDomain:@"OSMTileOverlayError" code:-1 userInfo:nil]);
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:tileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            // Salva su disco in background
            NSString *folder = [filePath stringByDeletingLastPathComponent];
            [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
            [data writeToFile:filePath atomically:YES];
            result(data, nil);
        } else {
            result(nil, error);
        }
    }];
    [task resume];
}

@end

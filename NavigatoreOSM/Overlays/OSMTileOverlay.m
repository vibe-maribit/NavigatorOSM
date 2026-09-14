#import "OSMTileOverlay.h"

@interface OSMTileOverlay ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) NSString *cacheDirectory;
@end

@implementation OSMTileOverlay

static NSString *URLTemplateForTheme(OSMMapTheme theme) {
    switch (theme) {
        case OSMMapThemeDark:
            return @"https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png";
        case OSMMapThemeVoyager:
            return @"https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png";
        case OSMMapThemeStandard:
        default:
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

        // Prepara la sessione HTTP con User-Agent appropriato
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"NavigatoreOSM/1.0 (iPad Mini 1; iOS 9.3.5)"
        };
        config.timeoutIntervalForRequest = 10.0;
        _session = [NSURLSession sessionWithConfiguration:config];

        // Prepara la cartella cache su disco
        NSString *baseCache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        _cacheDirectory = [baseCache stringByAppendingPathComponent:@"OSMTiles"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

- (void)switchTheme:(OSMMapTheme)newTheme {
    _theme = newTheme;
    // Aggiorna template
    NSString *template = URLTemplateForTheme(newTheme);
    [self setValue:template forKey:@"URLTemplate"];
}

- (NSString *)tileFilePathForPath:(MKTileOverlayPath)path theme:(OSMMapTheme)theme {
    NSString *themeName = (theme == OSMMapThemeDark) ? @"dark" : ((theme == OSMMapThemeVoyager) ? @"voyager" : @"standard");
    return [self.cacheDirectory stringByAppendingFormat:@"/%@/%ld/%ld/%ld.png",
            themeName, (long)path.z, (long)path.x, (long)path.y];
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

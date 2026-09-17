#import "TrafficTileOverlay.h"

@interface TrafficTileOverlay ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) NSString *cacheDirectory;
@end

@implementation TrafficTileOverlay

+ (instancetype)sharedOverlay {
    static TrafficTileOverlay *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TrafficTileOverlay alloc] init];
    });
    return instance;
}

- (instancetype)init {
    // Template TomTom Flow Tiles relative
    NSString *savedKey = [[NSUserDefaults standardUserDefaults] stringForKey:@"TrafficApiKey"];
    if (!savedKey || savedKey.length == 0) {
        savedKey = @"";
    }

    BOOL enabled = YES;
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"TrafficEnabled"]) {
        enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"TrafficEnabled"];
    }

    NSString *template = [NSString stringWithFormat:@"https://api.tomtom.com/traffic/map/4/tile/flow/relative0/{z}/{x}/{y}.png?key=%@", savedKey];
    self = [super initWithURLTemplate:template];
    if (self) {
        _apiKey = [savedKey copy];
        _isEnabled = enabled;
        self.canReplaceMapContent = NO; // Trasparente sopra OSM!
        self.maximumZ = 18;
        self.minimumZ = 6;
        self.tileSize = CGSizeMake(256, 256);

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 6.0;
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"NavigatoreOSM/1.3.6 (iPad Mini 1; iOS 9.3.5; TrafficClient)"
        };
        _session = [NSURLSession sessionWithConfiguration:config];

        NSString *baseCache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        _cacheDirectory = [baseCache stringByAppendingPathComponent:@"TrafficTiles"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

- (void)setIsEnabled:(BOOL)isEnabled {
    _isEnabled = isEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:isEnabled forKey:@"TrafficEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)hasValidApiKey {
    return (self.apiKey && self.apiKey.length >= 6);
}

- (void)updateApiKey:(NSString *)apiKey {
    _apiKey = [apiKey copy];
    [[NSUserDefaults standardUserDefaults] setObject:apiKey forKey:@"TrafficApiKey"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSString *template = [NSString stringWithFormat:@"https://api.tomtom.com/traffic/map/4/tile/flow/relative0/{z}/{x}/{y}.png?key=%@", apiKey ?: @""];
    [self setValue:template forKey:@"URLTemplate"];
}

- (void)loadTileAtPath:(MKTileOverlayPath)path result:(void (^)(NSData *tileData, NSError *error))result {
    if (!self.isEnabled || self.apiKey.length == 0) {
        // Nessuna chiave traffico configurata o disabilitato: restituisci trasparente/nil senza errori
        result(nil, nil);
        return;
    }

    // Cache temporanea con TTL 3 minuti per il traffico in tempo reale
    NSString *filePath = [self.cacheDirectory stringByAppendingFormat:@"/%ld/%ld/%ld.png",
                          (long)path.z, (long)path.x, (long)path.y];

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
    if (attrs) {
        NSDate *modDate = attrs[NSFileModificationDate];
        if (modDate && [[NSDate date] timeIntervalSinceDate:modDate] < 180.0) { // 3 minuti
            NSData *cached = [NSData dataWithContentsOfFile:filePath];
            if (cached && cached.length > 0) {
                result(cached, nil);
                return;
            }
        }
    }

    NSURL *tileURL = [self URLForTilePath:path];
    if (!tileURL) {
        result(nil, nil);
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:tileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error && [response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (httpResp.statusCode == 200) {
                NSString *folder = [filePath stringByDeletingLastPathComponent];
                [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
                [data writeToFile:filePath atomically:YES];
                result(data, nil);
                return;
            }
        }
        result(nil, nil);
    }];
    [task resume];
}

@end

#import "../Services/RoutingService.h"

typedef NS_ENUM(NSInteger, OSMMapTheme) {
    OSMMapThemeStandard = 0,
    OSMMapThemeDark = 1,
    OSMMapThemeSatellite = 2
};

@interface OSMTileOverlay : MKTileOverlay

@property (nonatomic, assign) OSMMapTheme theme;

- (instancetype)initWithTheme:(OSMMapTheme)theme;
- (void)switchTheme:(OSMMapTheme)newTheme;

/// Cache e Prefetching Predittivo
- (void)clearMemoryCache;
- (void)prefetchTilesAlongRoute:(RouteInfo *)route currentDistance:(double)currentDistance lookaheadMeters:(double)lookahead;
- (void)prefetchTilesAheadOfCoordinate:(CLLocationCoordinate2D)coord heading:(double)heading speed:(double)speed;

@end

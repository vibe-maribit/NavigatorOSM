#import <MapKit/MapKit.h>

typedef NS_ENUM(NSInteger, OSMMapTheme) {
    OSMMapThemeStandard = 0,
    OSMMapThemeDark = 1,
    OSMMapThemeVoyager = 2
};

@interface OSMTileOverlay : MKTileOverlay

@property (nonatomic, assign) OSMMapTheme theme;

- (instancetype)initWithTheme:(OSMMapTheme)theme;
- (void)switchTheme:(OSMMapTheme)newTheme;

@end

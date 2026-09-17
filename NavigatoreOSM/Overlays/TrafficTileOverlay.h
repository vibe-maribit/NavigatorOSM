#import <MapKit/MapKit.h>

@interface TrafficTileOverlay : MKTileOverlay

@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, assign) BOOL isEnabled;

+ (instancetype)sharedOverlay;
- (void)updateApiKey:(NSString *)apiKey;
- (BOOL)hasValidApiKey;

@end

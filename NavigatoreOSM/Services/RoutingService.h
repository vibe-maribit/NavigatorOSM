#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

@interface ManeuverStep : NSObject

@property (nonatomic, copy) NSString *instruction;
@property (nonatomic, copy) NSString *streetName;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *modifier;
@property (nonatomic, assign) CLLocationDistance distance;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) CLLocationCoordinate2D coordinate;

@end

@interface RouteInfo : NSObject

@property (nonatomic, strong) MKPolyline *polyline;
@property (nonatomic, strong) NSArray<ManeuverStep *> *steps;
@property (nonatomic, assign) CLLocationDistance totalDistance;
@property (nonatomic, assign) NSTimeInterval totalDuration;
@property (nonatomic, assign) CLLocationCoordinate2D destinationCoordinate;
@property (nonatomic, copy) NSString *destinationTitle;
@property (nonatomic, copy) NSString *routeSummary;
@property (nonatomic, copy) NSString *trafficDescription;
@property (nonatomic, copy) NSString *badgeTitle;
@property (nonatomic, copy) NSString *deltaDescription;
@property (nonatomic, assign) NSUInteger routeIndex;
@property (nonatomic, assign) BOOL isPrimary;

@end

typedef void (^RouteCompletionBlock)(RouteInfo *route, NSError *error);
typedef void (^RoutesCompletionBlock)(NSArray<RouteInfo *> *routes, NSError *error);

@interface RoutingService : NSObject

+ (instancetype)sharedService;

/// Calcola itinerari multipli alternativi con traffico/annotazioni
- (void)calculateRoutesFrom:(CLLocationCoordinate2D)start
                         to:(CLLocationCoordinate2D)destination
            destinationTitle:(NSString *)title
                 completion:(RoutesCompletionBlock)completion;

/// Calcola itinerari alternativi permettendo di variare la spaziatura del corridoio
- (void)calculateRoutesFrom:(CLLocationCoordinate2D)start
                         to:(CLLocationCoordinate2D)destination
            destinationTitle:(NSString *)title
             corridorOffset:(double)offsetRatio
                 completion:(RoutesCompletionBlock)completion;

/// Compatibilità: calcola il percorso principale più veloce
- (void)calculateRouteFrom:(CLLocationCoordinate2D)start
                        to:(CLLocationCoordinate2D)destination
               destinationTitle:(NSString *)title
                completion:(RouteCompletionBlock)completion;

@end

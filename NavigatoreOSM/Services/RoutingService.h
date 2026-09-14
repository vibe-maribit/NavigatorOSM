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

@end

typedef void (^RouteCompletionBlock)(RouteInfo *route, NSError *error);

@interface RoutingService : NSObject

+ (instancetype)sharedService;

- (void)calculateRouteFrom:(CLLocationCoordinate2D)start
                        to:(CLLocationCoordinate2D)destination
               destinationTitle:(NSString *)title
                completion:(RouteCompletionBlock)completion;

@end

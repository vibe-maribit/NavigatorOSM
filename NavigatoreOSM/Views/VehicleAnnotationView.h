#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>

@interface VehicleAnnotation : NSObject <MKAnnotation>

@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
@property (nonatomic, assign) CLLocationDirection heading;
@property (nonatomic, assign) double speed;
@property (nonatomic, copy) NSString *title;

- (void)updateCoordinate:(CLLocationCoordinate2D)newCoordinate heading:(CLLocationDirection)newHeading;

@end

@interface VehicleAnnotationView : MKAnnotationView

@property (nonatomic, strong, readonly) UIView *puckContainer;
@property (nonatomic, strong, readonly) UIView *arrowView;

- (void)updateHeading:(CLLocationDirection)heading cameraHeading:(CLLocationDirection)cameraHeading;

@end

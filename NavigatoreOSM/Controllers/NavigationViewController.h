#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

@interface NavigationViewController : UIViewController <MKMapViewDelegate, CLLocationManagerDelegate>

@property (nonatomic, strong) MKMapView *mapView;

@end

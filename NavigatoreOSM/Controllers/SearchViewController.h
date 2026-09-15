#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

@protocol SearchViewControllerDelegate <NSObject>
- (void)searchViewControllerDidSelectLocation:(CLLocationCoordinate2D)coordinate title:(NSString *)title;
@optional
- (void)searchViewControllerDidRequestShowAllPOIs:(NSArray<MKPointAnnotation *> *)annotations categoryName:(NSString *)categoryName;
@end

@interface SearchViewController : UIViewController

@property (nonatomic, weak) id<SearchViewControllerDelegate> delegate;
@property (nonatomic, assign) CLLocationCoordinate2D userLocation;

@end

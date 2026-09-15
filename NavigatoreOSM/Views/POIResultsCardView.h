#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

@class POIResultsCardView;

@protocol POIResultsCardViewDelegate <NSObject>
- (void)poiResultsCardView:(POIResultsCardView *)card didSelectNavigateToPOI:(MKPointAnnotation *)annotation;
@end

@interface POIResultsCardView : UIView

@property (nonatomic, weak) id<POIResultsCardViewDelegate> delegate;

- (void)showWithAnnotations:(NSArray<MKPointAnnotation *> *)annotations
               categoryName:(NSString *)categoryName
            currentLocation:(CLLocation *)currentLocation;
- (void)dismiss;

@end

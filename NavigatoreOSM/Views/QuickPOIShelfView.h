#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

@class QuickPOIShelfView;

@protocol QuickPOIShelfViewDelegate <NSObject>
- (void)quickPOIShelfView:(QuickPOIShelfView *)shelf didRequestSearchCategory:(NSString *)query categoryName:(NSString *)categoryName;
- (void)quickPOIShelfView:(QuickPOIShelfView *)shelf didFindPOIs:(NSArray<MKPointAnnotation *> *)annotations categoryName:(NSString *)category;
- (void)quickPOIShelfViewDidRequestClose:(QuickPOIShelfView *)shelf;
@end

@interface QuickPOIShelfView : UIView

@property (nonatomic, weak) id<QuickPOIShelfViewDelegate> delegate;

- (void)searchCategory:(NSString *)query fromCoordinate:(CLLocationCoordinate2D)coord categoryName:(NSString *)categoryName;

@end

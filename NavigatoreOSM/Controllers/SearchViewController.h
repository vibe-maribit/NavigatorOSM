#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

@protocol SearchViewControllerDelegate <NSObject>
- (void)searchViewControllerDidSelectLocation:(CLLocationCoordinate2D)coordinate title:(NSString *)title;
@end

@interface SearchViewController : UIViewController

@property (nonatomic, weak) id<SearchViewControllerDelegate> delegate;

@end

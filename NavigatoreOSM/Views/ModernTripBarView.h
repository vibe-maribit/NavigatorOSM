#import <UIKit/UIKit.h>

@interface ModernTripBarView : UIView

@property (nonatomic, copy) void (^onExitBlock)(void);

- (void)updateRemainingDistance:(double)distanceInMeters
                       duration:(NSTimeInterval)duration
                  trafficStatus:(NSString *)traffic;

@end

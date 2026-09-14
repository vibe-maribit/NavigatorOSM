#import <UIKit/UIKit.h>

@class ManeuverStep;

@interface ManeuverHUDView : UIView

@property (nonatomic, copy) void (^onTapBlock)(void);

- (void)updateWithManeuver:(ManeuverStep *)step distanceToStep:(double)distance;
- (void)updateTripRemainingDistance:(double)distance duration:(NSTimeInterval)duration trafficStatus:(NSString *)traffic;
- (void)reset;

@end

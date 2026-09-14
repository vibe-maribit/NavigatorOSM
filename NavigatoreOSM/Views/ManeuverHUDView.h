#import <UIKit/UIKit.h>

@class ManeuverStep;

@interface ManeuverHUDView : UIView

@property (nonatomic, copy) void (^onTapBlock)(void);

- (void)updateWithManeuver:(ManeuverStep *)step
            distanceToStep:(double)distance
                  nextStep:(ManeuverStep *)nextStep;

- (void)reset;

@end

#import <UIKit/UIKit.h>

@interface SpeedometerView : UIView

@property (nonatomic, assign) int speedLimit; // in km/h (0 = nessun limite)

- (void)updateSpeed:(double)speedInMetersPerSecond;
- (void)cycleSpeedLimit;

@end

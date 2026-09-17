#import <MapKit/MapKit.h>
#import "Services/SpeedCameraService.h"

@interface SpeedCameraAnnotationView : MKAnnotationView

- (void)updateWithCamera:(SpeedCamera *)camera;

@end

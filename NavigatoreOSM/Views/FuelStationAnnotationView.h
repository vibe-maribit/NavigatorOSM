#import <MapKit/MapKit.h>
#import "Services/FuelPriceService.h"

@interface FuelStationAnnotationView : MKAnnotationView

- (void)updateWithStation:(FuelStation *)station fuelType:(FuelType)type;

@end

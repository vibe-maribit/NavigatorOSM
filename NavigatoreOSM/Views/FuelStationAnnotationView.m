#import "FuelStationAnnotationView.h"

@interface FuelStationAnnotationView ()
@property (nonatomic, strong) UIView *pillContainer;
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation FuelStationAnnotationView

- (instancetype)initWithAnnotation:(id<MKAnnotation>)annotation reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithAnnotation:annotation reuseIdentifier:reuseIdentifier];
    if (self) {
        self.frame = CGRectMake(0, 0, 84, 28);
        self.centerOffset = CGPointMake(0, -14);
        self.canShowCallout = YES;
        self.backgroundColor = [UIColor clearColor];

        _pillContainer = [[UIView alloc] initWithFrame:self.bounds];
        _pillContainer.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
        _pillContainer.layer.cornerRadius = 14.0;
        _pillContainer.layer.borderColor = [[UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:1.0] CGColor]; // Verde carburanti
        _pillContainer.layer.borderWidth = 1.8;
        _pillContainer.layer.shadowColor = [[UIColor blackColor] CGColor];
        _pillContainer.layer.shadowOpacity = 0.45;
        _pillContainer.layer.shadowRadius = 3.0;
        _pillContainer.layer.shadowOffset = CGSizeMake(0, 2);
        [self addSubview:_pillContainer];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 2, 72, 24)];
        _titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.7;
        [_pillContainer addSubview:_titleLabel];

        // Bottone di navigazione nel callout
        UIButton *navBtn = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        self.rightCalloutAccessoryView = navBtn;

        if ([annotation isKindOfClass:[FuelStationAnnotation class]]) {
            FuelStationAnnotation *fAnn = (FuelStationAnnotation *)annotation;
            [self updateWithStation:fAnn.station fuelType:fAnn.fuelType];
        }
    }
    return self;
}

- (void)setAnnotation:(id<MKAnnotation>)annotation {
    [super setAnnotation:annotation];
    if ([annotation isKindOfClass:[FuelStationAnnotation class]]) {
        FuelStationAnnotation *fAnn = (FuelStationAnnotation *)annotation;
        [self updateWithStation:fAnn.station fuelType:fAnn.fuelType];
    }
}

- (void)updateWithStation:(FuelStation *)station fuelType:(FuelType)type {
    if (!station) return;

    double p = [station effectivePriceForFuelType:type];
    NSString *bName = (station.brand && station.brand.length > 0) ? station.brand : (station.name ?: @"Distributore");

    // Limita lunghezza brand per il badge
    if (bName.length > 8) {
        bName = [bName substringToIndex:8];
    }

    if (p > 0.1) {
        self.titleLabel.text = [NSString stringWithFormat:@"⛽ %@ %.2f€", bName, p];
    } else {
        self.titleLabel.text = [NSString stringWithFormat:@"⛽ %@", bName];
    }

    // Calcola dimensione dinamica del pill
    CGSize fitSize = [self.titleLabel.text sizeWithAttributes:@{NSFontAttributeName: self.titleLabel.font}];
    CGFloat width = MAX(74.0, fitSize.width + 18.0);
    self.frame = CGRectMake(0, 0, width, 28);
    self.pillContainer.frame = self.bounds;
    self.titleLabel.frame = CGRectMake(4, 2, width - 8, 24);
    self.centerOffset = CGPointMake(0, -14);
}

@end

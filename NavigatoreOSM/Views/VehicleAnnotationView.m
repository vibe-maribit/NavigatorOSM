#import "VehicleAnnotationView.h"

@implementation VehicleAnnotation

- (instancetype)init {
    self = [super init];
    if (self) {
        _coordinate = CLLocationCoordinate2DMake(0, 0);
        _heading = 0.0;
        _speed = 0.0;
        _title = @"Veicolo";
    }
    return self;
}

- (void)updateCoordinate:(CLLocationCoordinate2D)newCoordinate heading:(CLLocationDirection)newHeading {
    [self willChangeValueForKey:@"coordinate"];
    _coordinate = newCoordinate;
    _heading = newHeading;
    [self didChangeValueForKey:@"coordinate"];
}

- (void)setCoordinate:(CLLocationCoordinate2D)newCoordinate {
    [self willChangeValueForKey:@"coordinate"];
    _coordinate = newCoordinate;
    [self didChangeValueForKey:@"coordinate"];
}

@end

@interface VehicleAnnotationView ()
@property (nonatomic, strong) UIView *puckContainer;
@property (nonatomic, strong) UIView *arrowView;
@property (nonatomic, strong) CAShapeLayer *arrowLayer;
@end

@implementation VehicleAnnotationView

- (instancetype)initWithAnnotation:(id<MKAnnotation>)annotation reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithAnnotation:annotation reuseIdentifier:reuseIdentifier];
    if (self) {
        self.frame = CGRectMake(0, 0, 44, 44);
        self.centerOffset = CGPointMake(0, 0);
        self.canShowCallout = NO;
        self.backgroundColor = [UIColor clearColor];

        // 1. Contenitore Disco Esterno (Puck)
        _puckContainer = [[UIView alloc] initWithFrame:CGRectMake(4, 4, 36, 36)];
        _puckContainer.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
        _puckContainer.layer.cornerRadius = 18.0;
        _puckContainer.layer.borderColor = [[UIColor whiteColor] CGColor];
        _puckContainer.layer.borderWidth = 2.5;

        // Ombra 3D realistica da cruscotto
        _puckContainer.layer.shadowColor = [[UIColor blackColor] CGColor];
        _puckContainer.layer.shadowOpacity = 0.45;
        _puckContainer.layer.shadowRadius = 4.0;
        _puckContainer.layer.shadowOffset = CGSizeMake(0, 2.5);

        // 2. Contenitore Freccia Direzionale Rotante
        _arrowView = [[UIView alloc] initWithFrame:_puckContainer.bounds];
        _arrowView.backgroundColor = [UIColor clearColor];

        // Disegna una freccia / chevron aerodinamica bianca ad alta visibilità
        _arrowLayer = [CAShapeLayer layer];
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(18.0, 7.0)];     // Vertice superiore
        [path addLineToPoint:CGPointMake(28.0, 27.0)]; // Ala destra
        [path addLineToPoint:CGPointMake(18.0, 22.0)]; // Rientranza centrale
        [path addLineToPoint:CGPointMake(8.0, 27.0)];  // Ala sinistra
        [path closePath];

        _arrowLayer.path = [path CGPath];
        _arrowLayer.fillColor = [[UIColor whiteColor] CGColor];
        _arrowLayer.strokeColor = [[UIColor colorWithWhite:0.1 alpha:0.25] CGColor];
        _arrowLayer.lineWidth = 1.0;
        _arrowLayer.shadowColor = [[UIColor blackColor] CGColor];
        _arrowLayer.shadowOpacity = 0.3;
        _arrowLayer.shadowRadius = 1.5;
        _arrowLayer.shadowOffset = CGSizeMake(0, 1.0);

        [_arrowView.layer addSublayer:_arrowLayer];
        [_puckContainer addSubview:_arrowView];
        [self addSubview:_puckContainer];
    }
    return self;
}

- (void)updateHeading:(CLLocationDirection)heading cameraHeading:(CLLocationDirection)cameraHeading {
    double relative = heading - cameraHeading;
    while (relative < -180.0) relative += 360.0;
    while (relative > 180.0) relative -= 360.0;
    
    self.arrowView.transform = CGAffineTransformMakeRotation(relative * (M_PI / 180.0));
}

@end

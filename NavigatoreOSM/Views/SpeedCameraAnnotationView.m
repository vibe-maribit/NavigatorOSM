#import "SpeedCameraAnnotationView.h"

@interface SpeedCameraAnnotationView ()
@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UIView *limitBadge;
@property (nonatomic, strong) UILabel *limitLabel;
@end

@implementation SpeedCameraAnnotationView

- (instancetype)initWithAnnotation:(id<MKAnnotation>)annotation reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithAnnotation:annotation reuseIdentifier:reuseIdentifier];
    if (self) {
        self.frame = CGRectMake(0, 0, 40, 40);
        self.centerOffset = CGPointMake(0, -8);
        self.canShowCallout = YES;
        self.backgroundColor = [UIColor clearColor];

        // 1. Bolla principale con icona telecamera
        _bubbleView = [[UIView alloc] initWithFrame:CGRectMake(2, 4, 32, 32)];
        _bubbleView.backgroundColor = [UIColor colorWithRed:0.18 green:0.22 blue:0.28 alpha:0.95];
        _bubbleView.layer.cornerRadius = 16.0;
        _bubbleView.layer.borderColor = [[UIColor colorWithRed:1.0 green:0.45 blue:0.1 alpha:1.0] CGColor]; // Bordo arancione velox
        _bubbleView.layer.borderWidth = 2.0;
        _bubbleView.layer.shadowColor = [[UIColor blackColor] CGColor];
        _bubbleView.layer.shadowOpacity = 0.45;
        _bubbleView.layer.shadowRadius = 3.5;
        _bubbleView.layer.shadowOffset = CGSizeMake(0, 2);
        [self addSubview:_bubbleView];

        _iconLabel = [[UILabel alloc] initWithFrame:_bubbleView.bounds];
        _iconLabel.textAlignment = NSTextAlignmentCenter;
        _iconLabel.font = [UIFont systemFontOfSize:16.0];
        _iconLabel.text = @"📷";
        [_bubbleView addSubview:_iconLabel];

        // 2. Mini segnale limite di velocità in alto a destra
        _limitBadge = [[UIView alloc] initWithFrame:CGRectMake(20, 0, 18, 18)];
        _limitBadge.backgroundColor = [UIColor whiteColor];
        _limitBadge.layer.cornerRadius = 9.0;
        _limitBadge.layer.borderColor = [[UIColor colorWithRed:0.9 green:0.1 blue:0.1 alpha:1.0] CGColor]; // Bordo rosso
        _limitBadge.layer.borderWidth = 1.8;
        _limitBadge.layer.shadowColor = [[UIColor blackColor] CGColor];
        _limitBadge.layer.shadowOpacity = 0.35;
        _limitBadge.layer.shadowRadius = 2.0;
        _limitBadge.layer.shadowOffset = CGSizeMake(0, 1);

        _limitLabel = [[UILabel alloc] initWithFrame:_limitBadge.bounds];
        _limitLabel.textAlignment = NSTextAlignmentCenter;
        _limitLabel.font = [UIFont boldSystemFontOfSize:8.5];
        _limitLabel.textColor = [UIColor blackColor];
        [_limitBadge addSubview:_limitLabel];

        [self addSubview:_limitBadge];
        _limitBadge.hidden = YES;

        if ([annotation isKindOfClass:[SpeedCameraAnnotation class]]) {
            [self updateWithCamera:((SpeedCameraAnnotation *)annotation).camera];
        }
    }
    return self;
}

- (void)setAnnotation:(id<MKAnnotation>)annotation {
    [super setAnnotation:annotation];
    if ([annotation isKindOfClass:[SpeedCameraAnnotation class]]) {
        [self updateWithCamera:((SpeedCameraAnnotation *)annotation).camera];
    }
}

- (void)updateWithCamera:(SpeedCamera *)camera {
    if (!camera) return;

    // Cambia colore bordo in base alla tipologia
    if (camera.type == SpeedCameraTypeTutor) {
        self.bubbleView.layer.borderColor = [[UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0] CGColor]; // Azzurro per tutor
        self.iconLabel.text = @"⏱️";
    } else if (camera.type == SpeedCameraTypeTrafficLight) {
        self.bubbleView.layer.borderColor = [[UIColor colorWithRed:1.0 green:0.25 blue:0.2 alpha:1.0] CGColor]; // Rosso per semafori
        self.iconLabel.text = @"🚦";
    } else {
        self.bubbleView.layer.borderColor = [[UIColor colorWithRed:1.0 green:0.55 blue:0.0 alpha:1.0] CGColor]; // Arancione classico
        self.iconLabel.text = @"📷";
    }

    if (camera.speedLimit > 0) {
        self.limitBadge.hidden = NO;
        self.limitLabel.text = [NSString stringWithFormat:@"%d", camera.speedLimit];
    } else {
        self.limitBadge.hidden = YES;
    }
}

@end

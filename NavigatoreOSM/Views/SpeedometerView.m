#import "SpeedometerView.h"

@interface SpeedometerView ()
@property (nonatomic, strong) UIView *circleContainer;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *unitLabel;
@property (nonatomic, strong) UIView *limitSignView;
@property (nonatomic, strong) UILabel *limitSignLabel;
@property (nonatomic, assign) int currentKmh;
@end

@implementation SpeedometerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = NO;

        _speedLimit = 0;
        _currentKmh = 0;

        CGFloat size = MIN(frame.size.width, frame.size.height);

        // Contenitore Circolare Principale Stile Waze
        _circleContainer = [[UIView alloc] initWithFrame:CGRectMake((frame.size.width - size)/2.0, (frame.size.height - size)/2.0, size, size)];
        _circleContainer.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
        _circleContainer.layer.cornerRadius = size / 2.0;
        _circleContainer.layer.borderColor = [[UIColor colorWithRed:0.2 green:0.8 blue:0.5 alpha:0.8] CGColor];
        _circleContainer.layer.borderWidth = 2.5;
        _circleContainer.layer.shadowColor = [[UIColor blackColor] CGColor];
        _circleContainer.layer.shadowOpacity = 0.6;
        _circleContainer.layer.shadowRadius = 8.0;
        _circleContainer.layer.shadowOffset = CGSizeMake(0, 3);
        _circleContainer.clipsToBounds = YES;
        [self addSubview:_circleContainer];

        // Numero velocità grande al centro
        _speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, size * 0.14, size, size * 0.50)];
        _speedLabel.textAlignment = NSTextAlignmentCenter;
        _speedLabel.textColor = [UIColor whiteColor];
        _speedLabel.font = [UIFont boldSystemFontOfSize:38.0];
        _speedLabel.text = @"0";
        [_circleContainer addSubview:_speedLabel];

        // Etichetta KM/H sotto
        _unitLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, size * 0.62, size, 16)];
        _unitLabel.textAlignment = NSTextAlignmentCenter;
        _unitLabel.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.5 alpha:1.0];
        _unitLabel.font = [UIFont boldSystemFontOfSize:11.0];
        _unitLabel.text = @"KM/H";
        [_circleContainer addSubview:_unitLabel];

        // Segnale Stradale del Limite di Velocità (Cerchio Bianco con Bordo Rosso)
        CGFloat signSize = 32.0;
        _limitSignView = [[UIView alloc] initWithFrame:CGRectMake(frame.size.width - signSize, 0, signSize, signSize)];
        _limitSignView.backgroundColor = [UIColor whiteColor];
        _limitSignView.layer.cornerRadius = signSize / 2.0;
        _limitSignView.layer.borderColor = [[UIColor colorWithRed:0.9 green:0.15 blue:0.15 alpha:1.0] CGColor];
        _limitSignView.layer.borderWidth = 3.5;
        _limitSignView.layer.shadowColor = [[UIColor blackColor] CGColor];
        _limitSignView.layer.shadowOpacity = 0.5;
        _limitSignView.layer.shadowRadius = 4.0;
        _limitSignView.layer.shadowOffset = CGSizeMake(0, 2);
        _limitSignView.hidden = YES;
        [self addSubview:_limitSignView];

        _limitSignLabel = [[UILabel alloc] initWithFrame:_limitSignView.bounds];
        _limitSignLabel.textAlignment = NSTextAlignmentCenter;
        _limitSignLabel.textColor = [UIColor blackColor];
        _limitSignLabel.font = [UIFont boldSystemFontOfSize:13.0];
        _limitSignLabel.text = @"50";
        [_limitSignView addSubview:_limitSignLabel];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cycleSpeedLimit)];
        [self addGestureRecognizer:tap];
        self.userInteractionEnabled = YES;
    }
    return self;
}

- (void)cycleSpeedLimit {
    int limits[] = {0, 50, 70, 90, 110, 130};
    int currentIdx = 0;
    for (int i = 0; i < 6; i++) {
        if (limits[i] == self.speedLimit) {
            currentIdx = i;
            break;
        }
    }
    int nextIdx = (currentIdx + 1) % 6;
    self.speedLimit = limits[nextIdx];

    if (self.speedLimit > 0) {
        self.limitSignLabel.text = [NSString stringWithFormat:@"%d", self.speedLimit];
        self.limitSignView.hidden = NO;
    } else {
        self.limitSignView.hidden = YES;
    }

    [self refreshVisualAlert];
}

- (void)setDynamicSpeedLimit:(int)limit {
    if (self.speedLimit == limit) return;
    self.speedLimit = limit;
    if (limit > 0) {
        self.limitSignLabel.text = [NSString stringWithFormat:@"%d", limit];
        self.limitSignView.hidden = NO;
    } else {
        self.limitSignView.hidden = YES;
    }
    [self refreshVisualAlert];
}

- (void)updateSpeed:(double)speedInMetersPerSecond {
    if (speedInMetersPerSecond < 0) {
        self.currentKmh = 0;
    } else {
        self.currentKmh = (int)round(speedInMetersPerSecond * 3.6);
    }
    self.speedLabel.text = [NSString stringWithFormat:@"%d", self.currentKmh];
    [self refreshVisualAlert];
}

- (void)refreshVisualAlert {
    BOOL isOverSpeed = (self.speedLimit > 0 && self.currentKmh > self.speedLimit + 2);

    if (isOverSpeed) {
        self.circleContainer.backgroundColor = [UIColor colorWithRed:0.85 green:0.12 blue:0.12 alpha:0.96];
        self.circleContainer.layer.borderColor = [[UIColor yellowColor] CGColor];
        self.circleContainer.layer.borderWidth = 3.5;
        self.speedLabel.textColor = [UIColor yellowColor];
        self.unitLabel.textColor = [UIColor whiteColor];
        self.unitLabel.text = @"ECCESSO!";
    } else {
        self.circleContainer.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
        self.circleContainer.layer.borderColor = [[UIColor colorWithRed:0.2 green:0.8 blue:0.5 alpha:0.8] CGColor];
        self.circleContainer.layer.borderWidth = 2.5;
        self.speedLabel.textColor = [UIColor whiteColor];
        self.unitLabel.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.5 alpha:1.0];
        self.unitLabel.text = @"KM/H";
    }
}

@end

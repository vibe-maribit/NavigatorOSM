#import "SpeedometerView.h"

@interface SpeedometerView ()
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *unitLabel;
@property (nonatomic, strong) UILabel *limitBadgeLabel;
@property (nonatomic, assign) int currentKmh;
@end

@implementation SpeedometerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
        self.layer.cornerRadius = 14.0;
        self.layer.borderColor = [[UIColor colorWithWhite:0.3 alpha:0.6] CGColor];
        self.layer.borderWidth = 1.0;
        self.clipsToBounds = YES;

        _speedLimit = 0; // 0 = nessun limite attivo
        _currentKmh = 0;

        _speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 6, frame.size.width, frame.size.height * 0.50)];
        _speedLabel.textAlignment = NSTextAlignmentCenter;
        _speedLabel.textColor = [UIColor whiteColor];
        _speedLabel.font = [UIFont boldSystemFontOfSize:34.0];
        _speedLabel.text = @"0";
        [self addSubview:_speedLabel];

        _unitLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, frame.size.height * 0.52, frame.size.width, 18)];
        _unitLabel.textAlignment = NSTextAlignmentCenter;
        _unitLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
        _unitLabel.font = [UIFont boldSystemFontOfSize:12.0];
        _unitLabel.text = @"KM/H";
        [self addSubview:_unitLabel];

        _limitBadgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, frame.size.height * 0.72, frame.size.width, 18)];
        _limitBadgeLabel.textAlignment = NSTextAlignmentCenter;
        _limitBadgeLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
        _limitBadgeLabel.font = [UIFont boldSystemFontOfSize:10.0];
        _limitBadgeLabel.text = @"Lim: Off";
        [self addSubview:_limitBadgeLabel];

        // Tocco per cambiare soglia limite
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
        self.limitBadgeLabel.text = [NSString stringWithFormat:@"Lim: %d", self.speedLimit];
    } else {
        self.limitBadgeLabel.text = @"Lim: Off";
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
        self.backgroundColor = [UIColor colorWithRed:0.85 green:0.1 blue:0.1 alpha:0.95];
        self.layer.borderColor = [[UIColor yellowColor] CGColor];
        self.layer.borderWidth = 2.0;
        self.unitLabel.textColor = [UIColor yellowColor];
        self.limitBadgeLabel.textColor = [UIColor whiteColor];
        self.limitBadgeLabel.text = [NSString stringWithFormat:@"LIMITE %d!", self.speedLimit];
    } else {
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
        self.layer.borderColor = [[UIColor colorWithWhite:0.3 alpha:0.6] CGColor];
        self.layer.borderWidth = 1.0;
        self.unitLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
        if (self.speedLimit > 0) {
            self.limitBadgeLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
            self.limitBadgeLabel.text = [NSString stringWithFormat:@"Lim: %d", self.speedLimit];
        } else {
            self.limitBadgeLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
            self.limitBadgeLabel.text = @"Lim: Off";
        }
    }
}

@end

#import "SpeedometerView.h"

@interface SpeedometerView ()
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *unitLabel;
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

        _speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, frame.size.width, frame.size.height * 0.55)];
        _speedLabel.textAlignment = NSTextAlignmentCenter;
        _speedLabel.textColor = [UIColor whiteColor];
        _speedLabel.font = [UIFont boldSystemFontOfSize:36.0];
        _speedLabel.text = @"0";
        [self addSubview:_speedLabel];

        _unitLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, frame.size.height * 0.60, frame.size.width, frame.size.height * 0.3)];
        _unitLabel.textAlignment = NSTextAlignmentCenter;
        _unitLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
        _unitLabel.font = [UIFont boldSystemFontOfSize:14.0];
        _unitLabel.text = @"KM/H";
        [self addSubview:_unitLabel];
    }
    return self;
}

- (void)updateSpeed:(double)speedInMetersPerSecond {
    if (speedInMetersPerSecond < 0) {
        self.speedLabel.text = @"0";
        return;
    }
    int kmh = (int)round(speedInMetersPerSecond * 3.6);
    self.speedLabel.text = [NSString stringWithFormat:@"%d", kmh];
}

@end

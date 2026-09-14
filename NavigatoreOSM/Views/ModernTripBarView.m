#import "ModernTripBarView.h"

@interface ModernTripBarView ()

@property (nonatomic, strong) UILabel *etaLabel;
@property (nonatomic, strong) UILabel *statsLabel;
@property (nonatomic, strong) UILabel *trafficLabel;
@property (nonatomic, strong) UIButton *exitButton;

@end

@implementation ModernTripBarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
        self.layer.cornerRadius = 20.0;
        self.layer.borderColor = [[UIColor colorWithWhite:0.3 alpha:0.7] CGColor];
        self.layer.borderWidth = 1.0;
        self.layer.shadowColor = [[UIColor blackColor] CGColor];
        self.layer.shadowOpacity = 0.55;
        self.layer.shadowRadius = 10.0;
        self.layer.shadowOffset = CGSizeMake(0, -3);

        // Orario di arrivo grande (stile Google Maps)
        _etaLabel = [[UILabel alloc] initWithFrame:CGRectMake(22, 10, 120, 32)];
        _etaLabel.font = [UIFont boldSystemFontOfSize:26.0];
        _etaLabel.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.45 alpha:1.0];
        _etaLabel.text = @"--:--";
        [self addSubview:_etaLabel];

        // Dettagli minuti e km
        _statsLabel = [[UILabel alloc] initWithFrame:CGRectMake(142, 12, frame.size.width - 215, 28)];
        _statsLabel.font = [UIFont boldSystemFontOfSize:18.0];
        _statsLabel.textColor = [UIColor whiteColor];
        _statsLabel.text = @"In attesa di rotta...";
        [self addSubview:_statsLabel];

        // Badge traffico sotto
        _trafficLabel = [[UILabel alloc] initWithFrame:CGRectMake(22, 40, frame.size.width - 95, 20)];
        _trafficLabel.font = [UIFont systemFontOfSize:13.0];
        _trafficLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
        _trafficLabel.text = @"🟢 Traffico regolare";
        [self addSubview:_trafficLabel];

        // Pulsante circolare rosso Termina / Esci a destra
        _exitButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _exitButton.frame = CGRectMake(frame.size.width - 56, 12, 44, 44);
        _exitButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        _exitButton.backgroundColor = [UIColor colorWithRed:0.9 green:0.22 blue:0.22 alpha:1.0];
        _exitButton.layer.cornerRadius = 22.0;
        _exitButton.layer.shadowColor = [[UIColor blackColor] CGColor];
        _exitButton.layer.shadowOpacity = 0.4;
        _exitButton.layer.shadowRadius = 4.0;
        _exitButton.layer.shadowOffset = CGSizeMake(0, 2);
        [_exitButton setTitle:@"✕" forState:UIControlStateNormal];
        [_exitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _exitButton.titleLabel.font = [UIFont boldSystemFontOfSize:20.0];
        [_exitButton addTarget:self action:@selector(handleExit) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_exitButton];
    }
    return self;
}

- (void)handleExit {
    if (self.onExitBlock) {
        self.onExitBlock();
    }
}

- (void)updateRemainingDistance:(double)distanceInMeters duration:(NSTimeInterval)duration trafficStatus:(NSString *)traffic {
    int minutes = (int)ceil(duration / 60.0);
    int hours = minutes / 60;
    int remMins = minutes % 60;

    NSString *timeStr = (hours > 0) ? [NSString stringWithFormat:@"%dh %02dmin", hours, remMins]
                                    : [NSString stringWithFormat:@"%d min", minutes];

    NSString *distStr = (distanceInMeters > 1000) ? [NSString stringWithFormat:@"%.1f km", distanceInMeters / 1000.0]
                                                  : [NSString stringWithFormat:@"%d m", (int)round(distanceInMeters)];

    // Calcolo orario esatto di arrivo ETA
    NSDate *arrival = [[NSDate date] dateByAddingTimeInterval:duration];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm";
    self.etaLabel.text = [fmt stringFromDate:arrival];

    self.statsLabel.text = [NSString stringWithFormat:@"%@ • %@", timeStr, distStr];
    self.trafficLabel.text = traffic ?: @"🟢 Traffico regolare";
}

@end

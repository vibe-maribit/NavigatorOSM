#import "ManeuverHUDView.h"
#import "../Services/RoutingService.h"

@interface ManeuverHUDView ()

@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *distanceLabel;
@property (nonatomic, strong) UILabel *streetLabel;
@property (nonatomic, strong) UILabel *tripSummaryLabel;

@end

@implementation ManeuverHUDView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
        self.layer.cornerRadius = 16.0;
        self.layer.borderColor = [[UIColor colorWithWhite:0.35 alpha:0.7] CGColor];
        self.layer.borderWidth = 1.0;
        self.layer.shadowColor = [[UIColor blackColor] CGColor];
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 8.0;
        self.layer.shadowOffset = CGSizeMake(0, 4);

        // Icona svolta (carattere grafico ad alto contrasto)
        _iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 12, 54, 54)];
        _iconLabel.textAlignment = NSTextAlignmentCenter;
        _iconLabel.font = [UIFont systemFontOfSize:38.0];
        _iconLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
        _iconLabel.text = @"↑";
        [self addSubview:_iconLabel];

        // Distanza svolta (es. "300 m")
        _distanceLabel = [[UILabel alloc] initWithFrame:CGRectMake(74, 10, frame.size.width - 85, 28)];
        _distanceLabel.font = [UIFont boldSystemFontOfSize:22.0];
        _distanceLabel.textColor = [UIColor whiteColor];
        _distanceLabel.text = @"In attesa di rotta...";
        [self addSubview:_distanceLabel];

        // Nome via / Istruzione (es. "Via Roma")
        _streetLabel = [[UILabel alloc] initWithFrame:CGRectMake(74, 38, frame.size.width - 85, 26)];
        _streetLabel.font = [UIFont systemFontOfSize:16.0];
        _streetLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
        _streetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _streetLabel.text = @"Imposta una destinazione";
        [self addSubview:_streetLabel];

        // Riepilogo viaggio inferiore (es. "12 km • 18 min")
        _tripSummaryLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 70, frame.size.width - 28, 22)];
        _tripSummaryLabel.font = [UIFont boldSystemFontOfSize:13.0];
        _tripSummaryLabel.textColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0];
        _tripSummaryLabel.text = @"";
        [self addSubview:_tripSummaryLabel];

        // Riconoscimento tocco per ripetere la voce
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
        self.userInteractionEnabled = YES;
    }
    return self;
}

- (void)handleTap {
    if (self.onTapBlock) {
        self.onTapBlock();
    }
}

static NSString *ArrowSymbolForModifier(NSString *modifier, NSString *type) {
    if ([type isEqualToString:@"arrive"]) return @"🏁";
    if ([type isEqualToString:@"roundabout"]) return @"🔄";
    if ([modifier isEqualToString:@"left"]) return @"↰";
    if ([modifier isEqualToString:@"right"]) return @"↱";
    if ([modifier isEqualToString:@"sharp left"]) return @"⮡";
    if ([modifier isEqualToString:@"sharp right"]) return @"⮠";
    if ([modifier isEqualToString:@"slight left"]) return @"↖";
    if ([modifier isEqualToString:@"slight right"]) return @"↗";
    if ([modifier isEqualToString:@"uturn"]) return @"↺";
    return @"↑";
}

- (void)updateWithManeuver:(ManeuverStep *)step distanceToStep:(double)distance {
    if (!step) {
        [self reset];
        return;
    }

    self.iconLabel.text = ArrowSymbolForModifier(step.modifier, step.type);

    if (distance > 1000) {
        self.distanceLabel.text = [NSString stringWithFormat:@"%.1f km", distance / 1000.0];
    } else {
        self.distanceLabel.text = [NSString stringWithFormat:@"%d m", (int)round(distance)];
    }

    self.streetLabel.text = (step.streetName.length > 0) ? step.streetName : step.instruction;
}

- (void)updateTripRemainingDistance:(double)distance duration:(NSTimeInterval)duration {
    int minutes = (int)ceil(duration / 60.0);
    int hours = minutes / 60;
    int remMins = minutes % 60;

    NSString *timeStr = (hours > 0) ? [NSString stringWithFormat:@"%dh %02dmin", hours, remMins]
                                    : [NSString stringWithFormat:@"%d min", minutes];

    NSString *distStr = (distance > 1000) ? [NSString stringWithFormat:@"%.1f km", distance / 1000.0]
                                          : [NSString stringWithFormat:@"%d m", (int)round(distance)];

    self.tripSummaryLabel.text = [NSString stringWithFormat:@"%@ • %@", distStr, timeStr];
}

- (void)reset {
    self.iconLabel.text = @"🧭";
    self.distanceLabel.text = @"Navigatore OSM";
    self.streetLabel.text = @"Tocca 'Cerca' per iniziare";
    self.tripSummaryLabel.text = @"Pronto";
}

@end

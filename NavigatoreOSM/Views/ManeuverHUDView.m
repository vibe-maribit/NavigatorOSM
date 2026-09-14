#import "ManeuverHUDView.h"
#import "../Services/RoutingService.h"

@interface ManeuverHUDView ()

@property (nonatomic, strong) UIView *mainCard;
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *distanceLabel;
@property (nonatomic, strong) UILabel *streetLabel;

@property (nonatomic, strong) UIView *subCard;
@property (nonatomic, strong) UILabel *subLabel;

@end

@implementation ManeuverHUDView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = NO;

        // Scheda Principale Verde Smeraldo Waze (#00875A)
        CGFloat mainH = frame.size.height - 28.0;
        _mainCard = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, mainH)];
        _mainCard.backgroundColor = [UIColor colorWithRed:0.0 green:0.53 blue:0.35 alpha:0.96]; // #00875A
        _mainCard.layer.cornerRadius = 18.0;
        _mainCard.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.25] CGColor];
        _mainCard.layer.borderWidth = 1.0;
        _mainCard.layer.shadowColor = [[UIColor blackColor] CGColor];
        _mainCard.layer.shadowOpacity = 0.55;
        _mainCard.layer.shadowRadius = 10.0;
        _mainCard.layer.shadowOffset = CGSizeMake(0, 4);
        [self addSubview:_mainCard];

        // Icona svolta grande a sinistra
        _iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 6, 60, mainH - 12)];
        _iconLabel.textAlignment = NSTextAlignmentCenter;
        _iconLabel.font = [UIFont systemFontOfSize:42.0];
        _iconLabel.textColor = [UIColor whiteColor];
        _iconLabel.text = @"↑";
        [_mainCard addSubview:_iconLabel];

        // Distanza (es. "350 m")
        _distanceLabel = [[UILabel alloc] initWithFrame:CGRectMake(78, 6, frame.size.width - 90, 32)];
        _distanceLabel.font = [UIFont boldSystemFontOfSize:26.0];
        _distanceLabel.textColor = [UIColor whiteColor];
        _distanceLabel.text = @"Navigatore OSM";
        [_mainCard addSubview:_distanceLabel];

        // Nome della strada in evidenza
        _streetLabel = [[UILabel alloc] initWithFrame:CGRectMake(78, 38, frame.size.width - 90, 26)];
        _streetLabel.font = [UIFont boldSystemFontOfSize:17.0];
        _streetLabel.textColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        _streetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _streetLabel.text = @"Pronto per la guida";
        [_mainCard addSubview:_streetLabel];

        // Subcard inferiore per la manovra successiva ("Poi ↰ in ...")
        _subCard = [[UIView alloc] initWithFrame:CGRectMake(12, mainH - 4, frame.size.width - 24, 28)];
        _subCard.backgroundColor = [UIColor colorWithRed:0.0 green:0.42 blue:0.28 alpha:0.95];
        _subCard.layer.cornerRadius = 10.0;
        _subCard.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.18] CGColor];
        _subCard.layer.borderWidth = 1.0;
        _subCard.hidden = YES;
        [self addSubview:_subCard];

        _subLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 2, _subCard.bounds.size.width - 20, 24)];
        _subLabel.font = [UIFont boldSystemFontOfSize:12.0];
        _subLabel.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        _subLabel.text = @"";
        [_subCard addSubview:_subLabel];

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

- (void)updateWithManeuver:(ManeuverStep *)step
            distanceToStep:(double)distance
                  nextStep:(ManeuverStep *)nextStep {
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

    // Anteprima seconda manovra
    if (nextStep && nextStep.streetName.length > 0) {
        NSString *nextSymbol = ArrowSymbolForModifier(nextStep.modifier, nextStep.type);
        self.subLabel.text = [NSString stringWithFormat:@"Poi %@ su %@", nextSymbol, nextStep.streetName];
        self.subCard.hidden = NO;
    } else {
        self.subCard.hidden = YES;
    }
}

- (void)reset {
    self.iconLabel.text = @"🧭";
    self.distanceLabel.text = @"Navigatore OSM";
    self.streetLabel.text = @"Tocca 'Cerca' o 'POI' per iniziare";
    self.subCard.hidden = YES;
}

@end

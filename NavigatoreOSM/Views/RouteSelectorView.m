#import "RouteSelectorView.h"
#import "../Services/LocalizationManager.h"
#import "../Services/FuelPriceService.h"
#import "../Services/TollGuruService.h"

@interface RouteSelectorView ()

@property (nonatomic, strong) NSArray<RouteInfo *> *routes;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, strong) NSMutableArray<UIButton *> *routeButtons;

// Barra opzioni al volo
@property (nonatomic, strong) UIView *optionsBar;
@property (nonatomic, strong) UILabel *optionsLabel;
@property (nonatomic, strong) UIButton *tollsChipButton;
@property (nonatomic, strong) UIButton *highwaysChipButton;
@property (nonatomic, strong) UILabel *costSummaryLabel;

// Schede percorsi
@property (nonatomic, strong) UIView *buttonsContainer;

// Barra comandi inferiore
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *recalcButton;
@property (nonatomic, strong) UIButton *cancelButton;

@end

@implementation RouteSelectorView

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
        self.layer.cornerRadius = 18.0;
        self.layer.borderColor = [[UIColor colorWithWhite:0.3 alpha:0.8] CGColor];
        self.layer.borderWidth = 1.0;
        self.layer.shadowColor = [[UIColor blackColor] CGColor];
        self.layer.shadowOpacity = 0.6;
        self.layer.shadowRadius = 12.0;
        self.layer.shadowOffset = CGSizeMake(0, -3);

        _routeButtons = [NSMutableArray array];
        _selectedIndex = 0;
        _avoidTolls = NO;
        _avoidHighways = NO;

        // 1. Barra opzioni rapide in alto (Opzioni "al volo")
        _optionsBar = [[UIView alloc] initWithFrame:CGRectZero];
        [self addSubview:_optionsBar];

        _optionsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _optionsLabel.font = [UIFont boldSystemFontOfSize:12.0];
        _optionsLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
        _optionsLabel.text = NLString(@"ROUTE_OPTIONS", @"Opzioni:");
        [_optionsBar addSubview:_optionsLabel];

        // Chip No Pedaggio
        _tollsChipButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _tollsChipButton.layer.cornerRadius = 8.0;
        _tollsChipButton.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
        [_tollsChipButton setTitle:NLString(@"AVOID_TOLLS", @"🚫 No Pedaggio") forState:UIControlStateNormal];
        [_tollsChipButton addTarget:self action:@selector(handleTollsToggled) forControlEvents:UIControlEventTouchUpInside];
        [_optionsBar addSubview:_tollsChipButton];

        // Chip No Autostrade
        _highwaysChipButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _highwaysChipButton.layer.cornerRadius = 8.0;
        _highwaysChipButton.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
        [_highwaysChipButton setTitle:NLString(@"AVOID_HIGHWAYS", @"🛣️ No Autostrade") forState:UIControlStateNormal];
        [_highwaysChipButton addTarget:self action:@selector(handleHighwaysToggled) forControlEvents:UIControlEventTouchUpInside];
        [_optionsBar addSubview:_highwaysChipButton];

        // Etichetta riassuntiva del costo del percorso selezionato
        _costSummaryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _costSummaryLabel.font = [UIFont boldSystemFontOfSize:12.0];
        _costSummaryLabel.textAlignment = NSTextAlignmentRight;
        _costSummaryLabel.textColor = [UIColor colorWithRed:1.0 green:0.82 blue:0.3 alpha:1.0];
        [_optionsBar addSubview:_costSummaryLabel];

        [self updateToggleAppearances];

        // 2. Contenitore card itinerari
        _buttonsContainer = [[UIView alloc] initWithFrame:CGRectZero];
        [self addSubview:_buttonsContainer];

        // 3. Pulsanti azione in basso
        // Pulsante verde "Avvia Navigazione"
        _startButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _startButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.75 blue:0.35 alpha:1.0];
        _startButton.layer.cornerRadius = 12.0;
        [_startButton setTitle:NLString(@"START_NAVIGATION", @"▶ Avvia Navigazione") forState:UIControlStateNormal];
        [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _startButton.titleLabel.font = [UIFont boldSystemFontOfSize:15.5];
        _startButton.titleLabel.adjustsFontSizeToFitWidth = YES;
        _startButton.titleLabel.minimumScaleFactor = 0.7;
        [_startButton addTarget:self action:@selector(handleStart) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_startButton];

        // Pulsante blu "🔄 Altri" (Cerca itinerari alternativi)
        _recalcButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _recalcButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:0.95 alpha:0.95];
        _recalcButton.layer.cornerRadius = 12.0;
        [_recalcButton setTitle:NLString(@"MORE_ROUTES", @"🔄 Altri") forState:UIControlStateNormal];
        [_recalcButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _recalcButton.titleLabel.font = [UIFont boldSystemFontOfSize:13.5];
        _recalcButton.titleLabel.adjustsFontSizeToFitWidth = YES;
        _recalcButton.titleLabel.minimumScaleFactor = 0.7;
        [_recalcButton addTarget:self action:@selector(handleRecalculate) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_recalcButton];

        // Pulsante grigio "Annulla"
        _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _cancelButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.9];
        _cancelButton.layer.cornerRadius = 12.0;
        [_cancelButton setTitle:NLString(@"CANCEL", @"Annulla") forState:UIControlStateNormal];
        [_cancelButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _cancelButton.titleLabel.font = [UIFont systemFontOfSize:13.5];
        _cancelButton.titleLabel.adjustsFontSizeToFitWidth = YES;
        _cancelButton.titleLabel.minimumScaleFactor = 0.7;
        [_cancelButton addTarget:self action:@selector(handleCancel) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_cancelButton];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleLanguageChanged)
                                                     name:kAppLanguagePreferenceChangedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handlePricesUpdated)
                                                     name:kTollPricesUpdatedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handlePricesUpdated)
                                                     name:kFuelPricesUpdatedNotification
                                                   object:nil];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    // Barra opzioni in alto (y: 8, h: 30)
    _optionsBar.frame = CGRectMake(16, 8, w - 32, 30);
    _optionsLabel.frame = CGRectMake(0, 5, 55, 20);

    CGFloat chipW = 120.0;
    _tollsChipButton.frame = CGRectMake(60, 2, chipW, 26);
    _highwaysChipButton.frame = CGRectMake(60 + chipW + 8, 2, 130, 26);

    CGFloat costX = 60 + chipW + 8 + 130 + 8;
    CGFloat costW = (w - 32) - costX;
    if (costW > 80) {
        _costSummaryLabel.frame = CGRectMake(costX, 5, costW, 20);
        _costSummaryLabel.hidden = NO;
    } else {
        _costSummaryLabel.hidden = YES;
    }

    // Barra comandi in basso (y: h - 54, h: 44)
    CGFloat bottomH = 44.0;
    CGFloat totalW = w - 32.0;
    CGFloat spacing = 8.0;
    CGFloat usableW = totalW - spacing * 2.0;
    CGFloat startW = round(usableW * 0.48);
    CGFloat recalcW = round(usableW * 0.28);
    CGFloat cancelW = usableW - startW - recalcW;

    _startButton.frame = CGRectMake(16, h - 54, startW, bottomH);
    _recalcButton.frame = CGRectMake(16 + startW + spacing, h - 54, recalcW, bottomH);
    _cancelButton.frame = CGRectMake(16 + startW + spacing + recalcW + spacing, h - 54, cancelW, bottomH);

    // Contenitore card itinerari tra la barra opzioni e la barra comandi
    CGFloat containerY = 42.0;
    CGFloat containerH = (h - 54 - 6) - containerY;
    _buttonsContainer.frame = CGRectMake(16, containerY, w - 32, containerH);

    // Ricalcola layout dei pulsanti percorso
    if (self.routeButtons.count > 0) {
        CGFloat countF = (CGFloat)self.routeButtons.count;
        CGFloat cardSpacing = 8.0;
        CGFloat cardW = floor(((w - 32) - (countF - 1.0) * cardSpacing) / countF);
        for (NSUInteger i = 0; i < self.routeButtons.count; i++) {
            UIButton *btn = self.routeButtons[i];
            btn.frame = CGRectMake(i * (cardW + cardSpacing), 0, cardW, containerH);
            [self layoutCardSubviewsForButton:btn width:cardW height:containerH];
        }
    }
}

- (void)updateToggleAppearances {
    if (self.avoidTolls) {
        _tollsChipButton.backgroundColor = [UIColor colorWithRed:0.85 green:0.45 blue:0.1 alpha:1.0];
        _tollsChipButton.layer.borderColor = [[UIColor whiteColor] CGColor];
        _tollsChipButton.layer.borderWidth = 1.5;
        [_tollsChipButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    } else {
        _tollsChipButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.8];
        _tollsChipButton.layer.borderColor = [[UIColor colorWithWhite:0.4 alpha:0.5] CGColor];
        _tollsChipButton.layer.borderWidth = 1.0;
        [_tollsChipButton setTitleColor:[UIColor colorWithWhite:0.85 alpha:1.0] forState:UIControlStateNormal];
    }

    if (self.avoidHighways) {
        _highwaysChipButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.55 blue:0.85 alpha:1.0];
        _highwaysChipButton.layer.borderColor = [[UIColor whiteColor] CGColor];
        _highwaysChipButton.layer.borderWidth = 1.5;
        [_highwaysChipButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    } else {
        _highwaysChipButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.8];
        _highwaysChipButton.layer.borderColor = [[UIColor colorWithWhite:0.4 alpha:0.5] CGColor];
        _highwaysChipButton.layer.borderWidth = 1.0;
        [_highwaysChipButton setTitleColor:[UIColor colorWithWhite:0.85 alpha:1.0] forState:UIControlStateNormal];
    }
}

- (void)resetToggles {
    self.avoidTolls = NO;
    self.avoidHighways = NO;
    [self updateToggleAppearances];
}

- (void)handleTollsToggled {
    self.avoidTolls = !self.avoidTolls;
    [self updateToggleAppearances];

    if ([self.delegate respondsToSelector:@selector(routeSelectorView:didToggleAvoidTolls:avoidHighways:)]) {
        [self.delegate routeSelectorView:self didToggleAvoidTolls:self.avoidTolls avoidHighways:self.avoidHighways];
    }
}

- (void)handleHighwaysToggled {
    self.avoidHighways = !self.avoidHighways;
    [self updateToggleAppearances];

    if ([self.delegate respondsToSelector:@selector(routeSelectorView:didToggleAvoidTolls:avoidHighways:)]) {
        [self.delegate routeSelectorView:self didToggleAvoidTolls:self.avoidTolls avoidHighways:self.avoidHighways];
    }
}

- (void)handleLanguageChanged {
    [self.startButton setTitle:NLString(@"START_NAVIGATION", @"▶ Avvia Navigazione") forState:UIControlStateNormal];
    [self.recalcButton setTitle:NLString(@"MORE_ROUTES", @"🔄 Altri") forState:UIControlStateNormal];
    [self.cancelButton setTitle:NLString(@"CANCEL", @"Annulla") forState:UIControlStateNormal];
    [self.tollsChipButton setTitle:NLString(@"AVOID_TOLLS", @"🚫 No Pedaggio") forState:UIControlStateNormal];
    [self.highwaysChipButton setTitle:NLString(@"AVOID_HIGHWAYS", @"🛣️ No Autostrade") forState:UIControlStateNormal];
    self.optionsLabel.text = NLString(@"ROUTE_OPTIONS", @"Opzioni:");
    [self updateCostSummary];
}

- (void)updateCostSummary {
    if (self.selectedIndex < self.routes.count) {
        RouteInfo *r = self.routes[self.selectedIndex];
        if (r.totalTripCost <= 0.01) [r updateTripCosts];
        self.costSummaryLabel.text = [NSString stringWithFormat:@"€ %.2f (Tot)", r.totalTripCost];
    } else {
        self.costSummaryLabel.text = @"";
    }
}

- (void)populateCardLabelsForButton:(UIButton *)btn route:(RouteInfo *)r index:(NSUInteger)idx {
    UILabel *badgeLabel = (UILabel *)[btn viewWithTag:101];
    UILabel *timeLabel = (UILabel *)[btn viewWithTag:102];
    UILabel *distCostLabel = (UILabel *)[btn viewWithTag:103];
    UILabel *roadsLabel = (UILabel *)[btn viewWithTag:104];

    if (!badgeLabel) {
        badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        badgeLabel.tag = 101;
        badgeLabel.font = [UIFont boldSystemFontOfSize:12.5];
        badgeLabel.textAlignment = NSTextAlignmentCenter;
        badgeLabel.layer.cornerRadius = 9.0;
        badgeLabel.layer.masksToBounds = YES;
        badgeLabel.userInteractionEnabled = NO;
        [btn addSubview:badgeLabel];
    }

    if (!timeLabel) {
        timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        timeLabel.tag = 102;
        timeLabel.font = [UIFont boldSystemFontOfSize:24.0];
        timeLabel.textAlignment = NSTextAlignmentCenter;
        timeLabel.userInteractionEnabled = NO;
        timeLabel.adjustsFontSizeToFitWidth = YES;
        timeLabel.minimumScaleFactor = 0.75;
        [btn addSubview:timeLabel];
    }

    if (!distCostLabel) {
        distCostLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        distCostLabel.tag = 103;
        distCostLabel.font = [UIFont boldSystemFontOfSize:14.0];
        distCostLabel.textAlignment = NSTextAlignmentCenter;
        distCostLabel.textColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.35 alpha:1.0];
        distCostLabel.userInteractionEnabled = NO;
        distCostLabel.adjustsFontSizeToFitWidth = YES;
        distCostLabel.minimumScaleFactor = 0.75;
        [btn addSubview:distCostLabel];
    }

    if (!roadsLabel) {
        roadsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        roadsLabel.tag = 104;
        roadsLabel.font = [UIFont systemFontOfSize:13.0];
        roadsLabel.textAlignment = NSTextAlignmentCenter;
        roadsLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
        roadsLabel.userInteractionEnabled = NO;
        roadsLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [btn addSubview:roadsLabel];
    }

    // Imposta contenuti
    NSString *badge = r.badgeTitle ?: ((idx == 0) ? @"⚡ PIÙ VELOCE" : [NSString stringWithFormat:@"🛣️ ITINERARIO %lu", (unsigned long)(idx + 1)]);
    badgeLabel.text = badge;
    if ([badge containsString:@"VELOCE"]) {
        badgeLabel.backgroundColor = [UIColor colorWithRed:0.12 green:0.65 blue:0.30 alpha:0.95];
        badgeLabel.textColor = [UIColor whiteColor];
    } else if ([badge containsString:@"ECONOMICO"]) {
        badgeLabel.backgroundColor = [UIColor colorWithRed:0.85 green:0.55 blue:0.10 alpha:0.95];
        badgeLabel.textColor = [UIColor whiteColor];
    } else {
        badgeLabel.backgroundColor = [UIColor colorWithWhite:0.35 alpha:0.90];
        badgeLabel.textColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    }

    int mins = (int)ceil(r.totalDuration / 60.0);
    if (mins >= 60) {
        timeLabel.text = [NSString stringWithFormat:@"%d h %d m", mins / 60, mins % 60];
    } else {
        timeLabel.text = [NSString stringWithFormat:@"%d min", mins];
    }

    NSString *distStr = (r.totalDistance > 1000) ? [NSString stringWithFormat:@"%.1f km", r.totalDistance / 1000.0]
                                                 : [NSString stringWithFormat:@"%d m", (int)r.totalDistance];

    if (r.totalTripCost <= 0.01) [r updateTripCosts];
    NSString *costStr = (r.tollCost > 0.05)
        ? [NSString stringWithFormat:@"⛽ %.2f€ • 🛣️ %.2f€", r.fuelCost, r.tollCost]
        : [NSString stringWithFormat:@"⛽ %.2f€", r.fuelCost];

    distCostLabel.text = [NSString stringWithFormat:@"%@ • %@", distStr, costStr];
    roadsLabel.text = r.routeSummary.length > 0 ? [NSString stringWithFormat:@"via %@", r.routeSummary] : @"";
}

- (void)layoutCardSubviewsForButton:(UIButton *)btn width:(CGFloat)cardW height:(CGFloat)cardH {
    UILabel *badgeLabel = (UILabel *)[btn viewWithTag:101];
    UILabel *timeLabel = (UILabel *)[btn viewWithTag:102];
    UILabel *distCostLabel = (UILabel *)[btn viewWithTag:103];
    UILabel *roadsLabel = (UILabel *)[btn viewWithTag:104];

    CGFloat pad = 6.0;
    if (badgeLabel) {
        CGFloat badgeW = MIN(cardW - 16.0, 130.0);
        badgeLabel.frame = CGRectMake((cardW - badgeW) / 2.0, 7.0, badgeW, 20.0);
    }
    if (timeLabel) {
        timeLabel.frame = CGRectMake(pad, 30.0, cardW - pad * 2.0, 32.0);
    }
    if (distCostLabel) {
        distCostLabel.frame = CGRectMake(pad, 64.0, cardW - pad * 2.0, 22.0);
    }
    if (roadsLabel) {
        roadsLabel.frame = CGRectMake(pad, 88.0, cardW - pad * 2.0, 20.0);
    }
}

- (void)handlePricesUpdated {
    for (NSUInteger i = 0; i < self.routes.count; i++) {
        RouteInfo *r = self.routes[i];
        [r updateTripCosts];
        if (i < self.routeButtons.count) {
            UIButton *btn = self.routeButtons[i];
            [self populateCardLabelsForButton:btn route:r index:i];
        }
    }
    [self updateCostSummary];
}

- (void)setRoutes:(NSArray<RouteInfo *> *)routes {
    _routes = routes;
    _selectedIndex = 0;

    for (UIView *sub in self.buttonsContainer.subviews) {
        [sub removeFromSuperview];
    }
    [self.routeButtons removeAllObjects];

    if (routes.count == 0) {
        [self updateCostSummary];
        return;
    }

    CGFloat containerW = self.buttonsContainer.bounds.size.width;
    if (containerW <= 0) containerW = self.bounds.size.width - 32.0;
    CGFloat containerH = self.buttonsContainer.bounds.size.height;
    if (containerH <= 0) containerH = 114.0;

    CGFloat cardSpacing = 8.0;
    CGFloat itemW = floor((containerW - (CGFloat)(routes.count - 1) * cardSpacing) / (CGFloat)routes.count);

    for (NSUInteger i = 0; i < routes.count; i++) {
        RouteInfo *r = routes[i];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(i * (itemW + cardSpacing), 0, itemW, containerH);
        btn.layer.cornerRadius = 14.0;
        btn.tag = i;
        [btn addTarget:self action:@selector(handleRouteTapped:) forControlEvents:UIControlEventTouchUpInside];

        [self populateCardLabelsForButton:btn route:r index:i];
        [self layoutCardSubviewsForButton:btn width:itemW height:containerH];

        [self.buttonsContainer addSubview:btn];
        [self.routeButtons addObject:btn];
    }

    [self updateButtonHighlights];
    [self updateCostSummary];
}

- (void)updateButtonHighlights {
    for (NSUInteger i = 0; i < self.routeButtons.count; i++) {
        UIButton *btn = self.routeButtons[i];
        UILabel *timeLabel = (UILabel *)[btn viewWithTag:102];
        if (i == self.selectedIndex) {
            btn.backgroundColor = [UIColor colorWithRed:0.0 green:0.38 blue:0.88 alpha:0.95];
            btn.layer.borderColor = [[UIColor whiteColor] CGColor];
            btn.layer.borderWidth = 2.5;
            if (timeLabel) timeLabel.textColor = [UIColor whiteColor];
        } else {
            btn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.85];
            btn.layer.borderColor = [[UIColor colorWithWhite:0.4 alpha:0.5] CGColor];
            btn.layer.borderWidth = 1.0;
            if (timeLabel) timeLabel.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        }
    }
}

- (void)handleRouteTapped:(UIButton *)sender {
    self.selectedIndex = sender.tag;
    [self updateButtonHighlights];
    [self updateCostSummary];

    if ([self.delegate respondsToSelector:@selector(routeSelectorView:didSelectRouteIndex:)]) {
        [self.delegate routeSelectorView:self didSelectRouteIndex:self.selectedIndex];
    }
}

- (void)handleStart {
    if (self.selectedIndex < self.routes.count) {
        RouteInfo *chosen = self.routes[self.selectedIndex];
        if ([self.delegate respondsToSelector:@selector(routeSelectorView:didConfirmStartRoute:)]) {
            [self.delegate routeSelectorView:self didConfirmStartRoute:chosen];
        }
    }
}

- (void)handleRecalculate {
    if ([self.delegate respondsToSelector:@selector(routeSelectorViewDidRequestRecalculate:)]) {
        [self.delegate routeSelectorViewDidRequestRecalculate:self];
    }
}

- (void)handleCancel {
    if ([self.delegate respondsToSelector:@selector(routeSelectorViewDidCancel:)]) {
        [self.delegate routeSelectorViewDidCancel:self];
    }
}

@end

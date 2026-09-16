#import "RouteSelectorView.h"
#import "../Services/LocalizationManager.h"

@interface RouteSelectorView ()
@property (nonatomic, strong) NSArray<RouteInfo *> *routes;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, strong) NSMutableArray<UIButton *> *routeButtons;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIView *buttonsContainer;
@end

@implementation RouteSelectorView

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

        _buttonsContainer = [[UIView alloc] initWithFrame:CGRectMake(16, 12, frame.size.width - 32, frame.size.height - 75)];
        _buttonsContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_buttonsContainer];

        // Pulsante verde "Avvia Navigazione"
        CGFloat btnW = (frame.size.width - 44) * 0.72;
        _startButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _startButton.frame = CGRectMake(16, frame.size.height - 58, btnW, 46);
        _startButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        _startButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.75 blue:0.35 alpha:1.0];
        _startButton.layer.cornerRadius = 12.0;
        [_startButton setTitle:NLString(@"START_NAVIGATION", @"▶ Avvia Navigazione") forState:UIControlStateNormal];
        [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _startButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
        [_startButton addTarget:self action:@selector(handleStart) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_startButton];

        // Pulsante Annulla
        CGFloat cancelX = 16 + btnW + 12;
        CGFloat cancelW = frame.size.width - cancelX - 16;
        _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _cancelButton.frame = CGRectMake(cancelX, frame.size.height - 58, cancelW, 46);
        _cancelButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
        _cancelButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.9];
        _cancelButton.layer.cornerRadius = 12.0;
        [_cancelButton setTitle:NLString(@"CANCEL", @"Annulla") forState:UIControlStateNormal];
        [_cancelButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _cancelButton.titleLabel.font = [UIFont systemFontOfSize:15.0];
        [_cancelButton addTarget:self action:@selector(handleCancel) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_cancelButton];
    }
    return self;
}

- (void)setRoutes:(NSArray<RouteInfo *> *)routes {
    _routes = routes;
    _selectedIndex = 0;

    for (UIView *sub in self.buttonsContainer.subviews) {
        [sub removeFromSuperview];
    }
    [self.routeButtons removeAllObjects];

    if (routes.count == 0) return;

    CGFloat containerW = self.buttonsContainer.bounds.size.width;
    CGFloat itemW = (containerW - (CGFloat)(routes.count - 1) * 10.0) / (CGFloat)routes.count;
    CGFloat itemH = self.buttonsContainer.bounds.size.height;

    for (NSUInteger i = 0; i < routes.count; i++) {
        RouteInfo *r = routes[i];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(i * (itemW + 10.0), 0, itemW, itemH);
        btn.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        btn.layer.cornerRadius = 12.0;
        btn.tag = i;
        [btn addTarget:self action:@selector(handleRouteTapped:) forControlEvents:UIControlEventTouchUpInside];

        // Configura etichette interne
        int mins = (int)ceil(r.totalDuration / 60.0);
        NSString *timeStr = [NSString stringWithFormat:@"%d min", mins];
        NSString *distStr = (r.totalDistance > 1000) ? [NSString stringWithFormat:@"%.1f km", r.totalDistance / 1000.0]
                                                     : [NSString stringWithFormat:@"%d m", (int)r.totalDistance];

        NSString *badge = r.badgeTitle ?: @"Itinerario";
        NSString *delta = r.deltaDescription ?: @"";
        NSString *roads = r.routeSummary ?: @"";

        NSString *title = [NSString stringWithFormat:@"%@\n%@ • %@\n%@ • %@", badge, timeStr, distStr, delta, roads];
        [btn setTitle:title forState:UIControlStateNormal];
        btn.titleLabel.numberOfLines = 4;
        btn.titleLabel.textAlignment = NSTextAlignmentCenter;
        btn.titleLabel.font = [UIFont systemFontOfSize:12.0];

        [self.buttonsContainer addSubview:btn];
        [self.routeButtons addObject:btn];
    }

    [self updateButtonHighlights];
}

- (void)updateButtonHighlights {
    for (NSUInteger i = 0; i < self.routeButtons.count; i++) {
        UIButton *btn = self.routeButtons[i];
        if (i == self.selectedIndex) {
            btn.backgroundColor = [UIColor colorWithRed:0.0 green:0.45 blue:0.95 alpha:0.9];
            btn.layer.borderColor = [[UIColor whiteColor] CGColor];
            btn.layer.borderWidth = 2.0;
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            btn.backgroundColor = [UIColor colorWithWhite:0.22 alpha:0.8];
            btn.layer.borderColor = [[UIColor colorWithWhite:0.4 alpha:0.5] CGColor];
            btn.layer.borderWidth = 1.0;
            [btn setTitleColor:[UIColor colorWithWhite:0.85 alpha:1.0] forState:UIControlStateNormal];
        }
    }
}

- (void)handleRouteTapped:(UIButton *)sender {
    self.selectedIndex = sender.tag;
    [self updateButtonHighlights];

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

- (void)handleCancel {
    if ([self.delegate respondsToSelector:@selector(routeSelectorViewDidCancel:)]) {
        [self.delegate routeSelectorViewDidCancel:self];
    }
}

@end

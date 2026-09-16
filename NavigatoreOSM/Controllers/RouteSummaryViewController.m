#import "RouteSummaryViewController.h"
#import "../Services/LocalizationManager.h"
#import "../Services/VoiceGuidanceService.h"

static NSString *ArrowSymbolForStep(ManeuverStep *step) {
    if (!step) return @"↑";
    NSString *type = step.type ?: @"";
    NSString *modifier = step.modifier ?: @"";

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

@interface RouteSummaryViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *destinationLabel;
@property (nonatomic, strong) UIButton *topCloseButton;

@property (nonatomic, strong) UIView *metricsView;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *distanceLabel;
@property (nonatomic, strong) UILabel *trafficLabel;
@property (nonatomic, strong) UILabel *stepsCountLabel;

@property (nonatomic, strong) UITableView *tableView;

@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton *recalculateButton;
@property (nonatomic, strong) UIButton *repeatVoiceButton;
@property (nonatomic, strong) UIButton *closeButton;

@end

@implementation RouteSummaryViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.preferredContentSize = CGSizeMake(540, 620);
        self.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];

    [self setupHeader];
    [self setupMetrics];
    [self setupBottomBar];
    [self setupTableView];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLanguageChanged)
                                                 name:kAppLanguagePreferenceChangedNotification
                                               object:nil];

    [self scrollToCurrentStep];
}

- (void)setupHeader {
    CGFloat w = self.view.bounds.size.width;
    _headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 64)];
    _headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _headerView.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    [self.view addSubview:_headerView];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 10, w - 80, 24)];
    _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.text = NLString(@"ROUTE_SUMMARY", @"📋 Riepilogo Itinerario");
    [_headerView addSubview:_titleLabel];

    _destinationLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 36, w - 80, 20)];
    _destinationLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _destinationLabel.font = [UIFont systemFontOfSize:13.0];
    _destinationLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    _destinationLabel.text = self.route.destinationTitle ?: @"Destinazione";
    [_headerView addSubview:_destinationLabel];

    _topCloseButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _topCloseButton.frame = CGRectMake(w - 52, 12, 40, 40);
    _topCloseButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_topCloseButton setTitle:@"✕" forState:UIControlStateNormal];
    [_topCloseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _topCloseButton.titleLabel.font = [UIFont boldSystemFontOfSize:20.0];
    [_topCloseButton addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [_headerView addSubview:_topCloseButton];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 63, w, 1)];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    sep.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    [_headerView addSubview:sep];
}

- (void)setupMetrics {
    CGFloat w = self.view.bounds.size.width;
    _metricsView = [[UIView alloc] initWithFrame:CGRectMake(0, 64, w, 68)];
    _metricsView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _metricsView.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
    [self.view addSubview:_metricsView];

    int mins = (int)ceil(self.route.totalDuration / 60.0);
    NSString *timeStr = [NSString stringWithFormat:@"⏱️ %d min", mins];

    NSString *distStr;
    if (self.route.totalDistance > 1000) {
        distStr = [NSString stringWithFormat:@"📍 %.1f km", self.route.totalDistance / 1000.0];
    } else {
        distStr = [NSString stringWithFormat:@"📍 %d m", (int)self.route.totalDistance];
    }

    CGFloat itemW = (w - 32) / 3.0;

    _timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, itemW, 26)];
    _timeLabel.font = [UIFont boldSystemFontOfSize:18.0];
    _timeLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
    _timeLabel.text = timeStr;
    [_metricsView addSubview:_timeLabel];

    _distanceLabel = [[UILabel alloc] initWithFrame:CGRectMake(16 + itemW, 10, itemW, 26)];
    _distanceLabel.font = [UIFont boldSystemFontOfSize:18.0];
    _distanceLabel.textColor = [UIColor colorWithRed:0.3 green:0.75 blue:1.0 alpha:1.0];
    _distanceLabel.text = distStr;
    [_metricsView addSubview:_distanceLabel];

    _trafficLabel = [[UILabel alloc] initWithFrame:CGRectMake(16 + itemW * 2, 10, itemW, 26)];
    _trafficLabel.font = [UIFont boldSystemFontOfSize:14.0];
    _trafficLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    _trafficLabel.text = self.route.trafficDescription ?: @"🟢 Regolare";
    [_metricsView addSubview:_trafficLabel];

    _stepsCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 40, w - 32, 20)];
    _stepsCountLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _stepsCountLabel.font = [UIFont systemFontOfSize:12.0];
    _stepsCountLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    _stepsCountLabel.text = [NSString stringWithFormat:@"%lu %@ • %@",
                             (unsigned long)self.route.steps.count,
                             NLString(@"STEPS", @"Passaggi"),
                             self.route.badgeTitle ?: @""];
    [_metricsView addSubview:_stepsCountLabel];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 67, w, 1)];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    sep.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    [_metricsView addSubview:sep];
}

- (void)setupBottomBar {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat barH = 68.0;

    _bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, h - barH, w, barH)];
    _bottomBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    _bottomBar.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    [self.view addSubview:_bottomBar];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 1)];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    sep.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    [_bottomBar addSubview:sep];

    CGFloat btnH = 46.0;
    CGFloat spacing = 10.0;
    CGFloat totalW = w - 32.0;
    CGFloat usableW = totalW - spacing * 2.0;

    CGFloat recalcW = round(usableW * 0.50);
    CGFloat voiceW = round(usableW * 0.28);
    CGFloat closeW = usableW - recalcW - voiceW;

    _recalculateButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _recalculateButton.frame = CGRectMake(16, 11, recalcW, btnH);
    _recalculateButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
    _recalculateButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:0.95 alpha:1.0];
    _recalculateButton.layer.cornerRadius = 10.0;
    [_recalculateButton setTitle:NLString(@"FIND_MORE_ROUTES", @"🔄 Ricalcola / Altri itinerari") forState:UIControlStateNormal];
    [_recalculateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _recalculateButton.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
    _recalculateButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _recalculateButton.titleLabel.minimumScaleFactor = 0.7;
    [_recalculateButton addTarget:self action:@selector(handleRecalculate) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_recalculateButton];

    _repeatVoiceButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _repeatVoiceButton.frame = CGRectMake(16 + recalcW + spacing, 11, voiceW, btnH);
    _repeatVoiceButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _repeatVoiceButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    _repeatVoiceButton.layer.cornerRadius = 10.0;
    [_repeatVoiceButton setTitle:NLString(@"REPEAT_VOICE", @"🔊 Ripeti voce") forState:UIControlStateNormal];
    [_repeatVoiceButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _repeatVoiceButton.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    _repeatVoiceButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _repeatVoiceButton.titleLabel.minimumScaleFactor = 0.7;
    [_repeatVoiceButton addTarget:self action:@selector(handleRepeatVoice) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_repeatVoiceButton];

    _closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _closeButton.frame = CGRectMake(16 + recalcW + spacing + voiceW + spacing, 11, closeW, btnH);
    _closeButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    _closeButton.backgroundColor = [UIColor colorWithWhite:0.20 alpha:1.0];
    _closeButton.layer.cornerRadius = 10.0;
    [_closeButton setTitle:NLString(@"CLOSE", @"✕ Chiudi") forState:UIControlStateNormal];
    [_closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _closeButton.titleLabel.font = [UIFont systemFontOfSize:13.0];
    _closeButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    [_closeButton addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_closeButton];
}

- (void)setupTableView {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat topY = 64 + 68;
    CGFloat bottomH = 68;

    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, topY, w, h - topY - bottomH) style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.backgroundColor = [UIColor colorWithWhite:0.11 alpha:1.0];
    _tableView.separatorColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 62.0;
    [self.view addSubview:_tableView];
}

- (void)scrollToCurrentStep {
    if (self.currentStepIndex < self.route.steps.count) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:self.currentStepIndex inSection:0];
        [_tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    }
}

- (void)handleLanguageChanged {
    _titleLabel.text = NLString(@"ROUTE_SUMMARY", @"📋 Riepilogo Itinerario");
    [_recalculateButton setTitle:NLString(@"FIND_MORE_ROUTES", @"🔄 Ricalcola / Altri itinerari") forState:UIControlStateNormal];
    [_repeatVoiceButton setTitle:NLString(@"REPEAT_VOICE", @"🔊 Ripeti voce") forState:UIControlStateNormal];
    [_closeButton setTitle:NLString(@"CLOSE", @"✕ Chiudi") forState:UIControlStateNormal];
    [_tableView reloadData];
}

#pragma mark - Actions

- (void)handleRecalculate {
    if ([self.delegate respondsToSelector:@selector(routeSummaryViewControllerDidRequestRecalculate:)]) {
        [self.delegate routeSummaryViewControllerDidRequestRecalculate:self];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)handleRepeatVoice {
    if ([self.delegate respondsToSelector:@selector(routeSummaryViewControllerDidRequestRepeatVoice:)]) {
        [self.delegate routeSummaryViewControllerDidRequestRepeatVoice:self];
    } else if (self.currentStepIndex < self.route.steps.count) {
        ManeuverStep *step = self.route.steps[self.currentStepIndex];
        NSString *txt = (step.instruction.length > 0) ? step.instruction : step.streetName;
        if (txt.length > 0) {
            [[VoiceGuidanceService sharedService] speak:txt];
        }
    }
}

- (void)handleClose {
    if ([self.delegate respondsToSelector:@selector(routeSummaryViewControllerDidClose:)]) {
        [self.delegate routeSummaryViewControllerDidClose:self];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.route.steps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"RouteStepCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14.0];
        cell.detailTextLabel.textColor = [UIColor colorWithRed:0.25 green:0.75 blue:1.0 alpha:1.0];
        cell.detailTextLabel.font = [UIFont boldSystemFontOfSize:12.0];
    }

    if (indexPath.row >= self.route.steps.count) return cell;

    ManeuverStep *step = self.route.steps[indexPath.row];
    NSString *symbol = ArrowSymbolForStep(step);

    NSString *street = (step.streetName.length > 0) ? step.streetName : step.instruction;
    cell.textLabel.text = [NSString stringWithFormat:@"%ld. %@  %@", (long)(indexPath.row + 1), symbol, street ?: @""];

    NSString *distStr;
    if (step.distance > 1000) {
        distStr = [NSString stringWithFormat:@"%.1f km", step.distance / 1000.0];
    } else {
        distStr = [NSString stringWithFormat:@"%d m", (int)round(step.distance)];
    }

    BOOL isCurrent = (indexPath.row == self.currentStepIndex);
    if (isCurrent) {
        cell.backgroundColor = [UIColor colorWithRed:0.0 green:0.35 blue:0.22 alpha:0.85]; // Emerald highlight
        cell.detailTextLabel.text = [NSString stringWithFormat:@"▶ %@ • %@", distStr, step.instruction ?: @""];
        cell.detailTextLabel.textColor = [UIColor colorWithRed:0.4 green:1.0 blue:0.6 alpha:1.0];
    } else {
        cell.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", distStr, step.instruction ?: @""];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < self.route.steps.count) {
        ManeuverStep *step = self.route.steps[indexPath.row];
        NSString *txt = (step.instruction.length > 0) ? step.instruction : step.streetName;
        if (txt.length > 0) {
            [[VoiceGuidanceService sharedService] speak:txt];
        }
        if ([self.delegate respondsToSelector:@selector(routeSummaryViewController:didSelectStepIndex:)]) {
            [self.delegate routeSummaryViewController:self didSelectStepIndex:indexPath.row];
        }
    }
}

@end

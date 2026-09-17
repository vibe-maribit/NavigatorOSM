#import "QuickPOIShelfView.h"
#import "../Services/LocalizationManager.h"
#import "../Services/FuelPriceService.h"
#import <objc/runtime.h>

@interface QuickPOIShelfView ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSMutableArray<UIButton *> *categoryButtons;
@end

static NSArray *POICategoriesDefinition(void) {
    return @[
        @{@"icon": @"⛽", @"key": @"FUEL",        @"def": @"Benzina",    @"query": @"fuel",       @"type": @"amenity"},
        @{@"icon": @"🍕", @"key": @"RESTAURANTS", @"def": @"Ristoranti", @"query": @"restaurant", @"type": @"amenity"},
        @{@"icon": @"🅿️", @"key": @"PARKING",     @"def": @"Parcheggi",  @"query": @"parking",    @"type": @"amenity"},
        @{@"icon": @"☕", @"key": @"CAFE",        @"def": @"Bar",        @"query": @"cafe",       @"type": @"amenity"},
        @{@"icon": @"💊", @"key": @"PHARMACY",    @"def": @"Farmacie",   @"query": @"pharmacy",   @"type": @"amenity"}
    ];
}

@implementation QuickPOIShelfView

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
        self.layer.cornerRadius = 16.0;
        self.layer.borderColor = [[UIColor colorWithWhite:0.3 alpha:0.7] CGColor];
        self.layer.borderWidth = 1.0;
        self.layer.shadowColor = [[UIColor blackColor] CGColor];
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 8.0;
        self.layer.shadowOffset = CGSizeMake(0, 3);

        _categoryButtons = [NSMutableArray array];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"NavigatoreOSM/1.3 (iPad Mini 1; iOS 9.3.5)"
        };
        _session = [NSURLSession sessionWithConfiguration:config];

        [self setupButtons];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        _spinner.center = CGPointMake(frame.size.width / 2.0, frame.size.height / 2.0);
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateLocalizedTitles)
                                                     name:kAppLanguagePreferenceChangedNotification
                                                   object:nil];
    }
    return self;
}

- (void)setupButtons {
    NSArray *items = POICategoriesDefinition();
    [self.categoryButtons removeAllObjects];

    CGFloat totalW = self.bounds.size.width - 50;
    CGFloat btnW = totalW / (CGFloat)items.count;
    CGFloat btnH = self.bounds.size.height - 16;

    for (NSUInteger i = 0; i < items.count; i++) {
        NSDictionary *dict = items[i];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(8 + i * btnW, 8, btnW - 4, btnH);
        btn.backgroundColor = [UIColor colorWithWhite:0.22 alpha:0.85];
        btn.layer.cornerRadius = 10.0;
        btn.layer.borderColor = [[UIColor colorWithWhite:0.4 alpha:0.4] CGColor];
        btn.layer.borderWidth = 1.0;

        NSString *title = NLString(dict[@"key"], dict[@"def"]);
        NSString *text = [NSString stringWithFormat:@"%@ %@", dict[@"icon"], title];
        [btn setTitle:text forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.adjustsFontSizeToFitWidth = YES;
        btn.titleLabel.minimumScaleFactor = 0.7;

        objc_setAssociatedObject(btn, "poi_query", dict[@"query"], OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(btn, "poi_type", dict[@"type"], OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(btn, "poi_key", dict[@"key"], OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(btn, "poi_def", dict[@"def"], OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(btn, "poi_name", title, OBJC_ASSOCIATION_COPY_NONATOMIC);

        [btn addTarget:self action:@selector(handlePOITapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
        [self.categoryButtons addObject:btn];
    }

    // Bottone chiudi a destra
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(self.bounds.size.width - 42, 8, 34, btnH);
    closeBtn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.9];
    closeBtn.layer.cornerRadius = 10.0;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    [closeBtn addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:closeBtn];
}

- (void)updateLocalizedTitles {
    NSArray *items = POICategoriesDefinition();
    for (NSUInteger i = 0; i < self.categoryButtons.count && i < items.count; i++) {
        UIButton *btn = self.categoryButtons[i];
        NSDictionary *dict = items[i];
        NSString *title = NLString(dict[@"key"], dict[@"def"]);
        NSString *text = [NSString stringWithFormat:@"%@ %@", dict[@"icon"], title];
        [btn setTitle:text forState:UIControlStateNormal];
        objc_setAssociatedObject(btn, "poi_name", title, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
}

- (void)handleClose {
    if ([self.delegate respondsToSelector:@selector(quickPOIShelfViewDidRequestClose:)]) {
        [self.delegate quickPOIShelfViewDidRequestClose:self];
    }
}

- (void)handlePOITapped:(UIButton *)sender {
    NSString *query = objc_getAssociatedObject(sender, "poi_query");
    NSString *key = objc_getAssociatedObject(sender, "poi_key");
    NSString *def = objc_getAssociatedObject(sender, "poi_def");
    NSString *name = (key && def) ? NLString(key, def) : objc_getAssociatedObject(sender, "poi_name");

    if ([self.delegate respondsToSelector:@selector(quickPOIShelfView:didRequestSearchCategory:categoryName:)]) {
        [self.delegate quickPOIShelfView:self didRequestSearchCategory:query categoryName:name];
    }
}

- (void)searchCategory:(NSString *)query fromCoordinate:(CLLocationCoordinate2D)coord categoryName:(NSString *)categoryName {
    [self.spinner startAnimating];

    if ([query isEqualToString:@"fuel"]) {
        __weak QuickPOIShelfView *weakSelf = self;
        [[FuelPriceService sharedService] fetchStationsAroundCoordinate:coord radiusKm:10 completion:^(NSArray<FuelStation *> *stations, NSError *error) {
            if (!error && stations && stations.count > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf.spinner stopAnimating];
                    NSMutableArray *annotations = [NSMutableArray array];
                    FuelType fType = [FuelPriceService sharedService].selectedFuelType;
                    for (FuelStation *st in stations) {
                        [annotations addObject:[[FuelStationAnnotation alloc] initWithStation:st fuelType:fType]];
                    }
                    if ([weakSelf.delegate respondsToSelector:@selector(quickPOIShelfView:didFindPOIs:categoryName:)]) {
                        [weakSelf.delegate quickPOIShelfView:weakSelf didFindPOIs:annotations categoryName:categoryName];
                    }
                });
                return;
            }
            // Fallback su Nominatim OSM se MIMIT non restituisce stazioni o errore
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf executeNominatimSearch:query fromCoordinate:coord categoryName:categoryName];
            });
        }];
        return;
    }

    [self executeNominatimSearch:query fromCoordinate:coord categoryName:categoryName];
}

- (void)executeNominatimSearch:(NSString *)query fromCoordinate:(CLLocationCoordinate2D)coord categoryName:(NSString *)categoryName {
    // Bounding box di circa 6 km attorno alla posizione
    double delta = 0.06;
    NSString *urlString = [NSString stringWithFormat:
                           @"https://nominatim.openstreetmap.org/search?format=json&amenity=%@&viewbox=%.4f,%.4f,%.4f,%.4f&bounded=1&limit=15",
                           query, coord.longitude - delta, coord.latitude + delta, coord.longitude + delta, coord.latitude - delta];

    NSURL *url = [NSURL URLWithString:urlString];
    __weak QuickPOIShelfView *weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.spinner stopAnimating];
        });

        if (error || !data) return;

        NSError *jsonErr = nil;
        NSArray *items = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (![items isKindOfClass:[NSArray class]]) return;

        NSMutableArray<MKPointAnnotation *> *annotations = [NSMutableArray array];
        for (NSDictionary *d in items) {
            double lat = [d[@"lat"] doubleValue];
            double lon = [d[@"lon"] doubleValue];
            NSString *disp = d[@"display_name"] ?: categoryName;
            NSArray *parts = [disp componentsSeparatedByString:@", "];
            NSString *title = (parts.count > 0) ? parts[0] : categoryName;
            NSString *subtitle = (parts.count > 1) ? parts[1] : @"";

            MKPointAnnotation *ann = [[MKPointAnnotation alloc] init];
            ann.coordinate = CLLocationCoordinate2DMake(lat, lon);
            ann.title = title;
            ann.subtitle = subtitle;
            [annotations addObject:ann];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([weakSelf.delegate respondsToSelector:@selector(quickPOIShelfView:didFindPOIs:categoryName:)]) {
                [weakSelf.delegate quickPOIShelfView:weakSelf didFindPOIs:annotations categoryName:categoryName];
            }
        });
    }];
    [task resume];
}

@end

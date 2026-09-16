#import "SearchViewController.h"
#import "../Services/LocalizationManager.h"

@interface SearchItem : NSObject
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
@property (nonatomic, assign) BOOL isRecent;
@end

@implementation SearchItem
@end

static NSString *const kRecentDestinationsKey = @"NavigatoreOSM_RecentDestinations";

@interface SearchViewController () <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<SearchItem *> *results;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL showMapAllButton; // mostra "📍 Mostra tutti sulla mappa"
@property (nonatomic, assign) BOOL showingRecents;
@end

@implementation SearchViewController

+ (NSArray<NSDictionary *> *)recentDestinations {
    NSArray *recents = [[NSUserDefaults standardUserDefaults] arrayForKey:kRecentDestinationsKey];
    return recents ?: @[];
}

+ (void)saveRecentDestinationWithTitle:(NSString *)title coordinate:(CLLocationCoordinate2D)coordinate {
    if (!title || title.length == 0 || !CLLocationCoordinate2DIsValid(coordinate)) return;

    NSMutableArray *recents = [[self recentDestinations] mutableCopy];

    // Rimuovi duplicati vicini (< 250m) o con lo stesso titolo
    NSMutableArray *toRemove = [NSMutableArray array];
    for (NSDictionary *dict in recents) {
        double lat = [dict[@"lat"] doubleValue];
        double lon = [dict[@"lon"] doubleValue];
        NSString *existingTitle = dict[@"title"] ?: @"";
        if ([existingTitle isEqualToString:title] ||
            (fabs(lat - coordinate.latitude) < 0.0025 && fabs(lon - coordinate.longitude) < 0.0025)) {
            [toRemove addObject:dict];
        }
    }
    [recents removeObjectsInArray:toRemove];

    NSDictionary *newEntry = @{
        @"title": title,
        @"lat": @(coordinate.latitude),
        @"lon": @(coordinate.longitude),
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    };
    [recents insertObject:newEntry atIndex:0];

    // Mantieni al massimo 15 destinazioni recenti
    while (recents.count > 15) {
        [recents removeLastObject];
    }

    [[NSUserDefaults standardUserDefaults] setObject:recents forKey:kRecentDestinationsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)clearRecentDestinations {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kRecentDestinationsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NLString(@"SEARCH_TITLE", @"Cerca Destinazione");
    self.view.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];

    self.results = [NSMutableArray array];
    self.showMapAllButton = NO;
    self.showingRecents = NO;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPAdditionalHeaders = @{
        @"User-Agent": @"NavigatoreOSM/1.2 (iPad Mini 1; iOS 9.3.5)"
    };
    self.session = [NSURLSession sessionWithConfiguration:config];

    // Barra superiore alta 64pt con pulsante Chiudi prominente
    UIView *topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 64)];
    topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    topBar.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
    topBar.userInteractionEnabled = YES;
    [self.view addSubview:topBar];

    // Pulsante Chiudi ad alto contrasto (stile pillola scura con bordo)
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(topBar.bounds.size.width - 96, 12, 86, 40);
    closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    closeBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:0.9];
    closeBtn.layer.cornerRadius = 10.0;
    closeBtn.layer.masksToBounds = YES;
    [closeBtn setTitle:NLString(@"CLOSE", @"✕ Chiudi") forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    [closeBtn addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:closeBtn];

    // Search Bar
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(10, 10, topBar.bounds.size.width - 116, 44)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.delegate = self;
    self.searchBar.placeholder = NLString(@"SEARCH_INPUT_PLACEHOLDER", @"Cerca via, città o luogo...");
    self.searchBar.keyboardAppearance = UIKeyboardAppearanceDark;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.barTintColor = [UIColor colorWithWhite:0.16 alpha:1.0];
    self.searchBar.tintColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0];
    [topBar addSubview:self.searchBar];

    // Gesture swipe verso il basso per chiudere la schermata
    UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleClose)];
    swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
    [topBar addGestureRecognizer:swipeDown];

    // TableView
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 64, self.view.bounds.size.width, self.view.bounds.size.height - 64) style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    // Tap sulla tabella per chiudere la tastiera
    UITapGestureRecognizer *tapToDismiss = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapToDismiss.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:tapToDismiss];

    // Spinner
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.center = CGPointMake(self.view.bounds.size.width / 2.0, 160);
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    [self styleSearchField];
    [self loadRecentItems];
    [self.searchBar becomeFirstResponder];
}

- (void)loadRecentItems {
    [self.spinner stopAnimating];
    [self.results removeAllObjects];
    self.showMapAllButton = NO;

    NSArray *recents = [SearchViewController recentDestinations];
    for (NSDictionary *dict in recents) {
        SearchItem *item = [[SearchItem alloc] init];
        item.displayName = dict[@"title"] ?: @"Destinazione";
        item.coordinate = CLLocationCoordinate2DMake([dict[@"lat"] doubleValue], [dict[@"lon"] doubleValue]);
        item.isRecent = YES;
        [self.results addObject:item];
    }
    self.showingRecents = (self.results.count > 0);
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self styleSearchField];
}

- (void)styleSearchField {
    [self recursivelyStyleTextFieldInView:self.searchBar];
}

- (void)recursivelyStyleTextFieldInView:(UIView *)view {
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        tf.textColor = [UIColor whiteColor];
        tf.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
        tf.tintColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0];
        tf.keyboardAppearance = UIKeyboardAppearanceDark;
        tf.font = [UIFont systemFontOfSize:15.0];
        @try {
            [tf setValue:[UIColor colorWithWhite:0.70 alpha:1.0] forKeyPath:@"_placeholderLabel.textColor"];
        } @catch (NSException *e) {}
        return;
    }
    for (UIView *sub in view.subviews) {
        [self recursivelyStyleTextFieldInView:sub];
    }
}

- (void)dismissKeyboard {
    [self.searchBar resignFirstResponder];
}

- (void)handleClose {
    [self.searchBar resignFirstResponder];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [self styleSearchField];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        [self loadRecentItems];
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *query = searchBar.text;
    if (query.length == 0) {
        [self loadRecentItems];
        return;
    }

    [self performSearch:query];
}

- (void)performSearch:(NSString *)query {
    [self.spinner startAnimating];
    [self.results removeAllObjects];
    self.showMapAllButton = NO;
    self.showingRecents = NO;
    [self.tableView reloadData];

    NSString *encoded = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];

    // Se l'utente ha una posizione valida, cerca nei dintorni
    NSString *urlString;
    BOOL hasLocation = CLLocationCoordinate2DIsValid(self.userLocation) && self.userLocation.latitude != 0;
    if (hasLocation) {
        // Cerca con viewbox centrato sulla posizione corrente (~10km)
        double delta = 0.09;
        urlString = [NSString stringWithFormat:
            @"https://nominatim.openstreetmap.org/search?format=json&q=%@&viewbox=%.4f,%.4f,%.4f,%.4f&bounded=0&limit=15&addressdetails=1",
            encoded,
            self.userLocation.longitude - delta, self.userLocation.latitude + delta,
            self.userLocation.longitude + delta, self.userLocation.latitude - delta];
    } else {
        urlString = [NSString stringWithFormat:@"https://nominatim.openstreetmap.org/search?format=json&q=%@&countrycodes=it&limit=15&addressdetails=1", encoded];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
        });

        if (error || !data) return;

        NSError *jsonError = nil;
        NSArray *items = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (![items isKindOfClass:[NSArray class]]) return;

        NSMutableArray<SearchItem *> *newResults = [NSMutableArray array];
        for (NSDictionary *dict in items) {
            SearchItem *item = [[SearchItem alloc] init];
            item.displayName = dict[@"display_name"] ?: @"";
            double lat = [dict[@"lat"] doubleValue];
            double lon = [dict[@"lon"] doubleValue];
            item.coordinate = CLLocationCoordinate2DMake(lat, lon);
            [newResults addObject:item];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.results = newResults;
            // Mostra il pulsante "Mostra tutti sulla mappa" se ci sono 2+ risultati
            self.showMapAllButton = (newResults.count >= 2);
            [self.tableView reloadData];
        });
    }];
    [task resume];
}

#pragma mark - Show All POIs On Map

- (void)showAllResultsOnMap {
    if (self.results.count == 0) return;

    NSMutableArray<MKPointAnnotation *> *annotations = [NSMutableArray array];
    for (SearchItem *item in self.results) {
        MKPointAnnotation *ann = [[MKPointAnnotation alloc] init];
        ann.coordinate = item.coordinate;
        NSArray *parts = [item.displayName componentsSeparatedByString:@", "];
        ann.title = (parts.count > 0) ? parts[0] : item.displayName;
        ann.subtitle = (parts.count > 1) ? parts[1] : @"";
        [annotations addObject:ann];
    }

    NSString *category = self.searchBar.text ?: @"Risultati";

    [self dismissViewControllerAnimated:YES completion:^{
        if ([self.delegate respondsToSelector:@selector(searchViewControllerDidRequestShowAllPOIs:categoryName:)]) {
            [self.delegate searchViewControllerDidRequestShowAllPOIs:annotations categoryName:category];
        }
    }];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.showingRecents) {
        return self.results.count + 1; // +1 per pulsante "Cancella cronologia"
    }
    NSInteger extra = self.showMapAllButton ? 1 : 0;
    return self.results.count + extra;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.showingRecents) {
        return NLString(@"RECENT_DESTINATIONS", @"🕒 DESTINAZIONI RECENTI");
    } else if (self.results.count > 0) {
        return [NSString stringWithFormat:@"RISULTATI PER \"%@\"", self.searchBar.text ?: @""];
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Ultima riga dei recenti: pulsante "Cancella cronologia"
    if (self.showingRecents && indexPath.row == self.results.count) {
        UITableViewCell *clearCell = [tableView dequeueReusableCellWithIdentifier:@"ClearRecentsCell"];
        if (!clearCell) {
            clearCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ClearRecentsCell"];
            clearCell.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
            clearCell.textLabel.textColor = [UIColor colorWithRed:0.95 green:0.4 blue:0.4 alpha:1.0];
            clearCell.textLabel.font = [UIFont systemFontOfSize:14.0];
            clearCell.textLabel.textAlignment = NSTextAlignmentCenter;
        }
        clearCell.textLabel.text = NLString(@"CLEAR_HISTORY", @"🗑️ Cancella cronologia destinazioni");
        return clearCell;
    }

    // Prima riga: pulsante "Mostra tutti sulla mappa" (se abilitato per ricerca testuale)
    if (self.showMapAllButton && indexPath.row == 0 && !self.showingRecents) {
        UITableViewCell *mapCell = [tableView dequeueReusableCellWithIdentifier:@"MapAllCell"];
        if (!mapCell) {
            mapCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"MapAllCell"];
            mapCell.backgroundColor = [UIColor colorWithRed:0.1 green:0.3 blue:0.55 alpha:1.0];
            mapCell.textLabel.textColor = [UIColor whiteColor];
            mapCell.textLabel.font = [UIFont boldSystemFontOfSize:15.0];
            mapCell.textLabel.textAlignment = NSTextAlignmentCenter;
        }
        mapCell.textLabel.text = [NSString stringWithFormat:NLString(@"SHOW_ALL_MAP", @"📍 Mostra tutti i %lu risultati sulla mappa"), (unsigned long)self.results.count];
        return mapCell;
    }

    static NSString *cellId = @"SearchCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    }

    NSInteger resultIndex = (self.showMapAllButton && !self.showingRecents) ? (indexPath.row - 1) : indexPath.row;
    SearchItem *item = self.results[resultIndex];
    NSArray *parts = [item.displayName componentsSeparatedByString:@", "];
    NSString *mainTitle = (parts.count > 0) ? parts[0] : item.displayName;

    if (self.showingRecents) {
        cell.textLabel.text = [NSString stringWithFormat:@"🕒 %@", mainTitle];
        if (parts.count > 1) {
            NSRange restRange = NSMakeRange(1, parts.count - 1);
            cell.detailTextLabel.text = [[parts subarrayWithRange:restRange] componentsJoinedByString:@", "];
        } else {
            cell.detailTextLabel.text = NLString(@"RECENT_DEST_SUB", @"Destinazione recente");
        }
    } else {
        cell.textLabel.text = mainTitle;
        if (parts.count > 1) {
            NSRange restRange = NSMakeRange(1, parts.count - 1);
            cell.detailTextLabel.text = [[parts subarrayWithRange:restRange] componentsJoinedByString:@", "];
        } else {
            cell.detailTextLabel.text = @"";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.showingRecents && indexPath.row == self.results.count) {
        [SearchViewController clearRecentDestinations];
        [self loadRecentItems];
        return;
    }

    if (self.showMapAllButton && indexPath.row == 0 && !self.showingRecents) {
        [self showAllResultsOnMap];
        return;
    }

    NSInteger resultIndex = (self.showMapAllButton && !self.showingRecents) ? (indexPath.row - 1) : indexPath.row;
    SearchItem *selected = self.results[resultIndex];

    [SearchViewController saveRecentDestinationWithTitle:selected.displayName coordinate:selected.coordinate];

    if ([self.delegate respondsToSelector:@selector(searchViewControllerDidSelectLocation:title:)]) {
        [self.delegate searchViewControllerDidSelectLocation:selected.coordinate title:selected.displayName];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

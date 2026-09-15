#import "SearchViewController.h"

@interface SearchItem : NSObject
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
@end

@implementation SearchItem
@end

@interface SearchViewController () <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<SearchItem *> *results;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation SearchViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Cerca Destinazione";
    self.view.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];

    self.results = [NSMutableArray array];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPAdditionalHeaders = @{
        @"User-Agent": @"NavigatoreOSM/1.1 (iPad Mini 1; iOS 9.3.5)"
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
    [closeBtn setTitle:@"✕ Chiudi" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    [closeBtn addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:closeBtn];

    // Search Bar
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(10, 10, topBar.bounds.size.width - 116, 44)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"Cerca via, città o luogo...";
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
    [self.searchBar becomeFirstResponder];
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

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *query = searchBar.text;
    if (query.length == 0) return;

    [self performSearch:query];
}

- (void)performSearch:(NSString *)query {
    [self.spinner startAnimating];
    [self.results removeAllObjects];
    [self.tableView reloadData];

    NSString *encoded = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"https://nominatim.openstreetmap.org/search?format=json&q=%@&countrycodes=it&limit=15&addressdetails=1", encoded];

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
            [self.tableView reloadData];
        });
    }];
    [task resume];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
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

    SearchItem *item = self.results[indexPath.row];
    NSArray *parts = [item.displayName componentsSeparatedByString:@", "];
    if (parts.count > 0) {
        cell.textLabel.text = parts[0];
        if (parts.count > 1) {
            NSRange restRange = NSMakeRange(1, parts.count - 1);
            cell.detailTextLabel.text = [[parts subarrayWithRange:restRange] componentsJoinedByString:@", "];
        } else {
            cell.detailTextLabel.text = @"";
        }
    } else {
        cell.textLabel.text = item.displayName;
        cell.detailTextLabel.text = @"";
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SearchItem *selected = self.results[indexPath.row];

    if ([self.delegate respondsToSelector:@selector(searchViewControllerDidSelectLocation:title:)]) {
        [self.delegate searchViewControllerDidSelectLocation:selected.coordinate title:selected.displayName];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

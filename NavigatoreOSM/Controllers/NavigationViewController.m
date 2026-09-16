#import "NavigationViewController.h"
#import "SearchViewController.h"
#import "SettingsViewController.h"
#import "../Overlays/OSMTileOverlay.h"
#import "../Overlays/TrafficTileOverlay.h"
#import "../Services/RoutingService.h"
#import "../Services/VoiceGuidanceService.h"
#import "../Services/NetworkGPSReceiver.h"
#import "../Views/SpeedometerView.h"
#import "../Views/ManeuverHUDView.h"
#import "../Views/ModernTripBarView.h"
#import "../Views/RouteSelectorView.h"
#import "../Views/QuickPOIShelfView.h"
#import "../Views/POIResultsCardView.h"
#import "../Services/LocalizationManager.h"

@interface NavigationViewController () <SearchViewControllerDelegate, NetworkGPSReceiverDelegate, RouteSelectorViewDelegate, QuickPOIShelfViewDelegate, SettingsViewControllerDelegate, POIResultsCardViewDelegate>

@property (nonatomic, strong) OSMTileOverlay *osmOverlay;
@property (nonatomic, strong) TrafficTileOverlay *trafficOverlay;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *currentLocation;
@property (nonatomic, assign) CLLocationDirection currentHeading;

// UI HUD Moderna Waze / Google Maps
@property (nonatomic, strong) ManeuverHUDView *maneuverHUD;
@property (nonatomic, strong) ModernTripBarView *tripBar;
@property (nonatomic, strong) SpeedometerView *speedometer;
@property (nonatomic, strong) RouteSelectorView *routeSelector;
@property (nonatomic, strong) QuickPOIShelfView *poiShelf;
@property (nonatomic, strong) POIResultsCardView *poiResultsCard;

// Controlli Flottanti (FAB) — Colonna Verticale Collapsible
@property (nonatomic, strong) UIButton *topSearchPill;
@property (nonatomic, strong) UIButton *recenterButton;
@property (nonatomic, strong) UIButton *toggleToolbarButton;
@property (nonatomic, strong) UIButton *view3DButton;
@property (nonatomic, strong) UIButton *trafficButton;
@property (nonatomic, strong) UIButton *themeButton;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UILabel *gpsSourceLabel;
@property (nonatomic, assign) BOOL toolbarExpanded;

// Stato 3D / 2D e Navigazione
@property (nonatomic, assign) BOOL is3DMode;
@property (nonatomic, strong) NSArray<RouteInfo *> *availableRoutes;
@property (nonatomic, strong) RouteInfo *currentRoute;
@property (nonatomic, assign) NSUInteger currentStepIndex;
@property (nonatomic, assign) BOOL isNavigating;
@property (nonatomic, assign) NSInteger offRouteConsecutiveCount;
@property (nonatomic, strong) NSMutableArray<MKPointAnnotation *> *poiAnnotations;
@property (nonatomic, strong) MKPointAnnotation *destinationPin;
@property (nonatomic, assign) NSUInteger currentRouteRequestId;

@end

@implementation NavigationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    // 1. Evita assolutamente lo spegnimento dello schermo durante la guida!
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    // 2. Mappa Nativa con MapKit e supporto 3D
    self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;

    // Long-press per impostare rapidamente una destinazione toccando la mappa
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapLongPress:)];
    longPress.minimumPressDuration = 0.6;
    [self.mapView addGestureRecognizer:longPress];

    [self.view addSubview:self.mapView];

    // Modalità 3D attiva di default (visuale prospettica auto)
    self.is3DMode = YES;
    self.toolbarExpanded = NO;

    // 3. Sovrapponi layer OpenStreetMap base a livello strade
    self.osmOverlay = [[OSMTileOverlay alloc] initWithTheme:OSMMapThemeStandard];
    [self.mapView addOverlay:self.osmOverlay level:MKOverlayLevelAboveRoads];

    // 4. Layer Traffico in tempo reale
    self.trafficOverlay = [TrafficTileOverlay sharedOverlay];
    if (self.trafficOverlay.isEnabled) {
        [self.mapView addOverlay:self.trafficOverlay level:MKOverlayLevelAboveRoads];
    }

    // 5. Configura GPS Nativo (Apple CoreLocation)
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    self.locationManager.activityType = CLActivityTypeAutomotiveNavigation;
    self.locationManager.distanceFilter = 1.0;
    self.locationManager.headingFilter = 2.0;

    if ([self.locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
        [self.locationManager requestWhenInUseAuthorization];
    }
    [self.locationManager startUpdatingLocation];
    [self.locationManager startUpdatingHeading];

    // 6. Ricevitore GPS di rete (UDP o TCP) per tethering da Android con impostazioni persistenti
    [NetworkGPSReceiver sharedReceiver].delegate = self;
    [[NetworkGPSReceiver sharedReceiver] startWithSavedSettings];

    self.poiAnnotations = [NSMutableArray array];

    // 7. Costruisci l'interfaccia grafica moderna in stile Google Maps / Waze
    [self setupModernUI];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLanguageChanged:)
                                                 name:kAppLanguagePreferenceChangedNotification
                                               object:nil];

    // Messaggio vocale di avvio
    [[VoiceGuidanceService sharedService] speak:NLString(@"READY_3D", @"Navigatore pronto con visuale 3D prospettica.")];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

#pragma mark - Setup UI Moderna (Google Maps / Waze)

- (void)setupModernUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    __weak NavigationViewController *weakSelf = self;

    // 1. Barra di Ricerca a Pillola Flottante Superiore (Stile Google Maps)
    self.topSearchPill = [UIButton buttonWithType:UIButtonTypeCustom];
    self.topSearchPill.frame = CGRectMake(24, 20, MIN(380, w - 48), 48);
    self.topSearchPill.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    self.topSearchPill.layer.cornerRadius = 24.0;
    self.topSearchPill.layer.borderColor = [[UIColor colorWithWhite:0.35 alpha:0.7] CGColor];
    self.topSearchPill.layer.borderWidth = 1.0;
    self.topSearchPill.layer.shadowColor = [[UIColor blackColor] CGColor];
    self.topSearchPill.layer.shadowOpacity = 0.5;
    self.topSearchPill.layer.shadowRadius = 8.0;
    self.topSearchPill.layer.shadowOffset = CGSizeMake(0, 3);
    [self.topSearchPill setTitle:NLString(@"SEARCH_PLACEHOLDER", @"  🔍 Cerca destinazione o indirizzo...") forState:UIControlStateNormal];
    [self.topSearchPill setTitleColor:[UIColor colorWithWhite:0.9 alpha:1.0] forState:UIControlStateNormal];
    self.topSearchPill.titleLabel.font = [UIFont systemFontOfSize:15.0];
    self.topSearchPill.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.topSearchPill.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    [self.topSearchPill addTarget:self action:@selector(openSearch) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.topSearchPill];

    // 2. Barra POI Rapida a Pillole (Benzina, Ristoranti, Parcheggi, Bar, Farmacie)
    self.poiShelf = [[QuickPOIShelfView alloc] initWithFrame:CGRectMake(24, 76, MIN(420, w - 48), 46)];
    self.poiShelf.delegate = self;
    [self.view addSubview:self.poiShelf];

    // 3. Scheda Manovre Smeraldo Stile Waze (Nascosta prima di avviare la navigazione)
    self.maneuverHUD = [[ManeuverHUDView alloc] initWithFrame:CGRectMake(24, 20, 380, 108)];
    self.maneuverHUD.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.maneuverHUD.onTapBlock = ^{
        [weakSelf repeatCurrentInstruction];
    };
    self.maneuverHUD.hidden = YES;
    [self.view addSubview:self.maneuverHUD];

    // 4. Barra di Viaggio Inferiore Stile Google Maps (ETA grande, minuti, km, tasto stop)
    self.tripBar = [[ModernTripBarView alloc] initWithFrame:CGRectMake(24, h - 86, MIN(440, w - 48), 68)];
    self.tripBar.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.tripBar.onExitBlock = ^{
        [weakSelf cancelCurrentRoute];
    };
    self.tripBar.hidden = YES;
    [self.view addSubview:self.tripBar];

    // 5. Tachimetro Circolare Stile Waze in basso a sinistra
    self.speedometer = [[SpeedometerView alloc] initWithFrame:CGRectMake(24, h - 195, 96, 96)];
    self.speedometer.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.speedometer];

    // 6. Etichetta Sorgente GPS
    self.gpsSourceLabel = [[UILabel alloc] initWithFrame:CGRectMake(132, h - 130, 220, 20)];
    self.gpsSourceLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.gpsSourceLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.gpsSourceLabel.textColor = [UIColor colorWithWhite:0.25 alpha:0.85];
    self.gpsSourceLabel.text = NLString(@"WAITING_GPS", @"GPS: In attesa di segnale...");
    [self.view addSubview:self.gpsSourceLabel];

    // 7. TOOLBAR VERTICALE COLLAPSIBLE a destra
    [self setupVerticalToolbar];

    // 8. Selettore Itinerari Multipli in basso
    self.routeSelector = [[RouteSelectorView alloc] initWithFrame:CGRectMake(30, h - 195, w - 60, 175)];
    self.routeSelector.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.routeSelector.delegate = self;
    self.routeSelector.hidden = YES;
    [self.view addSubview:self.routeSelector];

    // 9. Scheda Risultati POI
    self.poiResultsCard = [[POIResultsCardView alloc] initWithFrame:CGRectMake(20, h - 170, w - 40, 155)];
    self.poiResultsCard.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.poiResultsCard.delegate = self;
    [self.view addSubview:self.poiResultsCard];
}

- (void)handleLanguageChanged:(NSNotification *)note {
    [self.topSearchPill setTitle:NLString(@"SEARCH_PLACEHOLDER", @"  🔍 Cerca destinazione o indirizzo...") forState:UIControlStateNormal];
    if (self.currentLocation == nil) {
        self.gpsSourceLabel.text = NLString(@"WAITING_GPS", @"GPS: In attesa di segnale...");
    }
    [self.maneuverHUD reset];
}

#pragma mark - Toolbar Verticale Collapsible (◀ / ▶)

- (void)setupVerticalToolbar {
    CGFloat w = self.view.bounds.size.width;
    CGFloat btnSize = 50.0;
    CGFloat rightMargin = 14.0;
    CGFloat btnX = w - btnSize - rightMargin;
    CGFloat spacing = 56.0;

    // Il pulsante più in basso è 🎯 (sempre visibile)
    CGFloat baseY = self.view.bounds.size.height - 68;

    self.recenterButton = [self createCircularButtonWithTitle:@"🎯" frame:CGRectMake(btnX, baseY, btnSize, btnSize)];
    [self.recenterButton addTarget:self action:@selector(recenterMap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.recenterButton];

    // Freccia toggle (sempre visibile, sopra 🎯)
    self.toggleToolbarButton = [self createCircularButtonWithTitle:@"◀" frame:CGRectMake(btnX, baseY - spacing, btnSize, btnSize)];
    self.toggleToolbarButton.titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
    [self.toggleToolbarButton addTarget:self action:@selector(toggleToolbar) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.toggleToolbarButton];

    // Pulsanti espandibili (nascosti di default)
    // Ordine dal basso: 2D/3D, 🚦, 🌙, 🔊, ⚙️
    self.view3DButton = [self createCircularButtonWithTitle:@"2D" frame:CGRectMake(btnX, baseY - spacing * 2, btnSize, btnSize)];
    [self.view3DButton setTitleColor:[UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    self.view3DButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [self.view3DButton addTarget:self action:@selector(toggle3DMode) forControlEvents:UIControlEventTouchUpInside];
    self.view3DButton.hidden = YES;
    self.view3DButton.alpha = 0;
    [self.view addSubview:self.view3DButton];

    self.trafficButton = [self createCircularButtonWithTitle:@"🚦" frame:CGRectMake(btnX, baseY - spacing * 3, btnSize, btnSize)];
    [self.trafficButton addTarget:self action:@selector(toggleTraffic) forControlEvents:UIControlEventTouchUpInside];
    self.trafficButton.hidden = YES;
    self.trafficButton.alpha = 0;
    [self.view addSubview:self.trafficButton];

    self.themeButton = [self createCircularButtonWithTitle:@"🌙" frame:CGRectMake(btnX, baseY - spacing * 4, btnSize, btnSize)];
    [self.themeButton addTarget:self action:@selector(toggleMapTheme) forControlEvents:UIControlEventTouchUpInside];
    self.themeButton.hidden = YES;
    self.themeButton.alpha = 0;
    [self.view addSubview:self.themeButton];

    self.muteButton = [self createCircularButtonWithTitle:@"🔊" frame:CGRectMake(btnX, baseY - spacing * 5, btnSize, btnSize)];
    [self.muteButton addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
    self.muteButton.hidden = YES;
    self.muteButton.alpha = 0;
    [self.view addSubview:self.muteButton];

    self.settingsButton = [self createCircularButtonWithTitle:@"⚙️" frame:CGRectMake(btnX, baseY - spacing * 6, btnSize, btnSize)];
    [self.settingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    self.settingsButton.hidden = YES;
    self.settingsButton.alpha = 0;
    [self.view addSubview:self.settingsButton];
}

- (void)toggleToolbar {
    self.toolbarExpanded = !self.toolbarExpanded;
    NSArray *expandableButtons = @[self.view3DButton, self.trafficButton, self.themeButton, self.muteButton, self.settingsButton];

    if (self.toolbarExpanded) {
        // Espandi: mostra tutti i pulsanti con animazione
        for (UIButton *btn in expandableButtons) {
            btn.hidden = NO;
        }
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            for (UIButton *btn in expandableButtons) {
                btn.alpha = 1.0;
            }
            [self.toggleToolbarButton setTitle:@"▶" forState:UIControlStateNormal];
        } completion:nil];
    } else {
        // Comprimi: nascondi tutti i pulsanti con animazione
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            for (UIButton *btn in expandableButtons) {
                btn.alpha = 0;
            }
            [self.toggleToolbarButton setTitle:@"◀" forState:UIControlStateNormal];
        } completion:^(BOOL finished) {
            for (UIButton *btn in expandableButtons) {
                btn.hidden = YES;
            }
        }];
    }
}

- (UIButton *)createCircularButtonWithTitle:(NSString *)title frame:(CGRect)frame {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    btn.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
    btn.layer.cornerRadius = frame.size.width / 2.0;
    btn.layer.borderColor = [[UIColor colorWithWhite:0.35 alpha:0.75] CGColor];
    btn.layer.borderWidth = 1.0;
    btn.layer.shadowColor = [[UIColor blackColor] CGColor];
    btn.layer.shadowOpacity = 0.5;
    btn.layer.shadowRadius = 6.0;
    btn.layer.shadowOffset = CGSizeMake(0, 3);
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:22.0];
    return btn;
}

#pragma mark - Gestione Telecamera 3D Prospettica / 2D Pianta (`MKMapCamera`)

- (void)toggle3DMode {
    self.is3DMode = !self.is3DMode;
    // Se siamo in 3D, il bottone offre di passare a 2D; se siamo in 2D, offre di passare a 3D
    [self.view3DButton setTitle:(self.is3DMode ? @"2D" : @"3D") forState:UIControlStateNormal];

    [self applyCameraPerspectiveAnimated:YES];

    NSString *announcement = self.is3DMode ? @"Visuale tridimensionale 3D attivata." : @"Visuale piana 2D a volo d'uccello.";
    [[VoiceGuidanceService sharedService] speak:announcement];
}

- (void)applyCameraPerspectiveAnimated:(BOOL)animated {
    CLLocationCoordinate2D center = self.currentLocation ? self.currentLocation.coordinate : self.mapView.centerCoordinate;
    CLLocationDirection heading = self.currentHeading;

    if (self.is3DMode) {
        // Modalità 3D Prospettica Cockpit (stile Waze/Google Maps)
        double speed = (self.currentLocation && self.currentLocation.speed > 0) ? self.currentLocation.speed : 0;
        double altitude = 420.0 + (speed * 3.5);
        altitude = MIN(altitude, 750.0);

        MKMapCamera *cam = [MKMapCamera cameraLookingAtCenterCoordinate:center
                                                      fromEyeCoordinate:center
                                                            eyeAltitude:altitude];
        cam.pitch = 56.0; // Inclinazione tridimensionale 3D
        cam.heading = heading;
        [self.mapView setCamera:cam animated:animated];
    } else {
        // Modalità 2D Pianta Ortogonale
        MKMapCamera *cam = [MKMapCamera cameraLookingAtCenterCoordinate:center
                                                      fromEyeCoordinate:center
                                                            eyeAltitude:1400.0];
        cam.pitch = 0.0; // Piatta a 0°
        cam.heading = heading;
        [self.mapView setCamera:cam animated:animated];
    }
}

- (void)recenterMap {
    if (self.currentLocation) {
        [self applyCameraPerspectiveAnimated:YES];
    }
}

#pragma mark - Azioni Flottanti

- (void)openSearch {
    SearchViewController *searchVC = [[SearchViewController alloc] init];
    searchVC.delegate = self;
    searchVC.modalPresentationStyle = UIModalPresentationFormSheet;
    // Passa la posizione corrente per ricerche geolocalizzate
    if (self.currentLocation) {
        searchVC.userLocation = self.currentLocation.coordinate;
    }
    [self presentViewController:searchVC animated:YES completion:nil];
}

- (void)openSettings {
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    settingsVC.delegate = self;
    // Wrapper UINavigationController per barra nativa con pulsante Chiudi di sistema
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.translucent = NO;
    nav.navigationBar.barTintColor = [UIColor colorWithWhite:0.16 alpha:1.0];
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
    nav.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)toggleTraffic {
    self.trafficOverlay.isEnabled = !self.trafficOverlay.isEnabled;
    if (self.trafficOverlay.isEnabled) {
        [self.mapView addOverlay:self.trafficOverlay level:MKOverlayLevelAboveRoads];
        [self.trafficButton setTitle:@"🚦" forState:UIControlStateNormal];
        [[VoiceGuidanceService sharedService] speak:NLString(@"TRAFFIC_ON", @"Traffico attivato.")];
    } else {
        [self.mapView removeOverlay:self.trafficOverlay];
        [self.trafficButton setTitle:@"⚪" forState:UIControlStateNormal];
        [[VoiceGuidanceService sharedService] speak:NLString(@"TRAFFIC_OFF", @"Traffico disattivato.")];
    }
}

- (void)toggleMapTheme {
    OSMMapTheme current = self.osmOverlay.theme;
    OSMMapTheme next;
    if (self.mapView.mapType == MKMapTypeHybrid) {
        next = OSMMapThemeStandard;
    } else if (current == OSMMapThemeStandard) {
        next = OSMMapThemeDark;
    } else if (current == OSMMapThemeDark) {
        next = OSMMapThemeSatellite;
    } else {
        next = OSMMapThemeStandard;
    }

    if (next == OSMMapThemeSatellite) {
        [self.mapView removeOverlay:self.osmOverlay];
        self.mapView.mapType = MKMapTypeHybrid;
        [self.themeButton setTitle:@"☀️" forState:UIControlStateNormal];
        [[VoiceGuidanceService sharedService] speak:NLString(@"SAT_MODE", @"Modalità satellite attivata.")];
    } else if (next == OSMMapThemeDark) {
        self.mapView.mapType = MKMapTypeStandard;
        [self.osmOverlay switchTheme:OSMMapThemeDark];
        [self.mapView removeOverlay:self.osmOverlay];
        [self.mapView addOverlay:self.osmOverlay level:MKOverlayLevelAboveRoads];
        [self.themeButton setTitle:@"🛰️" forState:UIControlStateNormal];
        [[VoiceGuidanceService sharedService] speak:NLString(@"NIGHT_MODE", @"Modalità notturna attivata.")];
    } else {
        self.mapView.mapType = MKMapTypeStandard;
        [self.osmOverlay switchTheme:OSMMapThemeStandard];
        [self.mapView removeOverlay:self.osmOverlay];
        [self.mapView addOverlay:self.osmOverlay level:MKOverlayLevelAboveRoads];
        [self.themeButton setTitle:@"🌙" forState:UIControlStateNormal];
        [[VoiceGuidanceService sharedService] speak:NLString(@"DAY_MODE", @"Mappa standard attivata.")];
    }
}

- (void)toggleMute {
    VoiceGuidanceService *voice = [VoiceGuidanceService sharedService];
    voice.isMuted = !voice.isMuted;
    [self.muteButton setTitle:(voice.isMuted ? @"🔇" : @"🔊") forState:UIControlStateNormal];
}

static double DistanceFromCoordinateToPolyline(CLLocationCoordinate2D coord, MKPolyline *polyline) {
    if (!polyline || polyline.pointCount == 0) return 0.0;
    MKMapPoint p = MKMapPointForCoordinate(coord);
    NSUInteger count = polyline.pointCount;
    MKMapPoint *pts = polyline.points;

    double minDistance = DBL_MAX;
    for (NSUInteger i = 0; i < count - 1; i++) {
        MKMapPoint a = pts[i];
        MKMapPoint b = pts[i+1];
        double dx = b.x - a.x;
        double dy = b.y - a.y;
        double lenSq = dx * dx + dy * dy;
        MKMapPoint closest;
        if (lenSq == 0.0) {
            closest = a;
        } else {
            double t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq;
            if (t < 0.0) t = 0.0;
            else if (t > 1.0) t = 1.0;
            closest = MKMapPointMake(a.x + t * dx, a.y + t * dy);
        }
        double d = MKMetersBetweenMapPoints(p, closest);
        if (d < minDistance) {
            minDistance = d;
        }
    }
    return minDistance;
}

static int DeduceSpeedLimitFromRoadName(NSString *roadName) {
    if (!roadName || roadName.length == 0) return 50;
    
    NSString *upper = [roadName uppercaseString];
    
    // Autostrade: A1, A6, A10, A21, AUTOSTRADA... -> 130 km/h
    if ([upper containsString:@"AUTOSTRADA"]) return 130;
    NSRegularExpression *motorwayRegex = [NSRegularExpression regularExpressionWithPattern:@"\\bA[0-9]{1,2}\\b" options:0 error:nil];
    if ([motorwayRegex numberOfMatchesInString:upper options:0 range:NSMakeRange(0, upper.length)] > 0) {
        return 130;
    }
    
    // Tangenziali, Raccordi autostradali -> 110 km/h
    if ([upper containsString:@"TANGENZIALE"] || [upper containsString:@"SUPERSTRADA"] || [upper containsString:@"RACCORDO"]) {
        return 110;
    }
    NSRegularExpression *raRegex = [NSRegularExpression regularExpressionWithPattern:@"\\bRA[0-9]{1,2}\\b" options:0 error:nil];
    if ([raRegex numberOfMatchesInString:upper options:0 range:NSMakeRange(0, upper.length)] > 0) {
        return 110;
    }
    
    // Strade Statali, Regionali, Provinciali -> 90 km/h
    NSRegularExpression *extraurbanRegex = [NSRegularExpression regularExpressionWithPattern:@"\\b(SS|SR|SP)[0-9]+" options:0 error:nil];
    if ([extraurbanRegex numberOfMatchesInString:upper options:0 range:NSMakeRange(0, upper.length)] > 0) {
        return 90;
    }
    if ([upper containsString:@"STATALE"] || [upper containsString:@"PROVINCIALE"] || [upper containsString:@"REGIONALE"]) {
        return 90;
    }
    
    // Strade urbane (Via, Corso, Viale, Piazza, ecc.) -> 50 km/h
    return 50;
}

- (void)cancelCurrentRoute {
    self.currentRouteRequestId++;
    self.isNavigating = NO;
    self.routeSelector.hidden = YES;
    self.tripBar.hidden = YES;
    self.maneuverHUD.hidden = YES;
    [self.speedometer setDynamicSpeedLimit:0];

    // Ripristina barra di ricerca e POI in alto
    self.topSearchPill.hidden = NO;
    self.poiShelf.hidden = NO;

    // Rimuovi TUTTE le polylines dalla mappa per garantire una pulizia perfetta
    for (id<MKOverlay> overlay in [self.mapView.overlays copy]) {
        if ([overlay isKindOfClass:[MKPolyline class]]) {
            [self.mapView removeOverlay:overlay];
        }
    }

    // Rimuovi pin destinazione e annotazioni temporanee
    if (self.destinationPin) {
        [self.mapView removeAnnotation:self.destinationPin];
        self.destinationPin = nil;
    }
    if (self.poiAnnotations.count > 0) {
        [self.mapView removeAnnotations:self.poiAnnotations];
        [self.poiAnnotations removeAllObjects];
    }

    self.availableRoutes = nil;
    self.currentRoute = nil;
    self.currentStepIndex = 0;
    self.offRouteConsecutiveCount = 0;

    [self.maneuverHUD reset];
    [[VoiceGuidanceService sharedService] resetManeuverTracking];
    [[VoiceGuidanceService sharedService] speak:NLString(@"NAV_ENDED", @"Navigazione terminata.")];

    [self applyCameraPerspectiveAnimated:YES];
}

- (void)repeatCurrentInstruction {
    if (self.isNavigating && self.currentRoute && self.currentStepIndex < self.currentRoute.steps.count) {
        ManeuverStep *step = self.currentRoute.steps[self.currentStepIndex];
        [[VoiceGuidanceService sharedService] speak:step.instruction];
    }
}

#pragma mark - Search & Route Calculation (Itinerari Multipli)

- (void)handleMapLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    CGPoint point = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];

    // Rimuovi eventuali pin temporanei precedenti
    [self.mapView removeAnnotations:self.poiAnnotations];
    [self.poiAnnotations removeAllObjects];

    MKPointAnnotation *pin = [[MKPointAnnotation alloc] init];
    pin.coordinate = coord;
    pin.title = @"Destinazione selezionata";
    [self.poiAnnotations addObject:pin];
    [self.mapView addAnnotation:pin];

    [self searchViewControllerDidSelectLocation:coord title:@"Punto sulla mappa"];
}

- (void)searchViewControllerDidSelectLocation:(CLLocationCoordinate2D)coordinate title:(NSString *)title {
    NSUInteger thisRequestId = ++self.currentRouteRequestId;
    [SearchViewController saveRecentDestinationWithTitle:title coordinate:coordinate];

    CLLocationCoordinate2D startCoord;
    if (self.currentLocation && CLLocationCoordinate2DIsValid(self.currentLocation.coordinate) && self.currentLocation.coordinate.latitude != 0) {
        startCoord = self.currentLocation.coordinate;
    } else if (self.mapView.userLocation.location && CLLocationCoordinate2DIsValid(self.mapView.userLocation.location.coordinate) && self.mapView.userLocation.location.coordinate.latitude != 0) {
        startCoord = self.mapView.userLocation.location.coordinate;
    } else if (CLLocationCoordinate2DIsValid(self.mapView.centerCoordinate) && self.mapView.centerCoordinate.latitude != 0) {
        startCoord = self.mapView.centerCoordinate;
    } else {
        startCoord = CLLocationCoordinate2DMake(45.4642, 9.1900); // Default Milano
    }

    [self.topSearchPill setTitle:NLString(@"SEARCH_PLACEHOLDER", @"  🔍 Cerca destinazione o indirizzo...") forState:UIControlStateNormal];
    [[VoiceGuidanceService sharedService] speak:NLString(@"SEARCHING_ROUTES", @"Ricerca itinerari alternativi...")];

    __weak NavigationViewController *weakSelf = self;
    [[RoutingService sharedService] calculateRoutesFrom:startCoord to:coordinate destinationTitle:title completion:^(NSArray<RouteInfo *> *routes, NSError *error) {
        if (!weakSelf || weakSelf.currentRouteRequestId != thisRequestId) {
            NSLog(@"[NavigationViewController] Itinerario scartato: richiesta annullata o superata.");
            return;
        }

        [weakSelf.topSearchPill setTitle:NLString(@"SEARCH_PLACEHOLDER", @"  🔍 Cerca destinazione o indirizzo...") forState:UIControlStateNormal];

        if (error || routes.count == 0) {
            NSString *errPrompt = (error.code == -2)
                ? NLString(@"NO_ROUTE_FOUND", @"Nessun percorso stradale trovato per questa destinazione.")
                : NLString(@"CALC_ERROR", @"Errore nel calcolo del percorso.");
            [[VoiceGuidanceService sharedService] speak:errPrompt];
            return;
        }

        // Pulisci overlay precedenti
        for (id<MKOverlay> overlay in [weakSelf.mapView.overlays copy]) {
            if ([overlay isKindOfClass:[MKPolyline class]]) {
                [weakSelf.mapView removeOverlay:overlay];
            }
        }

        // Imposta pin di destinazione
        if (weakSelf.destinationPin) {
            [weakSelf.mapView removeAnnotation:weakSelf.destinationPin];
        }
        weakSelf.destinationPin = [[MKPointAnnotation alloc] init];
        weakSelf.destinationPin.coordinate = coordinate;
        weakSelf.destinationPin.title = title ?: @"Destinazione";
        [weakSelf.mapView addAnnotation:weakSelf.destinationPin];

        weakSelf.availableRoutes = routes;
        weakSelf.currentRoute = routes[0];
        weakSelf.currentStepIndex = 0;

        for (RouteInfo *r in routes) {
            if (r.polyline) {
                [weakSelf.mapView addOverlay:r.polyline level:MKOverlayLevelAboveLabels];
            }
        }

        [weakSelf.mapView setVisibleMapRect:routes[0].polyline.boundingMapRect
                                edgePadding:UIEdgeInsetsMake(120, 60, 220, 60)
                                   animated:YES];

        // Mostra il selettore itinerari
        [weakSelf.routeSelector setRoutes:routes];
        weakSelf.routeSelector.hidden = NO;

        // Nascondi barre superiori per non ingombrare
        weakSelf.topSearchPill.hidden = YES;
        weakSelf.poiShelf.hidden = YES;

        NSString *fmt = NLString(@"FOUND_ROUTES_VOICE", @"Trovati %lu itinerari. Tocca quello desiderato per iniziare.");
        NSString *msg = [NSString stringWithFormat:fmt, (unsigned long)routes.count];
        [[VoiceGuidanceService sharedService] speak:msg];
    }];
}

#pragma mark - SearchViewControllerDelegate (Show All POIs on Map)

- (void)searchViewControllerDidRequestShowAllPOIs:(NSArray<MKPointAnnotation *> *)annotations categoryName:(NSString *)categoryName {
    // Rimuovi pin precedenti
    [self.mapView removeAnnotations:self.poiAnnotations];
    [self.poiAnnotations removeAllObjects];

    // Aggiungi tutti i pin
    [self.poiAnnotations addObjectsFromArray:annotations];
    [self.mapView addAnnotations:annotations];

    // Zoom automatico per inquadrare tutti i POI
    if (annotations.count > 0) {
        [self.mapView showAnnotations:annotations animated:YES];
    }

    // Mostra la scheda risultati POI
    [self.poiResultsCard showWithAnnotations:annotations
                                categoryName:categoryName
                             currentLocation:self.currentLocation];

    NSString *msg = [NSString stringWithFormat:@"Trovati %lu risultati per %@ sulla mappa.", (unsigned long)annotations.count, categoryName];
    [[VoiceGuidanceService sharedService] speak:msg];
}

#pragma mark - RouteSelectorViewDelegate

- (void)routeSelectorView:(RouteSelectorView *)view didSelectRouteIndex:(NSUInteger)index {
    if (index >= self.availableRoutes.count) return;

    self.currentRoute = self.availableRoutes[index];
    self.currentStepIndex = 0;

    for (RouteInfo *r in self.availableRoutes) {
        if (r.polyline) {
            [self.mapView removeOverlay:r.polyline];
            [self.mapView addOverlay:r.polyline level:MKOverlayLevelAboveLabels];
        }
    }
}

- (void)routeSelectorView:(RouteSelectorView *)view didConfirmStartRoute:(RouteInfo *)selectedRoute {
    self.currentRoute = selectedRoute;
    self.isNavigating = YES;
    self.routeSelector.hidden = YES;
    self.offRouteConsecutiveCount = 0;

    for (RouteInfo *r in self.availableRoutes) {
        if (r != selectedRoute && r.polyline) {
            [self.mapView removeOverlay:r.polyline];
        }
    }
    if (selectedRoute.polyline) {
        [self.mapView removeOverlay:selectedRoute.polyline];
        [self.mapView addOverlay:selectedRoute.polyline level:MKOverlayLevelAboveLabels];
    }

    // Mostra HUD di guida in stile Waze e Google Maps
    self.maneuverHUD.hidden = NO;
    self.tripBar.hidden = NO;

    // Chiudi la toolbar automaticamente durante la navigazione
    if (self.toolbarExpanded) {
        [self toggleToolbar];
    }

    if (self.currentRoute.steps.count > 0) {
        ManeuverStep *step1 = self.currentRoute.steps[0];
        ManeuverStep *step2 = (self.currentRoute.steps.count > 1) ? self.currentRoute.steps[1] : nil;
        [self.maneuverHUD updateWithManeuver:step1 distanceToStep:step1.distance nextStep:step2];
    }
    [self.tripBar updateRemainingDistance:self.currentRoute.totalDistance
                                 duration:self.currentRoute.totalDuration
                            trafficStatus:self.currentRoute.trafficDescription];

    [self applyCameraPerspectiveAnimated:YES];

    BOOL isIt = [[LocalizationManager sharedManager] isItalian];
    NSString *prompt = isIt ? [NSString stringWithFormat:@"Inizia a guidare verso %@.", self.currentRoute.destinationTitle]
                            : [NSString stringWithFormat:@"Start driving towards %@.", self.currentRoute.destinationTitle];
    [[VoiceGuidanceService sharedService] speak:prompt];
}

- (void)routeSelectorViewDidCancel:(RouteSelectorView *)view {
    [self cancelCurrentRoute];
}

#pragma mark - QuickPOIShelfViewDelegate

- (void)quickPOIShelfView:(QuickPOIShelfView *)shelf didRequestSearchCategory:(NSString *)query categoryName:(NSString *)categoryName {
    CLLocationCoordinate2D center = self.currentLocation ? self.currentLocation.coordinate : CLLocationCoordinate2DMake(45.4642, 9.1900);
    [shelf searchCategory:query fromCoordinate:center categoryName:categoryName];
}

- (void)quickPOIShelfView:(QuickPOIShelfView *)shelf didFindPOIs:(NSArray<MKPointAnnotation *> *)annotations categoryName:(NSString *)category {
    [self.mapView removeAnnotations:self.poiAnnotations];
    [self.poiAnnotations removeAllObjects];

    [self.poiAnnotations addObjectsFromArray:annotations];
    [self.mapView addAnnotations:annotations];

    // Zoom automatico per inquadrare tutti i POI trovati
    if (annotations.count > 0) {
        [self.mapView showAnnotations:annotations animated:YES];
    }

    // Mostra la scheda risultati POI con distanze e tasto Naviga
    [self.poiResultsCard showWithAnnotations:annotations
                                categoryName:category
                             currentLocation:self.currentLocation];

    NSString *msg = [NSString stringWithFormat:@"Trovati %lu %@ nelle vicinanze.", (unsigned long)annotations.count, category];
    [[VoiceGuidanceService sharedService] speak:msg];
}

- (void)quickPOIShelfViewDidRequestClose:(QuickPOIShelfView *)shelf {
    // Opzionale
}

#pragma mark - POIResultsCardViewDelegate

- (void)poiResultsCardView:(POIResultsCardView *)card didSelectNavigateToPOI:(MKPointAnnotation *)annotation {
    // Avvia il calcolo del percorso verso il POI selezionato
    [self searchViewControllerDidSelectLocation:annotation.coordinate title:annotation.title];
}

#pragma mark - MKMapViewDelegate (Annotation Views)

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) {
        return nil;
    }

    static NSString *poiId = @"POIAnnotation";
    MKPinAnnotationView *pin = (MKPinAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:poiId];
    if (!pin) {
        pin = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:poiId];
        pin.canShowCallout = YES;
        pin.animatesDrop = YES;

        UIButton *rightBtn = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        pin.rightCalloutAccessoryView = rightBtn;
    } else {
        pin.annotation = annotation;
    }

    // Colore pin in base al tipo (verde per POI, rosso per destinazione)
    if ([pin respondsToSelector:@selector(setPinTintColor:)]) {
        pin.pinTintColor = [UIColor colorWithRed:0.15 green:0.65 blue:0.35 alpha:1.0];
    }

    return pin;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control {
    id<MKAnnotation> ann = view.annotation;
    if (ann) {
        [self searchViewControllerDidSelectLocation:ann.coordinate title:ann.title];
    }
}

#pragma mark - Gestione Posizione & Ricalcolo Fuori Rotta

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorizedAlways || status == kCLAuthorizationStatusAuthorizedWhenInUse) {
        [manager startUpdatingLocation];
        [manager startUpdatingHeading];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = [locations lastObject];
    if (loc) {
        self.gpsSourceLabel.text = @"GPS: iOS Interno/Hotspot";
        [self processLocationUpdate:loc heading:self.currentHeading];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
    self.currentHeading = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading;
}

- (void)networkGPSDidUpdateLocation:(CLLocation *)location heading:(CLLocationDirection)heading {
    self.gpsSourceLabel.text = @"GPS: Rete Android (UDP 8888)";
    self.currentHeading = heading;
    [self processLocationUpdate:location heading:heading];
}

- (void)processLocationUpdate:(CLLocation *)location heading:(CLLocationDirection)heading {
    self.currentLocation = location;
    [self.speedometer updateSpeed:location.speed];

    // In modalità 3D e durante la navigazione, la telecamera segue dinamicamente l'auto
    if (self.is3DMode && self.isNavigating) {
        [self applyCameraPerspectiveAnimated:YES];
    }

    if (!self.isNavigating || !self.currentRoute) {
        return;
    }

    // Avanzamento manovre e tracciamento percorso
    if (self.currentStepIndex < self.currentRoute.steps.count) {
        ManeuverStep *targetStep = self.currentRoute.steps[self.currentStepIndex];
        CLLocation *stepLoc = [[CLLocation alloc] initWithLatitude:targetStep.coordinate.latitude
                                                         longitude:targetStep.coordinate.longitude];
        CLLocationDistance distToStep = [location distanceFromLocation:stepLoc];

        // Aggiorna limite di velocità dinamico in base al tipo di strada attuale
        int dynamicLimit = DeduceSpeedLimitFromRoadName(targetStep.streetName);
        [self.speedometer setDynamicSpeedLimit:dynamicLimit];

        // Calcolo dinamico reale della distanza rimanente verso destinazione (countdown continuo!)
        CLLocationDistance remainingDist = distToStep;
        for (NSUInteger i = self.currentStepIndex + 1; i < self.currentRoute.steps.count; i++) {
            remainingDist += self.currentRoute.steps[i].distance;
        }

        NSTimeInterval remainingDuration = 0;
        if (self.currentRoute.totalDistance > 0) {
            remainingDuration = self.currentRoute.totalDuration * (remainingDist / self.currentRoute.totalDistance);
        }

        ManeuverStep *nextStep = (self.currentStepIndex + 1 < self.currentRoute.steps.count) ? self.currentRoute.steps[self.currentStepIndex + 1] : nil;
        [self.maneuverHUD updateWithManeuver:targetStep distanceToStep:distToStep nextStep:nextStep];
        [self.tripBar updateRemainingDistance:remainingDist duration:remainingDuration trafficStatus:self.currentRoute.trafficDescription];

        // Istruzioni vocali discrete con checkpoint (1000m, 500m, 200m, Ora)
        [[VoiceGuidanceService sharedService] speakManeuver:targetStep.instruction distanceInMeters:distToStep stepIndex:self.currentStepIndex];

        // Avanzamento manovra al raggiungimento dell'incrocio/svolta
        if (distToStep < 30.0 && self.currentStepIndex + 1 < self.currentRoute.steps.count) {
            self.currentStepIndex++;
            ManeuverStep *newStep = self.currentRoute.steps[self.currentStepIndex];
            ManeuverStep *stepAfter = (self.currentStepIndex + 1 < self.currentRoute.steps.count) ? self.currentRoute.steps[self.currentStepIndex + 1] : nil;
            [self.maneuverHUD updateWithManeuver:newStep distanceToStep:newStep.distance nextStep:stepAfter];
            self.offRouteConsecutiveCount = 0;
        } else if (distToStep < 25.0 && self.currentStepIndex + 1 >= self.currentRoute.steps.count) {
            [[VoiceGuidanceService sharedService] speak:NLString(@"ARRIVED", @"Sei arrivato a destinazione.")];
            [self cancelCurrentRoute];
            return;
        }

        // Rilevamento Fuori Rotta intelligente basato sulla distanza perpendicolare dalla polyline del percorso
        double distToPolyline = DistanceFromCoordinateToPolyline(location.coordinate, self.currentRoute.polyline);
        if (distToPolyline > 65.0 && (location.speed < 0 || location.speed > 1.2)) {
            self.offRouteConsecutiveCount++;
            if (self.offRouteConsecutiveCount >= 4) {
                [self triggerAutoReroute];
                self.offRouteConsecutiveCount = 0;
            }
        } else if (distToPolyline <= 45.0) {
            self.offRouteConsecutiveCount = 0;
        }
    }
}

- (void)triggerAutoReroute {
    if (!self.isNavigating || !self.currentRoute) return;

    NSUInteger thisRequestId = ++self.currentRouteRequestId;
    [[VoiceGuidanceService sharedService] speak:NLString(@"RECALCULATING", @"Ricalcolo del percorso in corso...")];

    CLLocationCoordinate2D start;
    if (self.currentLocation && CLLocationCoordinate2DIsValid(self.currentLocation.coordinate) && self.currentLocation.coordinate.latitude != 0) {
        start = self.currentLocation.coordinate;
    } else if (self.mapView.userLocation.location && CLLocationCoordinate2DIsValid(self.mapView.userLocation.location.coordinate) && self.mapView.userLocation.location.coordinate.latitude != 0) {
        start = self.mapView.userLocation.location.coordinate;
    } else {
        start = self.mapView.centerCoordinate;
    }
    CLLocationCoordinate2D dest = self.currentRoute.destinationCoordinate;
    NSString *title = self.currentRoute.destinationTitle;

    __weak NavigationViewController *weakSelf = self;
    [[RoutingService sharedService] calculateRouteFrom:start to:dest destinationTitle:title completion:^(RouteInfo *newRoute, NSError *error) {
        if (!weakSelf || weakSelf.currentRouteRequestId != thisRequestId || !weakSelf.isNavigating) {
            NSLog(@"[NavigationViewController] Ricalcolo percorso scartato: richiesta annullata o obsoleta.");
            return;
        }
        if (error || !newRoute) return;

        // Rimuovi polylines precedenti
        for (id<MKOverlay> overlay in [weakSelf.mapView.overlays copy]) {
            if ([overlay isKindOfClass:[MKPolyline class]]) {
                [weakSelf.mapView removeOverlay:overlay];
            }
        }

        weakSelf.currentRoute = newRoute;
        weakSelf.currentStepIndex = 0;
        [weakSelf.mapView addOverlay:newRoute.polyline level:MKOverlayLevelAboveLabels];

        if (newRoute.steps.count > 0) {
            ManeuverStep *step1 = newRoute.steps[0];
            ManeuverStep *step2 = (newRoute.steps.count > 1) ? newRoute.steps[1] : nil;
            [weakSelf.maneuverHUD updateWithManeuver:step1 distanceToStep:step1.distance nextStep:step2];
        }
        [weakSelf.tripBar updateRemainingDistance:newRoute.totalDistance duration:newRoute.totalDuration trafficStatus:newRoute.trafficDescription];

        [[VoiceGuidanceService sharedService] resetManeuverTracking];
        [[VoiceGuidanceService sharedService] speak:NLString(@"NEW_ROUTE_READY", @"Nuovo percorso pronto. Continua a guidare.")];
    }];
}

#pragma mark - SettingsViewControllerDelegate

- (void)settingsViewControllerDidUpdateSettings:(SettingsViewController *)controller {
    NSInteger themeIdx = [[NSUserDefaults standardUserDefaults] integerForKey:@"MapThemeIndex"];
    if (themeIdx == 2) {
        // Satellite
        [self.mapView removeOverlay:self.osmOverlay];
        self.mapView.mapType = MKMapTypeHybrid;
        [self.themeButton setTitle:@"☀️" forState:UIControlStateNormal];
    } else if (themeIdx == 1) {
        // Notte (Esri Dark Canvas)
        self.mapView.mapType = MKMapTypeStandard;
        [self.osmOverlay switchTheme:OSMMapThemeDark];
        [self.mapView removeOverlay:self.osmOverlay];
        [self.mapView addOverlay:self.osmOverlay level:MKOverlayLevelAboveRoads];
        [self.themeButton setTitle:@"🛰️" forState:UIControlStateNormal];
    } else {
        // Giorno (OSM Standard)
        self.mapView.mapType = MKMapTypeStandard;
        [self.osmOverlay switchTheme:OSMMapThemeStandard];
        [self.mapView removeOverlay:self.osmOverlay];
        [self.mapView addOverlay:self.osmOverlay level:MKOverlayLevelAboveRoads];
        [self.themeButton setTitle:@"🌙" forState:UIControlStateNormal];
    }
}

#pragma mark - MKMapViewDelegate

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    if ([overlay isKindOfClass:[OSMTileOverlay class]]) {
        return [[MKTileOverlayRenderer alloc] initWithTileOverlay:(MKTileOverlay *)overlay];
    }

    if ([overlay isKindOfClass:[TrafficTileOverlay class]]) {
        MKTileOverlayRenderer *r = [[MKTileOverlayRenderer alloc] initWithTileOverlay:(MKTileOverlay *)overlay];
        r.alpha = 0.85;
        return r;
    }

    if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        renderer.lineCap = kCGLineCapRound;
        renderer.lineJoin = kCGLineJoinRound;

        if (self.currentRoute && overlay == self.currentRoute.polyline) {
            // Percorso attivo in blu elettrico brillante (#007AFF) ad alto contrasto
            renderer.strokeColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:0.95];
            renderer.lineWidth = 8.5;
        } else {
            // Alternative in grigio/azzurro (#6C7A89) ben distinguibile
            renderer.strokeColor = [UIColor colorWithRed:0.45 green:0.52 blue:0.62 alpha:0.80];
            renderer.lineWidth = 6.0;
        }
        return renderer;
    }
    return nil;
}

@end

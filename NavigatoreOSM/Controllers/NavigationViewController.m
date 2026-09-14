#import "NavigationViewController.h"
#import "SearchViewController.h"
#import "../Overlays/OSMTileOverlay.h"
#import "../Overlays/TrafficTileOverlay.h"
#import "../Services/RoutingService.h"
#import "../Services/VoiceGuidanceService.h"
#import "../Services/NetworkGPSReceiver.h"
#import "../Views/SpeedometerView.h"
#import "../Views/ManeuverHUDView.h"
#import "../Views/RouteSelectorView.h"
#import "../Views/QuickPOIShelfView.h"

@interface NavigationViewController () <SearchViewControllerDelegate, NetworkGPSReceiverDelegate, RouteSelectorViewDelegate, QuickPOIShelfViewDelegate>

@property (nonatomic, strong) OSMTileOverlay *osmOverlay;
@property (nonatomic, strong) TrafficTileOverlay *trafficOverlay;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *currentLocation;
@property (nonatomic, assign) CLLocationDirection currentHeading;

// UI HUD
@property (nonatomic, strong) ManeuverHUDView *maneuverHUD;
@property (nonatomic, strong) SpeedometerView *speedometer;
@property (nonatomic, strong) RouteSelectorView *routeSelector;
@property (nonatomic, strong) QuickPOIShelfView *poiShelf;

@property (nonatomic, strong) UIButton *searchButton;
@property (nonatomic, strong) UIButton *poiButton;
@property (nonatomic, strong) UIButton *recenterButton;
@property (nonatomic, strong) UIButton *themeButton;
@property (nonatomic, strong) UIButton *trafficButton;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UIButton *cancelRouteButton;
@property (nonatomic, strong) UILabel *gpsSourceLabel;

// Stato Itinerari e Navigazione
@property (nonatomic, strong) NSArray<RouteInfo *> *availableRoutes;
@property (nonatomic, strong) RouteInfo *currentRoute;
@property (nonatomic, assign) NSUInteger currentStepIndex;
@property (nonatomic, assign) BOOL isNavigating;
@property (nonatomic, assign) NSInteger offRouteConsecutiveCount;
@property (nonatomic, strong) NSMutableArray<MKPointAnnotation *> *poiAnnotations;

@end

@implementation NavigationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    // 1. Evita assolutamente lo spegnimento dello schermo durante la guida!
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    // 2. Mappa Nativa con MapKit
    self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    self.mapView.userTrackingMode = MKUserTrackingModeFollowWithHeading;
    [self.view addSubview:self.mapView];

    // 3. Sovrapponi il layer OpenStreetMap base
    self.osmOverlay = [[OSMTileOverlay alloc] initWithTheme:OSMMapThemeStandard];
    [self.mapView addOverlay:self.osmOverlay level:MKOverlayLevelAboveLabels];

    // 4. Sovrapponi il layer Traffico in tempo reale
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
    self.locationManager.headingFilter = 3.0;

    if ([self.locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
        [self.locationManager requestWhenInUseAuthorization];
    }
    [self.locationManager startUpdatingLocation];
    [self.locationManager startUpdatingHeading];

    // 6. Avvia ricevitore GPS di rete (UDP 8888) per tethering da Android
    [NetworkGPSReceiver sharedReceiver].delegate = self;
    [[NetworkGPSReceiver sharedReceiver] startListeningOnPort:8888];

    self.poiAnnotations = [NSMutableArray array];

    // 8. Costruisci tutti i controlli HUD per auto
    [self setupUIControls];

    // Messaggio vocale di avvio
    [[VoiceGuidanceService sharedService] speak:@"Navigatore pronto con mappe OpenStreetMap e traffico."];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

#pragma mark - Setup UI Controls

- (void)setupUIControls {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    // Scheda Manovre in alto a sinistra
    self.maneuverHUD = [[ManeuverHUDView alloc] initWithFrame:CGRectMake(20, 20, 380, 95)];
    self.maneuverHUD.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    __weak NavigationViewController *weakSelf = self;
    self.maneuverHUD.onTapBlock = ^{
        [weakSelf repeatCurrentInstruction];
    };
    [self.view addSubview:self.maneuverHUD];

    // Tachimetro in basso a sinistra
    self.speedometer = [[SpeedometerView alloc] initWithFrame:CGRectMake(20, h - 115, 95, 95)];
    self.speedometer.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.speedometer];

    // Etichetta sorgente GPS
    self.gpsSourceLabel = [[UILabel alloc] initWithFrame:CGRectMake(125, h - 35, 220, 20)];
    self.gpsSourceLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.gpsSourceLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.gpsSourceLabel.textColor = [UIColor colorWithWhite:0.25 alpha:0.85];
    self.gpsSourceLabel.text = @"GPS: In attesa di fix...";
    [self.view addSubview:self.gpsSourceLabel];

    // Pulsanti in alto a destra: Cerca e POI
    self.searchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.searchButton.frame = CGRectMake(w - 135, 20, 115, 46);
    self.searchButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.searchButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.5 blue:1.0 alpha:0.92];
    self.searchButton.layer.cornerRadius = 14.0;
    self.searchButton.layer.shadowColor = [[UIColor blackColor] CGColor];
    self.searchButton.layer.shadowOpacity = 0.4;
    self.searchButton.layer.shadowRadius = 6.0;
    self.searchButton.layer.shadowOffset = CGSizeMake(0, 3);
    [self.searchButton setTitle:@"🔍 Cerca" forState:UIControlStateNormal];
    [self.searchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.searchButton.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
    [self.searchButton addTarget:self action:@selector(openSearch) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.searchButton];

    self.poiButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.poiButton.frame = CGRectMake(w - 245, 20, 100, 46);
    self.poiButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.poiButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.4 alpha:0.92];
    self.poiButton.layer.cornerRadius = 14.0;
    [self.poiButton setTitle:@"📍 POI" forState:UIControlStateNormal];
    [self.poiButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.poiButton.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
    [self.poiButton addTarget:self action:@selector(togglePOIShelf) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.poiButton];

    // Pulsante Chiudi Rotta
    self.cancelRouteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cancelRouteButton.frame = CGRectMake(w - 180, 76, 160, 42);
    self.cancelRouteButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.cancelRouteButton.backgroundColor = [UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:0.92];
    self.cancelRouteButton.layer.cornerRadius = 12.0;
    [self.cancelRouteButton setTitle:@"✕ Chiudi Rotta" forState:UIControlStateNormal];
    [self.cancelRouteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.cancelRouteButton.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    self.cancelRouteButton.hidden = YES;
    [self.cancelRouteButton addTarget:self action:@selector(cancelCurrentRoute) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cancelRouteButton];

    // Pulsanti circolari di controllo in basso a destra
    CGFloat btnY = h - 68;
    CGFloat btnSpacing = 58;

    // 1. Centra e Ruota con bussola
    self.recenterButton = [self createCircularButtonWithTitle:@"🎯" frame:CGRectMake(w - 68, btnY, 48, 48)];
    [self.recenterButton addTarget:self action:@selector(recenterMap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.recenterButton];

    // 2. Toggle Traffico
    self.trafficButton = [self createCircularButtonWithTitle:@"🚦" frame:CGRectMake(w - 68 - btnSpacing, btnY, 48, 48)];
    [self.trafficButton addTarget:self action:@selector(toggleTraffic) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.trafficButton];

    // 3. Toggle Tema Notte/Giorno
    self.themeButton = [self createCircularButtonWithTitle:@"🌙" frame:CGRectMake(w - 68 - (btnSpacing * 2), btnY, 48, 48)];
    [self.themeButton addTarget:self action:@selector(toggleMapTheme) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.themeButton];

    // 4. Toggle Mute Voce
    self.muteButton = [self createCircularButtonWithTitle:@"🔊" frame:CGRectMake(w - 68 - (btnSpacing * 3), btnY, 48, 48)];
    [self.muteButton addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.muteButton];

    // Barra rapida POI (nascosta di default)
    self.poiShelf = [[QuickPOIShelfView alloc] initWithFrame:CGRectMake(20, 125, w - 40, 52)];
    self.poiShelf.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    self.poiShelf.delegate = self;
    self.poiShelf.hidden = YES;
    [self.view addSubview:self.poiShelf];

    // Selettore Itinerari in basso (nascosto di default)
    self.routeSelector = [[RouteSelectorView alloc] initWithFrame:CGRectMake(30, h - 195, w - 60, 175)];
    self.routeSelector.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.routeSelector.delegate = self;
    self.routeSelector.hidden = YES;
    [self.view addSubview:self.routeSelector];
}

- (UIButton *)createCircularButtonWithTitle:(NSString *)title frame:(CGRect)frame {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    btn.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.88];
    btn.layer.cornerRadius = frame.size.width / 2.0;
    btn.layer.borderColor = [[UIColor colorWithWhite:0.35 alpha:0.7] CGColor];
    btn.layer.borderWidth = 1.0;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:22.0];
    return btn;
}

#pragma mark - Azioni e Toggle

- (void)openSearch {
    SearchViewController *searchVC = [[SearchViewController alloc] init];
    searchVC.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:searchVC];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)togglePOIShelf {
    self.poiShelf.hidden = !self.poiShelf.hidden;
}

- (void)recenterMap {
    if (self.currentLocation) {
        [self.mapView setUserTrackingMode:MKUserTrackingModeFollowWithHeading animated:YES];
    }
}

- (void)toggleTraffic {
    self.trafficOverlay.isEnabled = !self.trafficOverlay.isEnabled;
    if (self.trafficOverlay.isEnabled) {
        [self.mapView addOverlay:self.trafficOverlay level:MKOverlayLevelAboveRoads];
        [self.trafficButton setTitle:@"🚦" forState:UIControlStateNormal];
        [[VoiceGuidanceService sharedService] speak:@"Traffico attivato."];
    } else {
        [self.mapView removeOverlay:self.trafficOverlay];
        [self.trafficButton setTitle:@"⚪" forState:UIControlStateNormal];
        [[VoiceGuidanceService sharedService] speak:@"Traffico disattivato."];
    }
}

- (void)toggleMapTheme {
    OSMMapTheme next = (self.osmOverlay.theme == OSMMapThemeStandard) ? OSMMapThemeDark : OSMMapThemeStandard;
    [self.osmOverlay switchTheme:next];
    [self.themeButton setTitle:(next == OSMMapThemeDark ? @"☀️" : @"🌙") forState:UIControlStateNormal];

    [self.mapView removeOverlay:self.osmOverlay];
    [self.mapView addOverlay:self.osmOverlay level:MKOverlayLevelAboveLabels];
}

- (void)toggleMute {
    VoiceGuidanceService *voice = [VoiceGuidanceService sharedService];
    voice.isMuted = !voice.isMuted;
    [self.muteButton setTitle:(voice.isMuted ? @"🔇" : @"🔊") forState:UIControlStateNormal];
}

- (void)cancelCurrentRoute {
    self.isNavigating = NO;
    self.routeSelector.hidden = YES;
    self.cancelRouteButton.hidden = YES;

    // Rimuovi tutti i percorsi polylines dalla mappa
    if (self.availableRoutes) {
        for (RouteInfo *r in self.availableRoutes) {
            if (r.polyline) [self.mapView removeOverlay:r.polyline];
        }
    }
    if (self.currentRoute && self.currentRoute.polyline) {
        [self.mapView removeOverlay:self.currentRoute.polyline];
    }

    self.availableRoutes = nil;
    self.currentRoute = nil;
    [self.maneuverHUD reset];
    [[VoiceGuidanceService sharedService] speak:@"Navigazione terminata."];
}

- (void)repeatCurrentInstruction {
    if (self.isNavigating && self.currentRoute && self.currentStepIndex < self.currentRoute.steps.count) {
        ManeuverStep *step = self.currentRoute.steps[self.currentStepIndex];
        [[VoiceGuidanceService sharedService] speak:step.instruction];
    }
}

#pragma mark - Search & Route Calculation (Itinerari Multipli)

- (void)searchViewControllerDidSelectLocation:(CLLocationCoordinate2D)coordinate title:(NSString *)title {
    CLLocationCoordinate2D startCoord;
    if (self.currentLocation) {
        startCoord = self.currentLocation.coordinate;
    } else {
        startCoord = CLLocationCoordinate2DMake(45.4642, 9.1900); // Default Milano
    }

    [[VoiceGuidanceService sharedService] speak:@"Ricerca itinerari alternativi e analisi traffico..."];

    __weak NavigationViewController *weakSelf = self;
    [[RoutingService sharedService] calculateRoutesFrom:startCoord to:coordinate destinationTitle:title completion:^(NSArray<RouteInfo *> *routes, NSError *error) {
        if (error || routes.count == 0) {
            [[VoiceGuidanceService sharedService] speak:@"Impossibile calcolare itinerari per questa destinazione."];
            return;
        }

        // Pulisci vecchi percorsi
        if (weakSelf.availableRoutes) {
            for (RouteInfo *oldR in weakSelf.availableRoutes) {
                if (oldR.polyline) [weakSelf.mapView removeOverlay:oldR.polyline];
            }
        }

        weakSelf.availableRoutes = routes;
        weakSelf.currentRoute = routes[0];
        weakSelf.currentStepIndex = 0;

        // Disegna tutti i percorsi (le alternative e il principale)
        for (RouteInfo *r in routes) {
            if (r.polyline) {
                [weakSelf.mapView addOverlay:r.polyline level:MKOverlayLevelAboveRoads];
            }
        }

        // Inquadra la rotta principale
        [weakSelf.mapView setVisibleMapRect:routes[0].polyline.boundingMapRect
                                edgePadding:UIEdgeInsetsMake(120, 60, 210, 60)
                                   animated:YES];

        // Mostra il selettore itinerari
        [weakSelf.routeSelector setRoutes:routes];
        weakSelf.routeSelector.hidden = NO;
        weakSelf.cancelRouteButton.hidden = NO;

        // Aggiorna HUD
        if (routes[0].steps.count > 0) {
            [weakSelf.maneuverHUD updateWithManeuver:routes[0].steps[0] distanceToStep:routes[0].steps[0].distance];
        }
        [weakSelf.maneuverHUD updateTripRemainingDistance:routes[0].totalDistance
                                                 duration:routes[0].totalDuration
                                            trafficStatus:routes[0].trafficDescription];

        NSString *speakMsg = [NSString stringWithFormat:@"Trovati %lu itinerari. Il più veloce richiede %d minuti, traffico %@.",
                              (unsigned long)routes.count,
                              (int)ceil(routes[0].totalDuration / 60.0),
                              routes[0].trafficDescription];
        [[VoiceGuidanceService sharedService] speak:speakMsg];
    }];
}

#pragma mark - RouteSelectorViewDelegate

- (void)routeSelectorView:(RouteSelectorView *)view didSelectRouteIndex:(NSUInteger)index {
    if (index >= self.availableRoutes.count) return;

    self.currentRoute = self.availableRoutes[index];
    self.currentStepIndex = 0;

    // Ricarica i render per evidenziare il percorso selezionato
    for (RouteInfo *r in self.availableRoutes) {
        if (r.polyline) {
            [self.mapView removeOverlay:r.polyline];
            [self.mapView addOverlay:r.polyline level:MKOverlayLevelAboveRoads];
        }
    }

    if (self.currentRoute.steps.count > 0) {
        [self.maneuverHUD updateWithManeuver:self.currentRoute.steps[0] distanceToStep:self.currentRoute.steps[0].distance];
    }
    [self.maneuverHUD updateTripRemainingDistance:self.currentRoute.totalDistance
                                             duration:self.currentRoute.totalDuration
                                        trafficStatus:self.currentRoute.trafficDescription];
}

- (void)routeSelectorView:(RouteSelectorView *)view didConfirmStartRoute:(RouteInfo *)selectedRoute {
    self.currentRoute = selectedRoute;
    self.isNavigating = YES;
    self.routeSelector.hidden = YES;
    self.offRouteConsecutiveCount = 0;

    // Rimuovi i percorsi alternativi non scelti per mantenere la mappa pulita
    for (RouteInfo *r in self.availableRoutes) {
        if (r != selectedRoute && r.polyline) {
            [self.mapView removeOverlay:r.polyline];
        }
    }

    // Centra sulla posizione dell'auto con prospettiva 3D
    [self.mapView setUserTrackingMode:MKUserTrackingModeFollowWithHeading animated:YES];

    NSString *prompt = [NSString stringWithFormat:@"Navigazione avviata verso %@. Inizia a guidare.", self.currentRoute.destinationTitle];
    [[VoiceGuidanceService sharedService] speak:prompt];
}

- (void)routeSelectorViewDidCancel:(RouteSelectorView *)view {
    [self cancelCurrentRoute];
}

#pragma mark - Gestione POI e Annotazioni

- (void)quickPOIShelfView:(QuickPOIShelfView *)shelf didRequestSearchCategory:(NSString *)query categoryName:(NSString *)categoryName {
    CLLocationCoordinate2D center = self.currentLocation ? self.currentLocation.coordinate : CLLocationCoordinate2DMake(45.4642, 9.1900);
    [shelf searchCategory:query fromCoordinate:center categoryName:categoryName];
}

- (void)quickPOIShelfView:(QuickPOIShelfView *)shelf didFindPOIs:(NSArray<MKPointAnnotation *> *)annotations categoryName:(NSString *)category {
    // Rimuovi vecchi POI
    [self.mapView removeAnnotations:self.poiAnnotations];
    [self.poiAnnotations removeAllObjects];

    [self.poiAnnotations addObjectsFromArray:annotations];
    [self.mapView addAnnotations:annotations];

    self.poiShelf.hidden = YES;
    NSString *msg = [NSString stringWithFormat:@"Trovati %lu %@ nelle vicinanze.", (unsigned long)annotations.count, category];
    [[VoiceGuidanceService sharedService] speak:msg];
}

- (void)quickPOIShelfViewDidRequestClose:(QuickPOIShelfView *)shelf {
    self.poiShelf.hidden = YES;
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) {
        return nil; // Usa il puntino blu predefinito per l'utente
    }

    static NSString *poiId = @"POIAnnotation";
    MKPinAnnotationView *pin = (MKPinAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:poiId];
    if (!pin) {
        pin = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:poiId];
        pin.canShowCallout = YES;
        if ([pin respondsToSelector:@selector(setPinTintColor:)]) {
            pin.pinTintColor = [UIColor colorWithRed:0.6 green:0.2 blue:0.9 alpha:1.0];
        }
        pin.animatesDrop = YES;

        UIButton *rightBtn = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        pin.rightCalloutAccessoryView = rightBtn;
    } else {
        pin.annotation = annotation;
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

    if (!self.isNavigating || !self.currentRoute) {
        return;
    }

    // 1. Controllo avanzamento manovre
    if (self.currentStepIndex < self.currentRoute.steps.count) {
        ManeuverStep *targetStep = self.currentRoute.steps[self.currentStepIndex];
        CLLocation *stepLoc = [[CLLocation alloc] initWithLatitude:targetStep.coordinate.latitude
                                                         longitude:targetStep.coordinate.longitude];
        CLLocationDistance dist = [location distanceFromLocation:stepLoc];

        [self.maneuverHUD updateWithManeuver:targetStep distanceToStep:dist];
        [[VoiceGuidanceService sharedService] speakManeuver:targetStep.instruction distanceInMeters:dist];

        // Avanza se entro 35 metri
        if (dist < 35.0 && self.currentStepIndex + 1 < self.currentRoute.steps.count) {
            self.currentStepIndex++;
            ManeuverStep *nextStep = self.currentRoute.steps[self.currentStepIndex];
            [self.maneuverHUD updateWithManeuver:nextStep distanceToStep:nextStep.distance];
            [[VoiceGuidanceService sharedService] speak:nextStep.instruction];
            self.offRouteConsecutiveCount = 0;
        } else if (dist < 25.0 && self.currentStepIndex + 1 >= self.currentRoute.steps.count) {
            [[VoiceGuidanceService sharedService] speak:@"Sei arrivato a destinazione."];
            [self cancelCurrentRoute];
            return;
        }

        // 2. Controllo Fuori Rotta (Off-route Detection)
        if (dist > 75.0 && self.currentStepIndex > 0) {
            self.offRouteConsecutiveCount++;
            if (self.offRouteConsecutiveCount >= 4) { // 4 fix consecutivi fuori rotta
                [self triggerAutoReroute];
                self.offRouteConsecutiveCount = 0;
            }
        } else {
            self.offRouteConsecutiveCount = 0;
        }
    }
}

- (void)triggerAutoReroute {
    if (!self.currentRoute) return;

    [[VoiceGuidanceService sharedService] speak:@"Ricalcolo del percorso in corso..."];
    CLLocationCoordinate2D start = self.currentLocation.coordinate;
    CLLocationCoordinate2D dest = self.currentRoute.destinationCoordinate;
    NSString *title = self.currentRoute.destinationTitle;

    __weak NavigationViewController *weakSelf = self;
    [[RoutingService sharedService] calculateRouteFrom:start to:dest destinationTitle:title completion:^(RouteInfo *newRoute, NSError *error) {
        if (error || !newRoute) return;

        if (weakSelf.currentRoute && weakSelf.currentRoute.polyline) {
            [weakSelf.mapView removeOverlay:weakSelf.currentRoute.polyline];
        }

        weakSelf.currentRoute = newRoute;
        weakSelf.currentStepIndex = 0;
        [weakSelf.mapView addOverlay:newRoute.polyline level:MKOverlayLevelAboveRoads];

        if (newRoute.steps.count > 0) {
            [weakSelf.maneuverHUD updateWithManeuver:newRoute.steps[0] distanceToStep:newRoute.steps[0].distance];
        }
        [weakSelf.maneuverHUD updateTripRemainingDistance:newRoute.totalDistance
                                                 duration:newRoute.totalDuration
                                            trafficStatus:newRoute.trafficDescription];

        [[VoiceGuidanceService sharedService] speak:@"Nuovo percorso calcolato. Prosegui."];
    }];
}

#pragma mark - MKMapViewDelegate (Rendering Layer OSM, Traffico e Rotte)

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    // 1. Layer OpenStreetMap base
    if ([overlay isKindOfClass:[OSMTileOverlay class]]) {
        return [[MKTileOverlayRenderer alloc] initWithTileOverlay:(MKTileOverlay *)overlay];
    }

    // 2. Layer Traffico in tempo reale (trasparente su strade)
    if ([overlay isKindOfClass:[TrafficTileOverlay class]]) {
        MKTileOverlayRenderer *r = [[MKTileOverlayRenderer alloc] initWithTileOverlay:(MKTileOverlay *)overlay];
        r.alpha = 0.85;
        return r;
    }

    // 3. Tracciati Polylines dei Percorsi
    if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        renderer.lineCap = kCGLineCapRound;
        renderer.lineJoin = kCGLineJoinRound;

        // Se è la rotta attiva/selezionata: Blu brillante spessa
        if (self.currentRoute && overlay == self.currentRoute.polyline) {
            renderer.strokeColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:0.92];
            renderer.lineWidth = 7.5;
        } else {
            // Rotta alternativa non selezionata: Viola/Grigio semitrasparente
            renderer.strokeColor = [UIColor colorWithRed:0.45 green:0.35 blue:0.85 alpha:0.75];
            renderer.lineWidth = 5.5;
        }
        return renderer;
    }
    return nil;
}

@end

#import "NavigationViewController.h"
#import "SearchViewController.h"
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

@interface NavigationViewController () <SearchViewControllerDelegate, NetworkGPSReceiverDelegate, RouteSelectorViewDelegate, QuickPOIShelfViewDelegate>

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

// Controlli Flottanti (FAB)
@property (nonatomic, strong) UIButton *topSearchPill;
@property (nonatomic, strong) UIButton *view3DButton;
@property (nonatomic, strong) UIButton *recenterButton;
@property (nonatomic, strong) UIButton *trafficButton;
@property (nonatomic, strong) UIButton *themeButton;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UILabel *gpsSourceLabel;

// Stato 3D / 2D e Navigazione
@property (nonatomic, assign) BOOL is3DMode;
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

    // 2. Mappa Nativa con MapKit e supporto 3D
    self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    [self.view addSubview:self.mapView];

    // Modalità 3D attiva di default (visuale prospettica auto)
    self.is3DMode = YES;

    // 3. Sovrapponi layer OpenStreetMap base
    self.osmOverlay = [[OSMTileOverlay alloc] initWithTheme:OSMMapThemeStandard];
    [self.mapView addOverlay:self.osmOverlay level:MKOverlayLevelAboveLabels];

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

    // 6. Ricevitore GPS di rete (UDP 8888) per tethering da Android
    [NetworkGPSReceiver sharedReceiver].delegate = self;
    [[NetworkGPSReceiver sharedReceiver] startListeningOnPort:8888];

    self.poiAnnotations = [NSMutableArray array];

    // 7. Costruisci l'interfaccia grafica moderna in stile Google Maps / Waze
    [self setupModernUI];

    // Messaggio vocale di avvio
    [[VoiceGuidanceService sharedService] speak:@"Navigatore pronto con visuale 3D prospettica."];
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
    [self.topSearchPill setTitle:@"  🔍 Cerca destinazione o indirizzo..." forState:UIControlStateNormal];
    [self.topSearchPill setTitleColor:[UIColor colorWithWhite:0.9 alpha:1.0] forState:UIControlStateNormal];
    self.topSearchPill.titleLabel.font = [UIFont systemFontOfSize:15.0];
    self.topSearchPill.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.topSearchPill.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    [self.topSearchPill addTarget:self action:@selector(openSearch) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.topSearchPill];

    // 2. Barra POI Rapida a Pillole (Benzina, Parcheggi, Bar, Farmacie)
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
    self.gpsSourceLabel.text = @"GPS: In attesa di segnale...";
    [self.view addSubview:self.gpsSourceLabel];

    // 7. Pulsanti Flottanti (FAB) Circolari in basso a destra
    CGFloat btnY = h - 68;
    CGFloat btnSpacing = 58;

    // Centra
    self.recenterButton = [self createCircularButtonWithTitle:@"🎯" frame:CGRectMake(w - 68, btnY, 50, 50)];
    [self.recenterButton addTarget:self action:@selector(recenterMap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.recenterButton];

    // Switch 3D / 2D
    self.view3DButton = [self createCircularButtonWithTitle:@"2D" frame:CGRectMake(w - 68 - btnSpacing, btnY, 50, 50)];
    [self.view3DButton setTitleColor:[UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    self.view3DButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [self.view3DButton addTarget:self action:@selector(toggle3DMode) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.view3DButton];

    // Toggle Traffico
    self.trafficButton = [self createCircularButtonWithTitle:@"🚦" frame:CGRectMake(w - 68 - (btnSpacing * 2), btnY, 50, 50)];
    [self.trafficButton addTarget:self action:@selector(toggleTraffic) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.trafficButton];

    // Toggle Notte / Giorno
    self.themeButton = [self createCircularButtonWithTitle:@"🌙" frame:CGRectMake(w - 68 - (btnSpacing * 3), btnY, 50, 50)];
    [self.themeButton addTarget:self action:@selector(toggleMapTheme) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.themeButton];

    // Toggle Mute Audio
    self.muteButton = [self createCircularButtonWithTitle:@"🔊" frame:CGRectMake(w - 68 - (btnSpacing * 4), btnY, 50, 50)];
    [self.muteButton addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.muteButton];

    // 8. Selettore Itinerari Multipli in basso
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
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:searchVC];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
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
    self.tripBar.hidden = YES;
    self.maneuverHUD.hidden = YES;

    // Ripristina barra di ricerca e POI in alto
    self.topSearchPill.hidden = NO;
    self.poiShelf.hidden = NO;

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

    [self applyCameraPerspectiveAnimated:YES];
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
        startCoord = CLLocationCoordinate2DMake(45.4642, 9.1900);
    }

    [[VoiceGuidanceService sharedService] speak:@"Ricerca itinerari alternativi e traffico..."];

    __weak NavigationViewController *weakSelf = self;
    [[RoutingService sharedService] calculateRoutesFrom:startCoord to:coordinate destinationTitle:title completion:^(NSArray<RouteInfo *> *routes, NSError *error) {
        if (error || routes.count == 0) {
            [[VoiceGuidanceService sharedService] speak:@"Nessun itinerario trovato."];
            return;
        }

        if (weakSelf.availableRoutes) {
            for (RouteInfo *oldR in weakSelf.availableRoutes) {
                if (oldR.polyline) [weakSelf.mapView removeOverlay:oldR.polyline];
            }
        }

        weakSelf.availableRoutes = routes;
        weakSelf.currentRoute = routes[0];
        weakSelf.currentStepIndex = 0;

        for (RouteInfo *r in routes) {
            if (r.polyline) {
                [weakSelf.mapView addOverlay:r.polyline level:MKOverlayLevelAboveRoads];
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

        NSString *msg = [NSString stringWithFormat:@"Trovati %lu percorsi. Seleziona l'itinerario desiderato.", (unsigned long)routes.count];
        [[VoiceGuidanceService sharedService] speak:msg];
    }];
}

#pragma mark - RouteSelectorViewDelegate

- (void)routeSelectorView:(RouteSelectorView *)view didSelectRouteIndex:(NSUInteger)index {
    if (index >= self.availableRoutes.count) return;

    self.currentRoute = self.availableRoutes[index];
    self.currentStepIndex = 0;

    for (RouteInfo *r in self.availableRoutes) {
        if (r.polyline) {
            [self.mapView removeOverlay:r.polyline];
            [self.mapView addOverlay:r.polyline level:MKOverlayLevelAboveRoads];
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

    // Mostra HUD di guida in stile Waze e Google Maps
    self.maneuverHUD.hidden = NO;
    self.tripBar.hidden = NO;

    if (self.currentRoute.steps.count > 0) {
        ManeuverStep *step1 = self.currentRoute.steps[0];
        ManeuverStep *step2 = (self.currentRoute.steps.count > 1) ? self.currentRoute.steps[1] : nil;
        [self.maneuverHUD updateWithManeuver:step1 distanceToStep:step1.distance nextStep:step2];
    }
    [self.tripBar updateRemainingDistance:self.currentRoute.totalDistance
                                 duration:self.currentRoute.totalDuration
                            trafficStatus:self.currentRoute.trafficDescription];

    [self applyCameraPerspectiveAnimated:YES];

    NSString *prompt = [NSString stringWithFormat:@"Inizia a guidare verso %@.", self.currentRoute.destinationTitle];
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

    NSString *msg = [NSString stringWithFormat:@"Trovati %lu %@ nelle vicinanze.", (unsigned long)annotations.count, category];
    [[VoiceGuidanceService sharedService] speak:msg];
}

- (void)quickPOIShelfViewDidRequestClose:(QuickPOIShelfView *)shelf {
    // Opzionale
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) {
        return nil;
    }

    static NSString *poiId = @"POIAnnotation";
    MKPinAnnotationView *pin = (MKPinAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:poiId];
    if (!pin) {
        pin = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:poiId];
        pin.canShowCallout = YES;
        if ([pin respondsToSelector:@selector(setPinTintColor:)]) {
            pin.pinTintColor = [UIColor colorWithRed:0.0 green:0.55 blue:0.95 alpha:1.0];
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

    // In modalità 3D e durante la navigazione, la telecamera segue dinamicamente l'auto
    if (self.is3DMode && self.isNavigating) {
        [self applyCameraPerspectiveAnimated:YES];
    }

    if (!self.isNavigating || !self.currentRoute) {
        return;
    }

    // Avanzamento manovre
    if (self.currentStepIndex < self.currentRoute.steps.count) {
        ManeuverStep *targetStep = self.currentRoute.steps[self.currentStepIndex];
        CLLocation *stepLoc = [[CLLocation alloc] initWithLatitude:targetStep.coordinate.latitude
                                                         longitude:targetStep.coordinate.longitude];
        CLLocationDistance dist = [location distanceFromLocation:stepLoc];

        ManeuverStep *nextStep = (self.currentStepIndex + 1 < self.currentRoute.steps.count) ? self.currentRoute.steps[self.currentStepIndex + 1] : nil;
        [self.maneuverHUD updateWithManeuver:targetStep distanceToStep:dist nextStep:nextStep];
        [self.tripBar updateRemainingDistance:self.currentRoute.totalDistance duration:self.currentRoute.totalDuration trafficStatus:self.currentRoute.trafficDescription];

        [[VoiceGuidanceService sharedService] speakManeuver:targetStep.instruction distanceInMeters:dist];

        if (dist < 35.0 && self.currentStepIndex + 1 < self.currentRoute.steps.count) {
            self.currentStepIndex++;
            ManeuverStep *newStep = self.currentRoute.steps[self.currentStepIndex];
            ManeuverStep *stepAfter = (self.currentStepIndex + 1 < self.currentRoute.steps.count) ? self.currentRoute.steps[self.currentStepIndex + 1] : nil;
            [self.maneuverHUD updateWithManeuver:newStep distanceToStep:newStep.distance nextStep:stepAfter];
            [[VoiceGuidanceService sharedService] speak:newStep.instruction];
            self.offRouteConsecutiveCount = 0;
        } else if (dist < 25.0 && self.currentStepIndex + 1 >= self.currentRoute.steps.count) {
            [[VoiceGuidanceService sharedService] speak:@"Sei arrivato a destinazione."];
            [self cancelCurrentRoute];
            return;
        }

        // Controllo Fuori Rotta
        if (dist > 75.0 && self.currentStepIndex > 0) {
            self.offRouteConsecutiveCount++;
            if (self.offRouteConsecutiveCount >= 4) {
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
            ManeuverStep *step1 = newRoute.steps[0];
            ManeuverStep *step2 = (newRoute.steps.count > 1) ? newRoute.steps[1] : nil;
            [weakSelf.maneuverHUD updateWithManeuver:step1 distanceToStep:step1.distance nextStep:step2];
        }
        [weakSelf.tripBar updateRemainingDistance:newRoute.totalDistance duration:newRoute.totalDuration trafficStatus:newRoute.trafficDescription];

        [[VoiceGuidanceService sharedService] speak:@"Nuovo percorso pronto. Continua a guidare."];
    }];
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
            // Percorso attivo in blu brillante (#007AFF)
            renderer.strokeColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:0.92];
            renderer.lineWidth = 7.5;
        } else {
            // Alternative in viola (#5856D6)
            renderer.strokeColor = [UIColor colorWithRed:0.45 green:0.35 blue:0.85 alpha:0.75];
            renderer.lineWidth = 5.5;
        }
        return renderer;
    }
    return nil;
}

@end

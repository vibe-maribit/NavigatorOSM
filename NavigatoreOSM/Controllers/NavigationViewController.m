#import "NavigationViewController.h"
#import "SearchViewController.h"
#import "../Overlays/OSMTileOverlay.h"
#import "../Services/RoutingService.h"
#import "../Services/VoiceGuidanceService.h"
#import "../Services/NetworkGPSReceiver.h"
#import "../Views/SpeedometerView.h"
#import "../Views/ManeuverHUDView.h"

@interface NavigationViewController () <SearchViewControllerDelegate, NetworkGPSReceiverDelegate>

@property (nonatomic, strong) OSMTileOverlay *osmOverlay;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *currentLocation;
@property (nonatomic, assign) CLLocationDirection currentHeading;

// UI HUD
@property (nonatomic, strong) ManeuverHUDView *maneuverHUD;
@property (nonatomic, strong) SpeedometerView *speedometer;
@property (nonatomic, strong) UIButton *searchButton;
@property (nonatomic, strong) UIButton *recenterButton;
@property (nonatomic, strong) UIButton *themeButton;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UIButton *cancelRouteButton;
@property (nonatomic, strong) UILabel *gpsSourceLabel;

// Stato Navigazione
@property (nonatomic, strong) RouteInfo *currentRoute;
@property (nonatomic, assign) NSUInteger currentStepIndex;
@property (nonatomic, assign) BOOL isNavigating;
@property (nonatomic, assign) BOOL isFollowingUser;

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

    // 3. Sovrapponi il layer OpenStreetMap
    self.osmOverlay = [[OSMTileOverlay alloc] initWithTheme:OSMMapThemeStandard];
    [self.mapView addOverlay:self.osmOverlay level:MKOverlayLevelAboveLabels];

    // 4. Configura GPS Nativo (Apple CoreLocation)
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

    // 5. Avvia anche il ricevitore GPS di rete (UDP 8888) per tethering da Android
    [NetworkGPSReceiver sharedReceiver].delegate = self;
    [[NetworkGPSReceiver sharedReceiver] startListeningOnPort:8888];

    // 6. Costruisci i componenti di interfaccia (HUD Auto)
    [self setupUIControls];

    // Messaggio di benvenuto vocale
    [[VoiceGuidanceService sharedService] speak:@"Navigatore pronto. In attesa di destinazione."];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

#pragma mark - Setup UI

- (void)setupUIControls {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    // Scheda Manovre in alto a sinistra
    self.maneuverHUD = [[ManeuverHUDView alloc] initWithFrame:CGRectMake(20, 20, 360, 105)];
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

    // Etichetta stato sorgente GPS
    self.gpsSourceLabel = [[UILabel alloc] initWithFrame:CGRectMake(125, h - 35, 200, 20)];
    self.gpsSourceLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.gpsSourceLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.gpsSourceLabel.textColor = [UIColor colorWithWhite:0.2 alpha:0.8];
    self.gpsSourceLabel.text = @"GPS: In ricerca...";
    [self.view addSubview:self.gpsSourceLabel];

    // Pulsante Cerca in alto a destra
    self.searchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.searchButton.frame = CGRectMake(w - 140, 20, 120, 48);
    self.searchButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.searchButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.5 blue:1.0 alpha:0.92];
    self.searchButton.layer.cornerRadius = 14.0;
    self.searchButton.layer.shadowColor = [[UIColor blackColor] CGColor];
    self.searchButton.layer.shadowOpacity = 0.4;
    self.searchButton.layer.shadowRadius = 6.0;
    self.searchButton.layer.shadowOffset = CGSizeMake(0, 3);
    [self.searchButton setTitle:@"🔍 Cerca" forState:UIControlStateNormal];
    [self.searchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.searchButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [self.searchButton addTarget:self action:@selector(openSearch) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.searchButton];

    // Pulsante Annulla Percorso (nascosto di base)
    self.cancelRouteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.cancelRouteButton.frame = CGRectMake(w - 180, 78, 160, 42);
    self.cancelRouteButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.cancelRouteButton.backgroundColor = [UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:0.9];
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

    // 1. Centra e Ruota
    self.recenterButton = [self createCircularButtonWithTitle:@"🎯" frame:CGRectMake(w - 68, btnY, 48, 48)];
    [self.recenterButton addTarget:self action:@selector(recenterMap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.recenterButton];

    // 2. Toggle Tema Notte/Giorno
    self.themeButton = [self createCircularButtonWithTitle:@"🌙" frame:CGRectMake(w - 68 - btnSpacing, btnY, 48, 48)];
    [self.themeButton addTarget:self action:@selector(toggleMapTheme) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.themeButton];

    // 3. Toggle Mute Voce
    self.muteButton = [self createCircularButtonWithTitle:@"🔊" frame:CGRectMake(w - 68 - (btnSpacing * 2), btnY, 48, 48)];
    [self.muteButton addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.muteButton];
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

#pragma mark - Azioni Utente

- (void)openSearch {
    SearchViewController *searchVC = [[SearchViewController alloc] init];
    searchVC.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:searchVC];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)recenterMap {
    if (self.currentLocation) {
        [self.mapView setUserTrackingMode:MKUserTrackingModeFollowWithHeading animated:YES];
    }
}

- (void)toggleMapTheme {
    OSMMapTheme next = (self.osmOverlay.theme == OSMMapThemeStandard) ? OSMMapThemeDark : OSMMapThemeStandard;
    [self.osmOverlay switchTheme:next];
    [self.themeButton setTitle:(next == OSMMapThemeDark ? @"☀️" : @"🌙") forState:UIControlStateNormal];

    // Ricarica l'overlay
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
    if (self.currentRoute && self.currentRoute.polyline) {
        [self.mapView removeOverlay:self.currentRoute.polyline];
    }
    self.currentRoute = nil;
    self.cancelRouteButton.hidden = YES;
    [self.maneuverHUD reset];
    [[VoiceGuidanceService sharedService] speak:@"Navigazione interrotta."];
}

- (void)repeatCurrentInstruction {
    if (self.isNavigating && self.currentRoute && self.currentStepIndex < self.currentRoute.steps.count) {
        ManeuverStep *step = self.currentRoute.steps[self.currentStepIndex];
        [[VoiceGuidanceService sharedService] speak:step.instruction];
    }
}

#pragma mark - Gestione Posizione (Nativo + Network)

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

    // Navigazione attiva: controlla la distanza dal prossimo passaggio di manovra
    if (self.currentStepIndex < self.currentRoute.steps.count) {
        ManeuverStep *targetStep = self.currentRoute.steps[self.currentStepIndex];
        CLLocation *stepLoc = [[CLLocation alloc] initWithLatitude:targetStep.coordinate.latitude
                                                         longitude:targetStep.coordinate.longitude];
        CLLocationDistance dist = [location distanceFromLocation:stepLoc];

        [self.maneuverHUD updateWithManeuver:targetStep distanceToStep:dist];

        // Voce guida quando ci si avvicina
        [[VoiceGuidanceService sharedService] speakManeuver:targetStep.instruction distanceInMeters:dist];

        // Se siamo entro 35 metri dal punto di svolta, passa alla manovra successiva
        if (dist < 35.0 && self.currentStepIndex + 1 < self.currentRoute.steps.count) {
            self.currentStepIndex++;
            ManeuverStep *nextStep = self.currentRoute.steps[self.currentStepIndex];
            [self.maneuverHUD updateWithManeuver:nextStep distanceToStep:nextStep.distance];
            [[VoiceGuidanceService sharedService] speak:nextStep.instruction];
        } else if (dist < 25.0 && self.currentStepIndex + 1 >= self.currentRoute.steps.count) {
            // Arrivo a destinazione!
            [[VoiceGuidanceService sharedService] speak:@"Sei arrivato a destinazione."];
            [self cancelCurrentRoute];
        }
    }
}

#pragma mark - SearchViewControllerDelegate

- (void)searchViewControllerDidSelectLocation:(CLLocationCoordinate2D)coordinate title:(NSString *)title {
    CLLocationCoordinate2D startCoord;
    if (self.currentLocation) {
        startCoord = self.currentLocation.coordinate;
    } else {
        // Posizione di default se il GPS non ha ancora fatto il fix (es. centro Milano)
        startCoord = CLLocationCoordinate2DMake(45.4642, 9.1900);
    }

    [[VoiceGuidanceService sharedService] speak:@"Calcolo del percorso in corso..."];

    __weak NavigationViewController *weakSelf = self;
    [[RoutingService sharedService] calculateRouteFrom:startCoord to:coordinate destinationTitle:title completion:^(RouteInfo *route, NSError *error) {
        if (error || !route) {
            [[VoiceGuidanceService sharedService] speak:@"Impossibile calcolare il percorso. Riprova."];
            return;
        }

        // Rimuovi eventuale vecchio percorso
        if (weakSelf.currentRoute && weakSelf.currentRoute.polyline) {
            [weakSelf.mapView removeOverlay:weakSelf.currentRoute.polyline];
        }

        weakSelf.currentRoute = route;
        weakSelf.currentStepIndex = 0;
        weakSelf.isNavigating = YES;
        weakSelf.cancelRouteButton.hidden = NO;

        // Disegna il percorso blu su OpenStreetMap
        [weakSelf.mapView addOverlay:route.polyline level:MKOverlayLevelAboveRoads];

        // Inquadra l'intero tragitto inizialmente
        [weakSelf.mapView setVisibleMapRect:route.polyline.boundingMapRect edgePadding:UIEdgeInsetsMake(120, 60, 60, 60) animated:YES];

        // Aggiorna HUD
        if (route.steps.count > 0) {
            [weakSelf.maneuverHUD updateWithManeuver:route.steps[0] distanceToStep:route.steps[0].distance];
        }
        [weakSelf.maneuverHUD updateTripRemainingDistance:route.totalDistance duration:route.totalDuration];

        // Istruzione vocale di partenza
        NSString *startMsg = [NSString stringWithFormat:@"Percorso calcolato. Destinazione %@. Inizia a guidare.", title];
        [[VoiceGuidanceService sharedService] speak:startMsg];
    }];
}

#pragma mark - MKMapViewDelegate

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    // 1. Render nativo dei tasselli OpenStreetMap
    if ([overlay isKindOfClass:[MKTileOverlay class]]) {
        return [[MKTileOverlayRenderer alloc] initWithTileOverlay:(MKTileOverlay *)overlay];
    }
    // 2. Render nativo del tracciato del percorso blu
    if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        renderer.strokeColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:0.88];
        renderer.lineWidth = 7.0;
        renderer.lineCap = kCGLineCapRound;
        renderer.lineJoin = kCGLineJoinRound;
        return renderer;
    }
    return nil;
}

@end

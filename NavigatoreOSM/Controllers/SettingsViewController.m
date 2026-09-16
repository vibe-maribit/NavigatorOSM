#import "SettingsViewController.h"
#import "Services/NetworkGPSReceiver.h"
#import "Services/VoiceGuidanceService.h"
#import "Services/LocalizationManager.h"

@interface SettingsViewController () <UITextFieldDelegate>

@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) UISegmentedControl *languageSegment;
@property (nonatomic, strong) UITextField *portTextField;
@property (nonatomic, strong) UITextField *ipTextField;
@property (nonatomic, strong) UISegmentedControl *modeSegment;
@property (nonatomic, strong) UISwitch *voiceSwitch;
@property (nonatomic, strong) UISegmentedControl *themeSegment;

// Riferimenti diretti ai label diagnostici (aggiornati senza reloadSections!)
@property (nonatomic, weak) UILabel *diagStatusLabel;
@property (nonatomic, weak) UILabel *diagLocationLabel;

@end

@implementation SettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self updateNavigationTitles];

    // Stile scuro per la tabella
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.22 alpha:1.0];

    // Chiudi tastiera al tocco
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:tap];
}

- (void)updateNavigationTitles {
    self.navigationItem.title = NLString(@"SETTINGS_TITLE", @"⚙️ Impostazioni");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:NLString(@"CLOSE", @"✕ Chiudi")
                style:UIBarButtonItemStyleDone
               target:self
               action:@selector(handleClose)];
    self.navigationItem.rightBarButtonItem.tintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Timer per aggiornare SOLO i label diagnostici via assegnazione diretta
    // MAI chiamare reloadSections qui — causa il freeze su iOS 9!
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                        target:self
                                                      selector:@selector(refreshDiagnosticLabels)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

#pragma mark - Aggiornamento Diagnostica (SENZA reloadSections!)

- (void)refreshDiagnosticLabels {
    // Aggiornamento diretto dei label — NESSUN reload della tabella!
    NetworkGPSReceiver *gps = [NetworkGPSReceiver sharedReceiver];

    if (self.diagStatusLabel) {
        NSString *ipLocal = [gps localIPAddress];
        NSString *status;
        if (gps.isRunning) {
            status = gps.isTCPClientMode ? NLString(@"CONNECTED_TCP", @"Connesso TCP") : NLString(@"LISTENING_UDP", @"In ascolto UDP");
        } else {
            status = NLString(@"STOPPED", @"Fermo");
        }
        self.diagStatusLabel.text = [NSString stringWithFormat:@"IP iPad: %@ • %@ • Pkt: %lu", ipLocal, status, (unsigned long)gps.packetsReceivedCount];
        self.diagStatusLabel.textColor = gps.packetsReceivedCount > 0
            ? [UIColor colorWithRed:0.3 green:0.85 blue:0.4 alpha:1.0]
            : [UIColor colorWithRed:1.0 green:0.7 blue:0.2 alpha:1.0];
    }

    if (self.diagLocationLabel) {
        if (gps.lastLocation) {
            self.diagLocationLabel.text = [NSString stringWithFormat:@"%.4f, %.4f (±%.0fm)",
                gps.lastLocation.coordinate.latitude,
                gps.lastLocation.coordinate.longitude,
                gps.lastLocation.horizontalAccuracy];
            self.diagLocationLabel.textColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.4 alpha:1.0];
        } else {
            self.diagLocationLabel.text = NLString(@"NO_PACKETS", @"Nessun pacchetto ricevuto");
            self.diagLocationLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        }
    }
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)handleClose {
    [self.view endEditing:YES];

    NetworkGPSReceiver *gps = [NetworkGPSReceiver sharedReceiver];

    NSInteger port = [self.portTextField.text integerValue];
    if (port > 0) {
        gps.port = port;
    }

    NSString *ip = [self.ipTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (ip.length > 0) {
        gps.tcpHost = ip;
    }

    if (self.modeSegment) {
        gps.isTCPClientMode = (self.modeSegment.selectedSegmentIndex == 1);
    }

    if (self.themeSegment) {
        [[NSUserDefaults standardUserDefaults] setInteger:self.themeSegment.selectedSegmentIndex forKey:@"MapThemeIndex"];
    }
    if (self.voiceSwitch) {
        [VoiceGuidanceService sharedService].isMuted = !self.voiceSwitch.isOn;
    }

    [gps saveSettings];
    [gps startWithSavedSettings];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if ([self.delegate respondsToSelector:@selector(settingsViewControllerDidUpdateSettings:)]) {
        [self.delegate settingsViewControllerDidUpdateSettings:self];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyLanguageChange:(UISegmentedControl *)sender {
    NSString *pref = @"auto";
    if (sender.selectedSegmentIndex == 1) {
        pref = @"en";
    } else if (sender.selectedSegmentIndex == 2) {
        pref = @"it";
    }

    [[LocalizationManager sharedManager] setSelectedLanguagePreference:pref];
    [self updateNavigationTitles];
    [self.tableView reloadData];
}

- (void)applyGPSModeChange:(UISegmentedControl *)sender {
    NetworkGPSReceiver *gps = [NetworkGPSReceiver sharedReceiver];
    gps.isTCPClientMode = (sender.selectedSegmentIndex == 1);
    NSInteger port = [self.portTextField.text integerValue] ?: gps.port;
    NSString *host = self.ipTextField.text.length > 0 ? self.ipTextField.text : gps.tcpHost;

    if (gps.isTCPClientMode) {
        [gps connectToTCPServer:host port:port];
    } else {
        [gps startListeningOnPort:port];
    }
}

- (void)copyCydiaRepoURL {
    [UIPasteboard generalPasteboard].string = @"https://vibe-maribit.github.io/NavigatorOSM/";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NLString(@"COPIED_TITLE", @"Copiato!")
                                                                   message:NLString(@"COPIED_CYDIA_MSG", @"L'indirizzo del repository Cydia è stato copiato negli appunti.\n\nOra apri Cydia > Sorgenti > Modifica > Aggiungi e incolla l'URL.")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 7; // 0: Versione, 1: Lingua, 2: GPS, 3: Cydia, 4: Voce, 5: Mappa, 6: Chiudi
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 3; // Versione App, Data Build, Architettura
        case 1: return 1; // Lingua Interfaccia
        case 2: return 5; // Ricevitore GPS di Rete
        case 3: return 2; // Repository Cydia OTA
        case 4: return 1; // Guida Vocale
        case 5: return 1; // Stile Mappa
        case 6: return 1; // Pulsante Salva ed Esci
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return NLString(@"SEC_VERSION", @"ℹ️ VERSIONE SOFTWARE & SISTEMA");
        case 1: return NLString(@"SEC_LANGUAGE", @"🌐 LINGUA APPLICAZIONE");
        case 2: return NLString(@"SEC_GPS", @"🛰️ RICEVITORE GPS DI RETE (DA SMARTPHONE ANDROID)");
        case 3: return NLString(@"SEC_CYDIA", @"📲 AGGIORNAMENTI AUTOMATICI ONLINE (CYDIA OTA)");
        case 4: return NLString(@"SEC_VOICE", @"🔊 GUIDA VOCALE");
        case 5: return NLString(@"SEC_MAP", @"🗺️ MAPPE & ASPETTO");
        case 6: return nil;
        default: return @"";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = [NSString stringWithFormat:@"Cell_%ld_%ld", (long)indexPath.section, (long)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15.0];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14.0];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    NetworkGPSReceiver *gps = [NetworkGPSReceiver sharedReceiver];

    // SEZIONE 0: Versione Software
    if (indexPath.section == 0) {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        NSString *versionStr = info[@"CFBundleShortVersionString"] ?: @"1.3.2";
        NSString *buildStr = info[@"CFBundleVersion"] ?: @"20260916.4";

        if (indexPath.row == 0) {
            cell.textLabel.text = NLString(@"APP_VERSION", @"Versione Applicazione");
            cell.detailTextLabel.text = [NSString stringWithFormat:@"v%@ (Build %@)", versionStr, buildStr];
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:1.0];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = NLString(@"BUILD_DATE", @"Data di Compilazione");
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%s %s", __DATE__, __TIME__];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = NLString(@"PLATFORM", @"Piattaforma");
            cell.detailTextLabel.text = @"armv7 (32-bit) • iPad Mini 1 (iPad2,5) • iOS 9.3.5";
        }
    }
    // SEZIONE 1: Lingua Interfaccia
    else if (indexPath.section == 1) {
        cell.textLabel.text = NLString(@"INTERFACE_LANG", @"Lingua Interfaccia");
        if (!self.languageSegment) {
            self.languageSegment = [[UISegmentedControl alloc] initWithItems:@[
                NLString(@"LANG_AUTO", @"Auto"),
                @"English",
                @"Italiano"
            ]];
            NSString *pref = [[LocalizationManager sharedManager] selectedLanguagePreference];
            if ([pref isEqualToString:@"en"]) {
                self.languageSegment.selectedSegmentIndex = 1;
            } else if ([pref isEqualToString:@"it"]) {
                self.languageSegment.selectedSegmentIndex = 2;
            } else {
                self.languageSegment.selectedSegmentIndex = 0;
            }
            [self.languageSegment addTarget:self action:@selector(applyLanguageChange:) forControlEvents:UIControlEventValueChanged];
            self.languageSegment.tintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
        }
        cell.accessoryView = self.languageSegment;
    }
    // SEZIONE 2: GPS Rete
    else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = NLString(@"PROTOCOL", @"Protocollo Ricezione");
            if (!self.modeSegment) {
                self.modeSegment = [[UISegmentedControl alloc] initWithItems:@[@"UDP Broadcast", @"TCP Client"]];
                self.modeSegment.selectedSegmentIndex = gps.isTCPClientMode ? 1 : 0;
                [self.modeSegment addTarget:self action:@selector(applyGPSModeChange:) forControlEvents:UIControlEventValueChanged];
                self.modeSegment.tintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
            }
            cell.accessoryView = self.modeSegment;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = NLString(@"PORT", @"Porta Ricezione (Default 8888)");
            if (!self.portTextField) {
                self.portTextField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 90, 32)];
                self.portTextField.text = [NSString stringWithFormat:@"%ld", (long)gps.port];
                self.portTextField.textColor = [UIColor whiteColor];
                self.portTextField.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
                self.portTextField.keyboardType = UIKeyboardTypeNumberPad;
                self.portTextField.textAlignment = NSTextAlignmentCenter;
                self.portTextField.layer.cornerRadius = 6.0;
            }
            cell.accessoryView = self.portTextField;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = NLString(@"SERVER_IP", @"IP Server Android (per TCP)");
            if (!self.ipTextField) {
                self.ipTextField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 130, 32)];
                self.ipTextField.text = gps.tcpHost ?: @"192.168.43.1";
                self.ipTextField.textColor = [UIColor whiteColor];
                self.ipTextField.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
                self.ipTextField.textAlignment = NSTextAlignmentCenter;
                self.ipTextField.layer.cornerRadius = 6.0;
            }
            cell.accessoryView = self.ipTextField;
        } else if (indexPath.row == 3) {
            // Box Diagnostica Live
            cell.textLabel.text = NLString(@"DIAGNOSTICS", @"Diagnostica Ricezione");
            NSString *ipLocal = [gps localIPAddress];
            NSString *status;
            if (gps.isRunning) {
                status = gps.isTCPClientMode ? NLString(@"CONNECTED_TCP", @"Connesso TCP") : NLString(@"LISTENING_UDP", @"In ascolto UDP");
            } else {
                status = NLString(@"STOPPED", @"Fermo");
            }
            NSString *diag = [NSString stringWithFormat:@"IP iPad: %@ • %@ • Pkt: %lu", ipLocal, status, (unsigned long)gps.packetsReceivedCount];
            cell.detailTextLabel.text = diag;
            cell.detailTextLabel.textColor = gps.packetsReceivedCount > 0
                ? [UIColor colorWithRed:0.3 green:0.85 blue:0.4 alpha:1.0]
                : [UIColor colorWithRed:1.0 green:0.7 blue:0.2 alpha:1.0];
            self.diagStatusLabel = cell.detailTextLabel;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = NLString(@"LAST_LOCATION", @"Ultima Posizione Ricevuta");
            if (gps.lastLocation) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%.4f, %.4f (±%.0fm)",
                                             gps.lastLocation.coordinate.latitude,
                                             gps.lastLocation.coordinate.longitude,
                                             gps.lastLocation.horizontalAccuracy];
                cell.detailTextLabel.textColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.4 alpha:1.0];
            } else {
                cell.detailTextLabel.text = NLString(@"NO_PACKETS", @"Nessun pacchetto ricevuto");
                cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
            }
            self.diagLocationLabel = cell.detailTextLabel;
        }
    }
    // SEZIONE 3: Cydia Repo OTA
    else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = NLString(@"CYDIA_SOURCE", @"Sorgente Cydia");
            cell.detailTextLabel.text = @"https://vibe-maribit.github.io/NavigatorOSM/";
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0];
            cell.selectionStyle = UITableViewCellSelectionStyleGray;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = NLString(@"OTA_INSTRUCTIONS", @"Istruzioni OTA:");
            cell.detailTextLabel.text = NLString(@"OTA_STEPS", @"Apri Cydia > Sorgenti > Modifica > Aggiungi");
            cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        }
    }
    // SEZIONE 4: Guida Vocale
    else if (indexPath.section == 4) {
        cell.textLabel.text = NLString(@"VOICE_SWITCH", @"Attiva Istruzioni Vocali");
        if (!self.voiceSwitch) {
            self.voiceSwitch = [[UISwitch alloc] init];
            self.voiceSwitch.on = ![VoiceGuidanceService sharedService].isMuted;
            self.voiceSwitch.onTintColor = [UIColor colorWithRed:0.15 green:0.75 blue:0.35 alpha:1.0];
        }
        cell.accessoryView = self.voiceSwitch;
    }
    // SEZIONE 5: Stile Mappa
    else if (indexPath.section == 5) {
        cell.textLabel.text = NLString(@"MAP_STYLE", @"Stile Mappa");
        if (!self.themeSegment) {
            self.themeSegment = [[UISegmentedControl alloc] initWithItems:@[
                NLString(@"MAP_DAY", @"Giorno"),
                NLString(@"MAP_NIGHT", @"Notte"),
                NLString(@"MAP_SAT", @"Satellite")
            ]];
            self.themeSegment.selectedSegmentIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"MapThemeIndex"];
            self.themeSegment.tintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
        }
        cell.accessoryView = self.themeSegment;
    }
    // SEZIONE 6: Pulsante Salva ed Esci (footer)
    else if (indexPath.section == 6) {
        cell.textLabel.text = NLString(@"SAVE_EXIT", @"💾 Salva ed Esci");
        cell.textLabel.textColor = [UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:1.0];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:17.0];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3 && indexPath.row == 0) {
        [self copyCydiaRepoURL];
    }
    if (indexPath.section == 6 && indexPath.row == 0) {
        [self handleClose];
    }
}

@end

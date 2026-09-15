#import "SettingsViewController.h"
#import "Services/NetworkGPSReceiver.h"
#import "Services/VoiceGuidanceService.h"

@interface SettingsViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) UITextField *portTextField;
@property (nonatomic, strong) UITextField *ipTextField;
@property (nonatomic, strong) UISegmentedControl *modeSegment;
@property (nonatomic, strong) UISwitch *voiceSwitch;
@property (nonatomic, strong) UISegmentedControl *themeSegment;

@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Impostazioni";
    self.view.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];

    // Barra superiore con titolo e pulsante Chiudi
    UIView *topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 64)];
    topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    topBar.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
    [self.view addSubview:topBar];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 14, 300, 36)];
    titleLabel.text = @"⚙️ Impostazioni";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:20.0];
    [topBar addSubview:titleLabel];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(topBar.bounds.size.width - 100, 12, 88, 40);
    closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    closeBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
    closeBtn.layer.cornerRadius = 10.0;
    [closeBtn setTitle:@"✕ Chiudi" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    [closeBtn addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:closeBtn];

    // TableView raggruppata
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 64, self.view.bounds.size.width, self.view.bounds.size.height - 64) style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    // Chiudi tastiera al tocco
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:tap];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Timer per aggiornare la diagnostica live ogni secondo
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refreshDiagnostics) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)refreshDiagnostics {
    // Ricarica la sezione diagnostica (sezione 0)
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)handleClose {
    [self.view endEditing:YES];

    // Salva impostazioni porta
    NSInteger port = [self.portTextField.text integerValue];
    if (port > 0) {
        [NetworkGPSReceiver sharedReceiver].port = port;
        [[NSUserDefaults standardUserDefaults] setInteger:port forKey:@"GPS_Port"];
    }

    NSString *ip = self.ipTextField.text;
    if (ip.length > 0) {
        [NetworkGPSReceiver sharedReceiver].tcpHost = ip;
        [[NSUserDefaults standardUserDefaults] setObject:ip forKey:@"GPS_TCP_Host"];
    }

    [[NSUserDefaults standardUserDefaults] synchronize];

    if ([self.delegate respondsToSelector:@selector(settingsViewControllerDidUpdateSettings:)]) {
        [self.delegate settingsViewControllerDidUpdateSettings:self];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyGPSModeChange:(UISegmentedControl *)sender {
    BOOL isTCP = (sender.selectedSegmentIndex == 1);
    NSInteger port = [self.portTextField.text integerValue] ?: 8888;
    NSString *host = self.ipTextField.text.length > 0 ? self.ipTextField.text : @"192.168.43.1";

    if (isTCP) {
        [[NetworkGPSReceiver sharedReceiver] connectToTCPServer:host port:port];
    } else {
        [[NetworkGPSReceiver sharedReceiver] startListeningOnPort:port];
    }
    [self.tableView reloadData];
}

- (void)copyCydiaRepoURL {
    [UIPasteboard generalPasteboard].string = @"https://vibe-maribit.github.io/NavigatorOSM/";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Copiato!"
                                                                   message:@"L'indirizzo del repository Cydia è stato copiato negli appunti.\n\nOra apri Cydia > Sorgenti > Modifica > Aggiungi e incolla l'URL."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 5; // Ricevitore GPS di Rete (Modalità, Porta, IP Host, Box Diagnostica, Pulsante Applica)
        case 1: return 2; // Repository Cydia OTA (URL Repo + Pulsante Copia, Istruzioni)
        case 2: return 1; // Guida Vocale
        case 3: return 1; // Stile Mappa
        case 4: return 4; // Info Versione SW & Sistema
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"🛰️ RICEVITORE GPS DI RETE (DA SMARTPHONE ANDROID)";
        case 1: return @"📲 AGGIORNAMENTI AUTOMATICI ONLINE (CYDIA OTA)";
        case 2: return @"🔊 GUIDA VOCALE";
        case 3: return @"🗺️ MAPPE & ASPETTO";
        case 4: return @"ℹ️ INFORMAZIONI SOFTWARE & SISTEMA";
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

    // SEZIONE 0: GPS Rete
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Protocollo Ricezione";
            if (!self.modeSegment) {
                self.modeSegment = [[UISegmentedControl alloc] initWithItems:@[@"UDP Broadcast", @"TCP Client"]];
                self.modeSegment.selectedSegmentIndex = gps.isTCPClientMode ? 1 : 0;
                [self.modeSegment addTarget:self action:@selector(applyGPSModeChange:) forControlEvents:UIControlEventValueChanged];
                self.modeSegment.tintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
            }
            cell.accessoryView = self.modeSegment;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Porta Ricezione (Default 8888)";
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
            cell.textLabel.text = @"IP Server Android (per TCP)";
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
            cell.textLabel.text = @"Diagnostica Ricezione";
            NSString *ipLocal = [gps localIPAddress];
            NSString *status = gps.isRunning ? (gps.isTCPClientMode ? @"Connesso TCP" : @"In ascolto UDP") : @"Fermo";
            NSString *diag = [NSString stringWithFormat:@"IP iPad: %@ • %@ • Pkt: %lu", ipLocal, status, (unsigned long)gps.packetsReceivedCount];
            cell.detailTextLabel.text = diag;
            cell.detailTextLabel.textColor = gps.packetsReceivedCount > 0 ? [UIColor colorWithRed:0.3 green:0.85 blue:0.4 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.7 blue:0.2 alpha:1.0];
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"Ultima Posizione Ricevuta";
            if (gps.lastLocation) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%.4f, %.4f (±%.0fm)",
                                             gps.lastLocation.coordinate.latitude,
                                             gps.lastLocation.coordinate.longitude,
                                             gps.lastLocation.horizontalAccuracy];
                cell.detailTextLabel.textColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.4 alpha:1.0];
            } else {
                cell.detailTextLabel.text = @"Nessun pacchetto ricevuto";
                cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
            }
        }
    }
    // SEZIONE 1: Cydia Repo OTA
    else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Sorgente Cydia";
            cell.detailTextLabel.text = @"https://vibe-maribit.github.io/NavigatorOSM/";
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0];
            cell.selectionStyle = UITableViewCellSelectionStyleGray;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Istruzioni OTA:";
            cell.detailTextLabel.text = @"Apri Cydia > Sorgenti > Modifica > Aggiungi";
            cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        }
    }
    // SEZIONE 2: Guida Vocale
    else if (indexPath.section == 2) {
        cell.textLabel.text = @"Attiva Istruzioni Vocali";
        if (!self.voiceSwitch) {
            self.voiceSwitch = [[UISwitch alloc] init];
            self.voiceSwitch.on = YES;
            self.voiceSwitch.onTintColor = [UIColor colorWithRed:0.15 green:0.75 blue:0.35 alpha:1.0];
        }
        cell.accessoryView = self.voiceSwitch;
    }
    // SEZIONE 3: Stile Mappa
    else if (indexPath.section == 3) {
        cell.textLabel.text = @"Tema Mappa";
        if (!self.themeSegment) {
            self.themeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Standard", @"Dark", @"Ciclo"]];
            self.themeSegment.selectedSegmentIndex = 0;
            self.themeSegment.tintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
        }
        cell.accessoryView = self.themeSegment;
    }
    // SEZIONE 4: Info Versione SW & Sistema
    else if (indexPath.section == 4) {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        NSString *versionStr = info[@"CFBundleShortVersionString"] ?: @"1.1.0";
        NSString *buildStr = info[@"CFBundleVersion"] ?: @"20260915.2";

        if (indexPath.row == 0) {
            cell.textLabel.text = @"Versione Applicazione";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"v%@ (Build %@)", versionStr, buildStr];
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:1.0];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Data di Compilazione";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%s %s", __DATE__, __TIME__];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Piattaforma & Architettura";
            cell.detailTextLabel.text = @"armv7 (32-bit) • iPad Mini 1 (iPad2,5)";
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Sistema Operativo Supportato";
            cell.detailTextLabel.text = @"iOS 9.3.5 (Build 13G36)";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 0) {
        [self copyCydiaRepoURL];
    }
}

@end

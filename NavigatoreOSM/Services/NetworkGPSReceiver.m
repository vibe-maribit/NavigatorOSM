#import "NetworkGPSReceiver.h"
#import <sys/socket.h>
#import <sys/sysctl.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <ifaddrs.h>
#import <net/if.h>

#if !defined(RTF_GATEWAY)
#define RTF_GATEWAY 0x2
#endif

@interface NetworkGPSReceiver () {
    int _udpSocketFd;
    dispatch_source_t _udpReadSource;

    int _tcpSocketFd;
    BOOL _tcpShouldRun;
    dispatch_queue_t _tcpQueue;

    // Cache per fusione e correzione NMEA
    double _lastValidSpeed;
    double _lastValidCourse;
    NSTimeInterval _lastValidSpeedTimestamp;

    CLLocation *_lastDispatchedLocation;
    NSTimeInterval _lastDispatchTime;
}

@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) NSUInteger packetsReceivedCount;
@property (nonatomic, strong) NSDate *lastPacketTimestamp;
@property (nonatomic, copy) NSString *lastSenderIP;
@property (nonatomic, copy) NSString *lastStreamType;
@property (nonatomic, strong) CLLocation *lastLocation;

@end

@implementation NetworkGPSReceiver

+ (instancetype)sharedReceiver {
    static NetworkGPSReceiver *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[NetworkGPSReceiver alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSInteger savedPort = [defaults integerForKey:@"GPS_Port"];
        _port = (savedPort > 0) ? savedPort : 8888;

        NSString *savedHost = [defaults stringForKey:@"GPS_TCP_Host"];
        if (savedHost && savedHost.length > 0) {
            _tcpHost = [savedHost copy];
        } else {
            // Rileva automaticamente il gateway della rete Wi-Fi (es. 192.168.43.1)
            NSString *gw = [NetworkGPSReceiver defaultGatewayIP];
            _tcpHost = (gw && gw.length > 0) ? [gw copy] : @"192.168.43.1";
        }

        // Di default abilita la ricezione simultanea duale (UDP + TCP)
        if ([defaults objectForKey:@"GPS_IsDualMode"] != nil) {
            _isDualMode = [defaults boolForKey:@"GPS_IsDualMode"];
        } else {
            _isDualMode = YES;
        }

        _isTCPClientMode = [defaults boolForKey:@"GPS_IsTCPClientMode"];

        _udpSocketFd = -1;
        _tcpSocketFd = -1;
        _tcpShouldRun = NO;
        _tcpQueue = dispatch_queue_create("com.nicola.navigatoreosm.tcp_gps", DISPATCH_QUEUE_SERIAL);

        _lastValidSpeed = -1.0;
        _lastValidCourse = -1.0;
        _lastValidSpeedTimestamp = 0;
        _lastDispatchTime = 0;
        _lastDispatchedLocation = nil;

        _isRunning = NO;
        _packetsReceivedCount = 0;
        _lastSenderIP = @"N/D";
        _lastStreamType = @"N/D";
    }
    return self;
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.port forKey:@"GPS_Port"];
    if (self.tcpHost) {
        [defaults setObject:self.tcpHost forKey:@"GPS_TCP_Host"];
    }
    [defaults setBool:self.isTCPClientMode forKey:@"GPS_IsTCPClientMode"];
    [defaults setBool:self.isDualMode forKey:@"GPS_IsDualMode"];
    [defaults synchronize];
}

- (void)startWithSavedSettings {
    // Se l'host non è configurato o è predefinito, controlla se c'è un gateway rilevato migliore
    if (!self.tcpHost || [self.tcpHost isEqualToString:@"127.0.0.1"]) {
        NSString *gw = [NetworkGPSReceiver defaultGatewayIP];
        if (gw && gw.length > 0) {
            self.tcpHost = gw;
        }
    }

    if (self.isDualMode) {
        [self startDualReceiverOnHost:self.tcpHost port:self.port];
    } else if (self.isTCPClientMode) {
        [self connectToTCPServer:self.tcpHost port:self.port];
    } else {
        [self startListeningOnPort:self.port];
    }
}

#pragma mark - Modalità Duale Simultanea (UDP Broadcast + TCP Client)

- (void)startDualReceiverOnHost:(NSString *)host port:(NSInteger)port {
    [self stopListening];

    self.isDualMode = YES;
    self.port = port;
    if (host && host.length > 0) {
        self.tcpHost = host;
    }
    [self saveSettings];

    // 1. Avvia ricevitore UDP (ascolta sia broadcast che unicast)
    [self startUDPSocketOnPort:port];

    // 2. Avvia client TCP verso il gateway hotspot con auto-reconnect in background
    if (self.tcpHost && self.tcpHost.length > 0) {
        [self startTCPWorkerOnHost:self.tcpHost port:port];
    }

    self.isRunning = YES;
    NSLog(@"[NetworkGPSReceiver] Avviata modalità duale: UDP %ld + TCP %@:%ld", (long)port, self.tcpHost, (long)port);
}

#pragma mark - Gestione Socket UDP

- (void)startListeningOnPort:(NSInteger)port {
    [self stopListening];
    self.isDualMode = NO;
    self.isTCPClientMode = NO;
    self.port = port;
    [self saveSettings];

    [self startUDPSocketOnPort:port];
    self.isRunning = YES;
}

- (void)startUDPSocketOnPort:(NSInteger)port {
    _udpSocketFd = socket(AF_INET, SOCK_DGRAM, 0);
    if (_udpSocketFd < 0) {
        NSLog(@"[NetworkGPSReceiver] Impossibile creare socket UDP");
        return;
    }

    int reuse = 1;
    setsockopt(_udpSocketFd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    int broadcastEnable = 1;
    setsockopt(_udpSocketFd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, sizeof(broadcastEnable));

    struct sockaddr_in serverAddr;
    memset(&serverAddr, 0, sizeof(serverAddr));
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons((uint16_t)port);
    serverAddr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(_udpSocketFd, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
        NSLog(@"[NetworkGPSReceiver] Impossibile effettuare bind UDP sulla porta %ld", (long)port);
        close(_udpSocketFd);
        _udpSocketFd = -1;
        return;
    }

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    _udpReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _udpSocketFd, 0, queue);

    __weak NetworkGPSReceiver *weakSelf = self;
    dispatch_source_set_event_handler(_udpReadSource, ^{
        [weakSelf handleIncomingUDPData];
    });

    dispatch_source_set_cancel_handler(_udpReadSource, ^{
        NetworkGPSReceiver *strongSelf = weakSelf;
        if (strongSelf && strongSelf->_udpSocketFd >= 0) {
            close(strongSelf->_udpSocketFd);
            strongSelf->_udpSocketFd = -1;
        }
    });

    dispatch_resume(_udpReadSource);
    NSLog(@"[NetworkGPSReceiver] In ascolto su UDP %ld (Broadcast & Unicast)", (long)port);
}

- (void)handleIncomingUDPData {
    char buffer[2048];
    struct sockaddr_in clientAddr;
    socklen_t addrLen = sizeof(clientAddr);

    ssize_t bytesRead = recvfrom(_udpSocketFd, buffer, sizeof(buffer) - 1, 0, (struct sockaddr *)&clientAddr, &addrLen);
    if (bytesRead > 0) {
        buffer[bytesRead] = '\0';
        NSString *message = [NSString stringWithUTF8String:buffer];
        if (message) {
            NSString *senderIP = [NSString stringWithUTF8String:inet_ntoa(clientAddr.sin_addr)];
            [self processReceivedPayload:message senderIP:senderIP streamType:@"UDP"];
        }
    }
}

#pragma mark - Gestione Socket TCP Client con Auto-Reconnect

- (void)connectToTCPServer:(NSString *)host port:(NSInteger)port {
    [self stopListening];
    self.isDualMode = NO;
    self.isTCPClientMode = YES;
    self.tcpHost = host;
    self.port = port;
    [self saveSettings];

    [self startTCPWorkerOnHost:host port:port];
    self.isRunning = YES;
}

- (void)startTCPWorkerOnHost:(NSString *)host port:(NSInteger)port {
    _tcpShouldRun = YES;
    NSString *targetHost = [host copy];

    dispatch_async(_tcpQueue, ^{
        while (self->_tcpShouldRun) {
            int sock = socket(AF_INET, SOCK_STREAM, 0);
            if (sock < 0) {
                sleep(3);
                continue;
            }

            struct timeval timeout;
            timeout.tv_sec = 4;
            timeout.tv_usec = 0;
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));

            struct sockaddr_in serverAddr;
            memset(&serverAddr, 0, sizeof(serverAddr));
            serverAddr.sin_family = AF_INET;
            serverAddr.sin_port = htons((uint16_t)port);
            inet_pton(AF_INET, [targetHost UTF8String], &serverAddr.sin_addr);

            NSLog(@"[NetworkGPSReceiver] Connessione TCP a %@:%ld...", targetHost, (long)port);
            if (connect(sock, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
                close(sock);
                // Riprova dopo breve pausa
                for (int i = 0; i < 4 && self->_tcpShouldRun; i++) {
                    sleep(1);
                }
                continue;
            }

            self->_tcpSocketFd = sock;
            NSLog(@"[NetworkGPSReceiver] Connesso con successo al server TCP %@:%ld", targetHost, (long)port);

            char buffer[2048];
            while (self->_tcpShouldRun && self->_tcpSocketFd >= 0) {
                ssize_t bytesRead = recv(self->_tcpSocketFd, buffer, sizeof(buffer) - 1, 0);
                if (bytesRead > 0) {
                    buffer[bytesRead] = '\0';
                    NSString *stream = [NSString stringWithUTF8String:buffer];
                    if (stream) {
                        NSArray *lines = [stream componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                        for (NSString *line in lines) {
                            if (line.length > 0) {
                                [self processReceivedPayload:line senderIP:targetHost streamType:@"TCP"];
                            }
                        }
                    }
                } else if (bytesRead == 0) {
                    // Chiusura da remoto
                    break;
                } else {
                    // Errore o timeout
                    if (errno == EAGAIN || errno == EWOULDBLOCK) {
                        continue; // Normale timeout di lettura, riprova
                    }
                    break;
                }
            }

            if (self->_tcpSocketFd >= 0) {
                close(self->_tcpSocketFd);
                self->_tcpSocketFd = -1;
            }

            if (self->_tcpShouldRun) {
                NSLog(@"[NetworkGPSReceiver] Disconnesso da TCP. Riconnessione tra 3s...");
                sleep(3);
            }
        }
    });
}

- (void)stopListening {
    self.isRunning = NO;
    _tcpShouldRun = NO;

    if (_udpReadSource) {
        dispatch_source_cancel(_udpReadSource);
        _udpReadSource = nil;
    }
    if (_udpSocketFd >= 0) {
        close(_udpSocketFd);
        _udpSocketFd = -1;
    }

    if (_tcpSocketFd >= 0) {
        close(_tcpSocketFd);
        _tcpSocketFd = -1;
    }
}

#pragma mark - Parsing Payload e Fusione Dati (JSON, NMEA e CSV)

- (void)processReceivedPayload:(NSString *)payload senderIP:(NSString *)senderIP streamType:(NSString *)streamType {
    NSString *trimmed = [payload stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;

    CLLocation *parsedLocation = nil;
    CLLocationDirection parsedHeading = -1.0;

    // 1. Parser NMEA-0183 ($GPRMC, $GPGGA, $GNRMC, $GNZDA, ecc.)
    if ([trimmed hasPrefix:@"$"]) {
        parsedLocation = [self parseNMEASentence:trimmed outHeading:&parsedHeading];
    }
    // 2. Parser JSON nativo: {"lat": 45.464, "lon": 9.190, "speed": 13.5, "bearing": 180.0}
    else if ([trimmed hasPrefix:@"{"] && [trimmed hasSuffix:@"}"]) {
        parsedLocation = [self parseJSONPayload:trimmed outHeading:&parsedHeading];
    }
    // 3. Parser CSV: lat,lon,speed_kmh,bearing
    else if ([trimmed rangeOfString:@","].location != NSNotFound) {
        parsedLocation = [self parseCSVPayload:trimmed outHeading:&parsedHeading];
    }

    if (!parsedLocation) return;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    // Filtro di de-duplicazione tra stream TCP e UDP arrivati in parallelo
    if (_lastDispatchedLocation && (now - _lastDispatchTime) < 0.08) {
        CLLocationDistance diff = [parsedLocation distanceFromLocation:_lastDispatchedLocation];
        if (diff < 1.0) {
            // È lo stesso pacchetto ricevuto via entrambi i canali: scartiamo il doppione
            return;
        }
    }

    // Filtro Anti-Spike velocità 0:
    // Se il fix dichiara velocità 0 (o non disponibile), ma la distanza percorsa rispetto al fix precedente
    // indica uno spostamento netto a velocità di crociera, recuperiamo la velocità dal gradiente reale
    double finalSpeed = parsedLocation.speed;
    CLLocationDirection finalHeading = (parsedHeading >= 0) ? parsedHeading : parsedLocation.course;

    if (_lastDispatchedLocation) {
        NSTimeInterval dt = now - _lastDispatchTime;
        if (dt > 0.25 && dt < 2.5) {
            CLLocationDistance dist = [parsedLocation distanceFromLocation:_lastDispatchedLocation];
            double impliedSpeed = dist / dt;

            // Se il GPS ha mandato velocità 0 (bug NMEA o glitch) ma l'auto si è spostata di 15m in 0.5s:
            if (finalSpeed < 0.5 && impliedSpeed > 2.8) {
                finalSpeed = impliedSpeed;
            }
            // Se la direzione non è specificata, deducila dallo spostamento
            if (finalHeading < 0 && dist > 3.0) {
                finalHeading = [self calculateHeadingFrom:_lastDispatchedLocation.coordinate to:parsedLocation.coordinate];
            }
        }
    }

    // Ricostruisci il CLLocation validato
    CLLocation *cleanedLocation = [[CLLocation alloc] initWithCoordinate:parsedLocation.coordinate
                                                                altitude:parsedLocation.altitude
                                                      horizontalAccuracy:parsedLocation.horizontalAccuracy
                                                        verticalAccuracy:parsedLocation.verticalAccuracy
                                                                  course:finalHeading >= 0 ? finalHeading : 0.0
                                                                   speed:finalSpeed
                                                               timestamp:[NSDate date]];

    _lastDispatchedLocation = cleanedLocation;
    _lastDispatchTime = now;

    self.packetsReceivedCount++;
    self.lastPacketTimestamp = [NSDate date];
    self.lastSenderIP = senderIP ?: @"127.0.0.1";
    self.lastStreamType = streamType ?: @"NET";
    self.lastLocation = cleanedLocation;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(networkGPSDidUpdateLocation:heading:)]) {
            [self.delegate networkGPSDidUpdateLocation:cleanedLocation heading:finalHeading];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkGPSDidReceiveUpdateNotification" object:self];
    });
}

- (double)calculateHeadingFrom:(CLLocationCoordinate2D)from to:(CLLocationCoordinate2D)to {
    double lat1 = from.latitude * (M_PI / 180.0);
    double lon1 = from.longitude * (M_PI / 180.0);
    double lat2 = to.latitude * (M_PI / 180.0);
    double lon2 = to.longitude * (M_PI / 180.0);
    double dLon = lon2 - lon1;

    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double brng = atan2(y, x) * (180.0 / M_PI);
    return fmod((brng + 360.0), 360.0);
}

#pragma mark - Parser Specifici

- (CLLocation *)parseJSONPayload:(NSString *)jsonStr outHeading:(CLLocationDirection *)outHeading {
    NSData *data = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![dict isKindOfClass:[NSDictionary class]]) return nil;

    double lat = [dict[@"lat"] doubleValue];
    double lon = [dict[@"lon"] doubleValue];
    double speed = dict[@"speed"] ? [dict[@"speed"] doubleValue] : -1.0;
    double bearing = dict[@"bearing"] ? [dict[@"bearing"] doubleValue] : -1.0;
    double alt = dict[@"alt"] ? [dict[@"alt"] doubleValue] : 0.0;
    double acc = dict[@"acc"] ? [dict[@"acc"] doubleValue] : 3.5;

    if (lat == 0 && lon == 0) return nil;
    if (outHeading) *outHeading = bearing;

    return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                         altitude:alt
                               horizontalAccuracy:acc
                                 verticalAccuracy:acc
                                           course:bearing >= 0 ? bearing : 0.0
                                            speed:speed
                                        timestamp:[NSDate date]];
}

- (CLLocation *)parseCSVPayload:(NSString *)csvStr outHeading:(CLLocationDirection *)outHeading {
    NSArray *parts = [csvStr componentsSeparatedByString:@","];
    if (parts.count < 2) return nil;

    double lat = [parts[0] doubleValue];
    double lon = [parts[1] doubleValue];
    double speed = (parts.count > 2) ? ([parts[2] doubleValue] / 3.6) : -1.0;
    double bearing = (parts.count > 3) ? [parts[3] doubleValue] : -1.0;

    if (lat == 0 && lon == 0) return nil;
    if (outHeading) *outHeading = bearing;

    return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                         altitude:0
                               horizontalAccuracy:4.0
                                 verticalAccuracy:4.0
                                           course:bearing >= 0 ? bearing : 0.0
                                            speed:speed
                                        timestamp:[NSDate date]];
}

static double NmeaCoordToDecimal(NSString *valStr, NSString *direction) {
    if (valStr.length < 4) return 0.0;
    double val = [valStr doubleValue];
    int deg = (int)(val / 100.0);
    double minutes = val - (deg * 100.0);
    double dec = deg + (minutes / 60.0);
    if ([direction isEqualToString:@"S"] || [direction isEqualToString:@"W"]) {
        dec = -dec;
    }
    return dec;
}

- (CLLocation *)parseNMEASentence:(NSString *)sentence outHeading:(CLLocationDirection *)outHeading {
    NSArray *tokens = [sentence componentsSeparatedByString:@","];
    if (tokens.count < 7) return nil;

    NSString *tag = tokens[0];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    // RMC: $GPRMC o $GNRMC (Contiene LAT, LON, VELOCITÀ in nodi e BEARING)
    if ([tag hasSuffix:@"RMC"]) {
        NSString *status = tokens[2];
        if (![status isEqualToString:@"A"]) return nil; // Fix valido solo se status == "A"

        double lat = NmeaCoordToDecimal(tokens[3], tokens[4]);
        double lon = NmeaCoordToDecimal(tokens[5], tokens[6]);
        double speedKnots = (tokens.count > 7 && [tokens[7] length] > 0) ? [tokens[7] doubleValue] : 0.0;
        double speedMs = speedKnots * 0.514444;
        double bearing = (tokens.count > 8 && [tokens[8] length] > 0) ? [tokens[8] doubleValue] : -1.0;

        if (lat == 0 && lon == 0) return nil;

        // Memorizza velocità e bearing validi per arricchire le successive righe GGA
        _lastValidSpeed = speedMs;
        _lastValidSpeedTimestamp = now;
        if (bearing >= 0) {
            _lastValidCourse = bearing;
        }
        if (outHeading) *outHeading = bearing;

        return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                             altitude:0
                                   horizontalAccuracy:3.5
                                     verticalAccuracy:3.5
                                               course:bearing >= 0 ? bearing : 0.0
                                                speed:speedMs
                                            timestamp:[NSDate date]];
    }
    // GGA: $GPGGA o $GNGGA (Contiene LAT, LON, ALTITUDINE, ma NON contiene la velocità!)
    else if ([tag hasSuffix:@"GGA"]) {
        int quality = [tokens[6] intValue];
        if (quality <= 0) return nil;

        double lat = NmeaCoordToDecimal(tokens[2], tokens[3]);
        double lon = NmeaCoordToDecimal(tokens[4], tokens[5]);
        double alt = (tokens.count > 9) ? [tokens[9] doubleValue] : 0.0;

        if (lat == 0 && lon == 0) return nil;

        // CORREZIONE BUG FONDAMENTALE:
        // $GPGGA non contiene la velocità! NON impostare MAI speed: 0.0!
        // Usa l'ultima velocità valida registrata da $GPRMC se recente (< 2.5s), altrimenti imposta -1.0 (sconosciuta).
        double speedMs = -1.0;
        if (_lastValidSpeed >= 0 && (now - _lastValidSpeedTimestamp) < 2.5) {
            speedMs = _lastValidSpeed;
        }

        double bearing = -1.0;
        if (_lastValidCourse >= 0 && (now - _lastValidSpeedTimestamp) < 2.5) {
            bearing = _lastValidCourse;
        }
        if (outHeading) *outHeading = bearing;

        return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                             altitude:alt
                                   horizontalAccuracy:4.0
                                     verticalAccuracy:4.0
                                               course:bearing >= 0 ? bearing : 0.0
                                                speed:speedMs
                                            timestamp:[NSDate date]];
    }

    return nil;
}

#pragma mark - Rilevamento Automatico Gateway IP e IP Locale

+ (NSString *)defaultGatewayIP {
    // 1. Prova a dedurre il gateway dalla subnet Wi-Fi di en0:
    // Negli hotspot Android la subnet è quasi sempre 192.168.43.0/24 e il telefono è 192.168.43.1
    // Negli hotspot iOS è 172.20.10.1
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp = NULL;
    NSString *gateway = nil;

    if (getifaddrs(&interfaces) == 0) {
        temp = interfaces;
        while (temp != NULL) {
            if (temp->ifa_addr && temp->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp->ifa_name];
                if ([name isEqualToString:@"en0"]) { // Wi-Fi su iOS
                    struct sockaddr_in *addr = (struct sockaddr_in *)temp->ifa_addr;
                    struct sockaddr_in *netmask = (struct sockaddr_in *)temp->ifa_netmask;

                    if (addr && netmask) {
                        uint32_t ip = ntohl(addr->sin_addr.s_addr);
                        uint32_t mask = ntohl(netmask->sin_addr.s_addr);
                        // Il gateway predefinito per Android Hotspot o router tipico è (.1)
                        uint32_t gw = (ip & mask) | 1;

                        struct in_addr gwAddr;
                        gwAddr.s_addr = htonl(gw);
                        gateway = [NSString stringWithUTF8String:inet_ntoa(gwAddr)];
                    }
                    break;
                }
            }
            temp = temp->ifa_next;
        }
    }
    if (interfaces) freeifaddrs(interfaces);

    return gateway ?: @"192.168.43.1";
}

- (NSString *)localIPAddress {
    NSString *address = @"Disconnesso";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr && temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([name isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    if (interfaces) freeifaddrs(interfaces);
    return address;
}

- (void)dealloc {
    [self stopListening];
}

@end

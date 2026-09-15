#import "NetworkGPSReceiver.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <ifaddrs.h>

@interface NetworkGPSReceiver () {
    int _socketFd;
    dispatch_source_t _readSource;
}
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) NSUInteger packetsReceivedCount;
@property (nonatomic, strong) NSDate *lastPacketTimestamp;
@property (nonatomic, copy) NSString *lastSenderIP;
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
        _port = 8888;
        _tcpHost = @"192.168.43.1";
        _socketFd = -1;
        _isRunning = NO;
        _isTCPClientMode = NO;
        _packetsReceivedCount = 0;
        _lastSenderIP = @"N/D";
    }
    return self;
}

#pragma mark - Gestione Ricevitore UDP Broadcast

- (void)startListeningOnPort:(NSInteger)port {
    if (self.isRunning) {
        [self stopListening];
    }

    self.isTCPClientMode = NO;
    self.port = port;
    _socketFd = socket(AF_INET, SOCK_DGRAM, 0);
    if (_socketFd < 0) {
        NSLog(@"[NetworkGPSReceiver] Impossibile creare socket UDP");
        return;
    }

    int reuse = 1;
    setsockopt(_socketFd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    // Consenti broadcast
    int broadcastEnable = 1;
    setsockopt(_socketFd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, sizeof(broadcastEnable));

    struct sockaddr_in serverAddr;
    memset(&serverAddr, 0, sizeof(serverAddr));
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons((uint16_t)port);
    serverAddr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(_socketFd, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
        NSLog(@"[NetworkGPSReceiver] Impossibile effettuare bind UDP sulla porta %ld", (long)port);
        close(_socketFd);
        _socketFd = -1;
        return;
    }

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _socketFd, 0, queue);

    __weak NetworkGPSReceiver *weakSelf = self;
    dispatch_source_set_event_handler(_readSource, ^{
        [weakSelf handleIncomingUDPData];
    });

    dispatch_source_set_cancel_handler(_readSource, ^{
        NetworkGPSReceiver *strongSelf = weakSelf;
        if (strongSelf && strongSelf->_socketFd >= 0) {
            close(strongSelf->_socketFd);
            strongSelf->_socketFd = -1;
        }
    });

    dispatch_resume(_readSource);
    self.isRunning = YES;
    NSLog(@"[NetworkGPSReceiver] In ascolto su UDP %ld (Broadcast & Unicast)", (long)port);
}

- (void)handleIncomingUDPData {
    char buffer[2048];
    struct sockaddr_in clientAddr;
    socklen_t addrLen = sizeof(clientAddr);

    ssize_t bytesRead = recvfrom(_socketFd, buffer, sizeof(buffer) - 1, 0, (struct sockaddr *)&clientAddr, &addrLen);
    if (bytesRead > 0) {
        buffer[bytesRead] = '\0';
        NSString *message = [NSString stringWithUTF8String:buffer];
        if (message) {
            NSString *senderIP = [NSString stringWithUTF8String:inet_ntoa(clientAddr.sin_addr)];
            [self processReceivedPayload:message senderIP:senderIP];
        }
    }
}

#pragma mark - Gestione TCP Client

- (void)connectToTCPServer:(NSString *)host port:(NSInteger)port {
    if (self.isRunning) {
        [self stopListening];
    }

    self.isTCPClientMode = YES;
    self.tcpHost = host;
    self.port = port;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) return;

        struct sockaddr_in serverAddr;
        memset(&serverAddr, 0, sizeof(serverAddr));
        serverAddr.sin_family = AF_INET;
        serverAddr.sin_port = htons((uint16_t)port);
        inet_pton(AF_INET, [host UTF8String], &serverAddr.sin_addr);

        NSLog(@"[NetworkGPSReceiver] Tento connessione TCP a %@:%ld...", host, (long)port);
        if (connect(sock, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
            NSLog(@"[NetworkGPSReceiver] Connessione TCP fallita a %@:%ld", host, (long)port);
            close(sock);
            return;
        }

        self->_socketFd = sock;
        self.isRunning = YES;
        NSLog(@"[NetworkGPSReceiver] Connesso con successo al server TCP %@:%ld", host, (long)port);

        char buffer[2048];
        while (self.isRunning && self->_socketFd >= 0) {
            ssize_t bytesRead = recv(self->_socketFd, buffer, sizeof(buffer) - 1, 0);
            if (bytesRead <= 0) {
                NSLog(@"[NetworkGPSReceiver] Connessione TCP chiusa dal server");
                break;
            }
            buffer[bytesRead] = '\0';
            NSString *stream = [NSString stringWithUTF8String:buffer];
            if (stream) {
                // Possono arrivare più righe separate da newline
                NSArray *lines = [stream componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                for (NSString *line in lines) {
                    if (line.length > 0) {
                        [self processReceivedPayload:line senderIP:host];
                    }
                }
            }
        }

        [self stopListening];
    });
}

- (void)stopListening {
    self.isRunning = NO;
    if (_readSource) {
        dispatch_source_cancel(_readSource);
        _readSource = nil;
    }
    if (_socketFd >= 0) {
        close(_socketFd);
        _socketFd = -1;
    }
}

#pragma mark - Parsing Payload (JSON, NMEA-0183 e CSV)

- (void)processReceivedPayload:(NSString *)payload senderIP:(NSString *)senderIP {
    NSString *trimmed = [payload stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;

    CLLocation *parsedLocation = nil;
    CLLocationDirection parsedHeading = 0.0;

    // 1. Parser NMEA-0183 ($GPRMC o $GPGGA)
    if ([trimmed hasPrefix:@"$GPRMC"] || [trimmed hasPrefix:@"$GPGGA"] || [trimmed hasPrefix:@"$GNRMC"]) {
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

    if (parsedLocation) {
        self.packetsReceivedCount++;
        self.lastPacketTimestamp = [NSDate date];
        self.lastSenderIP = senderIP ?: @"127.0.0.1";
        self.lastLocation = parsedLocation;

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(networkGPSDidUpdateLocation:heading:)]) {
                [self.delegate networkGPSDidUpdateLocation:parsedLocation heading:parsedHeading];
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkGPSDidReceiveUpdateNotification" object:self];
        });
    }
}

- (CLLocation *)parseJSONPayload:(NSString *)jsonStr outHeading:(CLLocationDirection *)outHeading {
    NSData *data = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![dict isKindOfClass:[NSDictionary class]]) return nil;

    double lat = [dict[@"lat"] doubleValue];
    double lon = [dict[@"lon"] doubleValue];
    double speed = [dict[@"speed"] doubleValue]; // m/s
    double bearing = [dict[@"bearing"] doubleValue];
    double alt = [dict[@"alt"] doubleValue];
    double acc = dict[@"acc"] ? [dict[@"acc"] doubleValue] : 4.0;

    if (lat == 0 && lon == 0) return nil;
    if (outHeading) *outHeading = bearing;

    return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                         altitude:alt
                               horizontalAccuracy:acc
                                 verticalAccuracy:acc
                                           course:bearing
                                            speed:speed
                                        timestamp:[NSDate date]];
}

- (CLLocation *)parseCSVPayload:(NSString *)csvStr outHeading:(CLLocationDirection *)outHeading {
    NSArray *parts = [csvStr componentsSeparatedByString:@","];
    if (parts.count < 2) return nil;

    double lat = [parts[0] doubleValue];
    double lon = [parts[1] doubleValue];
    double speed = (parts.count > 2) ? ([parts[2] doubleValue] / 3.6) : 0.0;
    double bearing = (parts.count > 3) ? [parts[3] doubleValue] : 0.0;

    if (lat == 0 && lon == 0) return nil;
    if (outHeading) *outHeading = bearing;

    return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                         altitude:0
                               horizontalAccuracy:5.0
                                 verticalAccuracy:5.0
                                           course:bearing
                                            speed:speed
                                        timestamp:[NSDate date]];
}

// Converte stringa NMEA DDMM.MMMM in gradi decimali
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
    if ([tag hasSuffix:@"RMC"]) {
        // $GPRMC,hhmmss,status(A/V),lat,NS,lon,EW,speed(knots),track,date,...
        NSString *status = tokens[2];
        if (![status isEqualToString:@"A"]) return nil; // Fix non valido

        double lat = NmeaCoordToDecimal(tokens[3], tokens[4]);
        double lon = NmeaCoordToDecimal(tokens[5], tokens[6]);
        double speedKnots = (tokens.count > 7) ? [tokens[7] doubleValue] : 0.0;
        double speedMs = speedKnots * 0.514444;
        double bearing = (tokens.count > 8) ? [tokens[8] doubleValue] : 0.0;

        if (lat == 0 && lon == 0) return nil;
        if (outHeading) *outHeading = bearing;

        return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                             altitude:0
                                   horizontalAccuracy:4.0
                                     verticalAccuracy:4.0
                                               course:bearing
                                                speed:speedMs
                                            timestamp:[NSDate date]];
    } else if ([tag hasSuffix:@"GGA"]) {
        // $GPGGA,hhmmss,lat,NS,lon,EW,quality,numSV,HDOP,alt,M,...
        int quality = [tokens[6] intValue];
        if (quality <= 0) return nil;

        double lat = NmeaCoordToDecimal(tokens[2], tokens[3]);
        double lon = NmeaCoordToDecimal(tokens[4], tokens[5]);
        double alt = (tokens.count > 9) ? [tokens[9] doubleValue] : 0.0;

        if (lat == 0 && lon == 0) return nil;
        if (outHeading) *outHeading = 0.0;

        return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                             altitude:alt
                                   horizontalAccuracy:5.0
                                     verticalAccuracy:5.0
                                               course:0.0
                                                speed:0.0
                                            timestamp:[NSDate date]];
    }
    return nil;
}

#pragma mark - Lettura IP Locale iPad (Wi-Fi en0)

- (NSString *)localIPAddress {
    NSString *address = @"Disconnesso";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                // en0 è l'interfaccia standard Wi-Fi su iOS
                if ([name isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

- (void)dealloc {
    [self stopListening];
}

@end

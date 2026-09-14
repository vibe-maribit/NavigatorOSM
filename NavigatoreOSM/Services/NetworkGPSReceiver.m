#import "NetworkGPSReceiver.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>

@interface NetworkGPSReceiver () {
    int _socketFd;
    dispatch_source_t _readSource;
}
@property (nonatomic, assign) BOOL isRunning;
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
        _socketFd = -1;
        _isRunning = NO;
    }
    return self;
}

- (void)startListeningOnPort:(NSInteger)port {
    if (self.isRunning) {
        [self stopListening];
    }

    self.port = port;
    _socketFd = socket(AF_INET, SOCK_DGRAM, 0);
    if (_socketFd < 0) {
        NSLog(@"[NetworkGPSReceiver] Impossibile creare socket UDP");
        return;
    }

    int reuse = 1;
    setsockopt(_socketFd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in serverAddr;
    memset(&serverAddr, 0, sizeof(serverAddr));
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons((uint16_t)port);
    serverAddr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(_socketFd, (struct sockaddr *)&serverAddr, sizeof(serverAddr)) < 0) {
        NSLog(@"[NetworkGPSReceiver] Impossibile effettuare il bind sulla porta %ld", (long)port);
        close(_socketFd);
        _socketFd = -1;
        return;
    }

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _socketFd, 0, queue);

    __weak NetworkGPSReceiver *weakSelf = self;
    dispatch_source_set_event_handler(_readSource, ^{
        [weakSelf handleIncomingData];
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
    NSLog(@"[NetworkGPSReceiver] In ascolto su porta UDP %ld per coordinate esterne", (long)port);
}

- (void)stopListening {
    if (_readSource) {
        dispatch_source_cancel(_readSource);
        _readSource = nil;
    }
    self.isRunning = NO;
}

- (void)handleIncomingData {
    char buffer[2048];
    struct sockaddr_in clientAddr;
    socklen_t addrLen = sizeof(clientAddr);

    ssize_t bytesRead = recvfrom(_socketFd, buffer, sizeof(buffer) - 1, 0, (struct sockaddr *)&clientAddr, &addrLen);
    if (bytesRead > 0) {
        buffer[bytesRead] = '\0';
        NSString *message = [NSString stringWithUTF8String:buffer];
        if (message) {
            [self parsePayload:message];
        }
    }
}

- (void)parsePayload:(NSString *)payload {
    NSString *trimmed = [payload stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;

    // 1. Prova formato JSON: {"lat": 45.464, "lon": 9.190, "speed": 13.5, "bearing": 180.0}
    if ([trimmed hasPrefix:@"{"] && [trimmed hasSuffix:@"}"]) {
        NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (!error && [dict isKindOfClass:[NSDictionary class]]) {
            double lat = [dict[@"lat"] doubleValue];
            double lon = [dict[@"lon"] doubleValue];
            double speed = [dict[@"speed"] doubleValue]; // m/s
            double bearing = [dict[@"bearing"] doubleValue];

            CLLocation *loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                                            altitude:0
                                                  horizontalAccuracy:5.0
                                                    verticalAccuracy:5.0
                                                              course:bearing
                                                               speed:speed
                                                           timestamp:[NSDate date]];

            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(networkGPSDidUpdateLocation:heading:)]) {
                    [self.delegate networkGPSDidUpdateLocation:loc heading:bearing];
                }
            });
            return;
        }
    }

    // 2. Prova formato CSV semplice: lat,lon,speed_kmh,bearing
    NSArray *parts = [trimmed componentsSeparatedByString:@","];
    if (parts.count >= 2) {
        double lat = [parts[0] doubleValue];
        double lon = [parts[1] doubleValue];
        double speed = (parts.count > 2) ? ([parts[2] doubleValue] / 3.6) : 0;
        double bearing = (parts.count > 3) ? [parts[3] doubleValue] : 0;

        if (lat != 0 && lon != 0) {
            CLLocation *loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                                            altitude:0
                                                  horizontalAccuracy:5.0
                                                    verticalAccuracy:5.0
                                                              course:bearing
                                                               speed:speed
                                                           timestamp:[NSDate date]];

            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(networkGPSDidUpdateLocation:heading:)]) {
                    [self.delegate networkGPSDidUpdateLocation:loc heading:bearing];
                }
            });
        }
    }
}

- (void)dealloc {
    [self stopListening];
}

@end

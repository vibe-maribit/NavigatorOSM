#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@protocol NetworkGPSReceiverDelegate <NSObject>
- (void)networkGPSDidUpdateLocation:(CLLocation *)location heading:(CLLocationDirection)heading;
@end

@interface NetworkGPSReceiver : NSObject

@property (nonatomic, weak) id<NetworkGPSReceiverDelegate> delegate;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, copy) NSString *tcpHost;
@property (nonatomic, assign) BOOL isTCPClientMode;

// Statistiche e diagnostica in tempo reale
@property (nonatomic, assign, readonly) NSUInteger packetsReceivedCount;
@property (nonatomic, strong, readonly) NSDate *lastPacketTimestamp;
@property (nonatomic, copy, readonly) NSString *lastSenderIP;
@property (nonatomic, strong, readonly) CLLocation *lastLocation;

+ (instancetype)sharedReceiver;

// Avvia ricevitore UDP (predefinito, in ascolto su broadcast porta 8888)
- (void)startListeningOnPort:(NSInteger)port;

// Avvia connessione TCP Client (verso app hotspot Android su porta 8888)
- (void)connectToTCPServer:(NSString *)host port:(NSInteger)port;

// Ferma ricevitore
- (void)stopListening;

// Restituisce l'IP locale dell'iPad (es. interfaccia en0 Wi-Fi)
- (NSString *)localIPAddress;

@end

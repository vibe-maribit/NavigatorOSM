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
@property (nonatomic, assign) BOOL isDualMode; // Ricezione simultanea UDP + TCP (predefinita)

// Statistiche e diagnostica in tempo reale
@property (nonatomic, assign, readonly) NSUInteger packetsReceivedCount;
@property (nonatomic, strong, readonly) NSDate *lastPacketTimestamp;
@property (nonatomic, copy, readonly) NSString *lastSenderIP;
@property (nonatomic, copy, readonly) NSString *lastStreamType; // "UDP", "TCP"
@property (nonatomic, strong, readonly) CLLocation *lastLocation;

+ (instancetype)sharedReceiver;

// Avvia con le impostazioni persistenti memorizzate
- (void)startWithSavedSettings;
- (void)saveSettings;

// Avvia ricezione contemporanea Duale (UDP broadcast + TCP client auto-reconnecting)
- (void)startDualReceiverOnHost:(NSString *)host port:(NSInteger)port;

// Avvia solo ricevitore UDP (in ascolto su broadcast porta specificata)
- (void)startListeningOnPort:(NSInteger)port;

// Avvia solo connessione TCP Client (verso host su porta specificata)
- (void)connectToTCPServer:(NSString *)host port:(NSInteger)port;

// Ferma tutti i ricevitori
- (void)stopListening;

// Rileva e restituisce l'IP del gateway predefinito della rete (es. 192.168.43.1 per hotspot Android)
+ (NSString *)defaultGatewayIP;

// Restituisce l'IP locale dell'iPad (es. interfaccia en0 Wi-Fi)
- (NSString *)localIPAddress;

@end

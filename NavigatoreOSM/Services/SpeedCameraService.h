#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

@class RouteInfo;

typedef NS_ENUM(NSInteger, SpeedCameraType) {
    SpeedCameraTypeFixed,        // Autovelox fisso
    SpeedCameraTypeTutor,        // Tutor / Controllo velocità media
    SpeedCameraTypeTrafficLight, // Telecamera semaforica / T-Red
    SpeedCameraTypeMobile        // Postazione mobile frequente
};

@interface SpeedCamera : NSObject <NSSecureCoding>

@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
@property (nonatomic, assign) int speedLimit; // 0 se non specificato
@property (nonatomic, assign) CLLocationDirection direction; // -1 se non direzionale
@property (nonatomic, assign) SpeedCameraType type;
@property (nonatomic, copy) NSString *roadDescription;
@property (nonatomic, copy) NSString *operatorName;
@property (nonatomic, assign) long long osmId;

- (NSString *)typeDescription;
- (NSString *)formattedTitle;
- (NSString *)formattedSubtitle;

@end

@interface SpeedCameraAnnotation : NSObject <MKAnnotation>

@property (nonatomic, strong, readonly) SpeedCamera *camera;
@property (nonatomic, assign, readonly) CLLocationCoordinate2D coordinate;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *subtitle;

- (instancetype)initWithCamera:(SpeedCamera *)camera;

@end

@interface SpeedCameraService : NSObject

@property (nonatomic, strong, readonly) NSArray<SpeedCamera *> *cachedCameras;
@property (nonatomic, strong, readonly) NSDate *lastFetchDate;

+ (instancetype)sharedService;

/// Scarica i velox nell'area geografica (con cache su disco 7 giorni)
- (void)fetchCamerasAroundCoordinate:(CLLocationCoordinate2D)coord
                        radiusMeters:(double)radius
                          completion:(void (^)(NSArray<SpeedCamera *> *cameras, NSError *error))completion;

/// Scarica i velox presenti lungo l'itinerario attivo
- (void)fetchCamerasAlongRoute:(RouteInfo *)route
                    completion:(void (^)(NSArray<SpeedCamera *> *cameras, NSError *error))completion;

/// Controlla se c'è un autovelox in avvicinamento rispetto alla posizione e rotta attuale del veicolo.
/// Restituisce la telecamera più vicina entro la soglia (es. 500m/800m) e valorizza outDistance.
- (SpeedCamera *)checkApproachingCameraFromLocation:(CLLocation *)location
                                            heading:(CLLocationDirection)heading
                                        outDistance:(CLLocationDistance *)outDistance;

/// Ritorna la lista di annotazioni pronte per l'aggiunta su MKMapView
- (NSArray<SpeedCameraAnnotation *> *)annotationsForCachedCameras;

@end

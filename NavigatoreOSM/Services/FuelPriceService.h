#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

typedef NS_ENUM(NSInteger, FuelType) {
    FuelTypePetrol = 0,    // Benzina
    FuelTypeDiesel = 1,    // Gasolio / Diesel
    FuelTypeLPG = 2,       // GPL
    FuelTypeElectric = 3   // Elettrico
};

extern NSString *const kFuelPricesUpdatedNotification;

@interface FuelStation : NSObject <NSSecureCoding>

@property (nonatomic, assign) long long stationId;
@property (nonatomic, copy) NSString *brand;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *address;
@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
@property (nonatomic, assign) double petrolPriceSelf;
@property (nonatomic, assign) double petrolPriceServed;
@property (nonatomic, assign) double dieselPriceSelf;
@property (nonatomic, assign) double dieselPriceServed;
@property (nonatomic, assign) double lpgPrice;
@property (nonatomic, assign) double methanePrice;
@property (nonatomic, assign) double distanceFromQuery; // in km
@property (nonatomic, strong) NSDate *lastUpdated;

- (double)effectivePriceForFuelType:(FuelType)type;
- (NSString *)displayTitleForFuelType:(FuelType)type;
- (NSString *)formattedSubtitle;

@end

@interface FuelStationAnnotation : MKPointAnnotation

@property (nonatomic, strong, readonly) FuelStation *station;
@property (nonatomic, assign, readonly) FuelType fuelType;

- (instancetype)initWithStation:(FuelStation *)station fuelType:(FuelType)fuelType;

@end

@interface FuelPriceService : NSObject

+ (instancetype)sharedService;

@property (nonatomic, assign) FuelType selectedFuelType;
@property (nonatomic, strong, readonly) NSArray<FuelStation *> *cachedStations;

/// Restituisce il nome localizzato del tipo di carburante
- (NSString *)nameForFuelType:(FuelType)type;

/// Restituisce l'unità di misura del volume / energia ("L" o "kWh")
- (NSString *)unitForFuelType:(FuelType)type;

/// Restituisce l'unità di consumo ("L/100km" o "kWh/100km")
- (NSString *)consumptionUnitForFuelType:(FuelType)type;

/// Restituisce il consumo predefinito per il tipo di carburante (es. 6.5 L/100km)
- (double)defaultConsumptionForFuelType:(FuelType)type;

/// Restituisce il consumo attualmente attivo (personalizzato dall'utente oppure predefinito)
- (double)effectiveConsumptionForFuelType:(FuelType)type;

/// Imposta un consumo personalizzato per il tipo di carburante (passare <= 0 per ripristinare il predefinito)
- (void)setCustomConsumption:(double)consumption forFuelType:(FuelType)type;

/// Verifica se l'utente ha impostato un consumo personalizzato
- (BOOL)hasCustomConsumptionForFuelType:(FuelType)type;

/// Restituisce il prezzo predefinito offline di fallback (€/L o €/kWh)
- (double)defaultPriceForFuelType:(FuelType)type;

/// Restituisce l'ultimo prezzo medio rilevato online tramite API MIMIT (<= 0 se non disponibile)
- (double)onlinePriceForFuelType:(FuelType)type;

/// Restituisce il prezzo attualmente effettivo (€/L o €/kWh):
/// Se personalizzato dall'utente -> prezzo utente
/// Altrimenti se rilevato online -> prezzo online MIMIT
/// Altrimenti -> prezzo predefinito offline
- (double)effectivePriceForFuelType:(FuelType)type;

/// Imposta un prezzo personalizzato (passare <= 0 per usare il prezzo online / predefinito)
- (void)setCustomPrice:(double)price forFuelType:(FuelType)type;

/// Verifica se l'utente ha impostato un prezzo personalizzato
- (BOOL)hasCustomPriceForFuelType:(FuelType)type;

/// Verifica se il prezzo attualmente utilizzato deriva dalle API online MIMIT
- (BOOL)isUsingOnlinePriceForFuelType:(FuelType)type;

/// Data e ora dell'ultimo aggiornamento prezzi online
- (NSDate *)lastOnlinePriceFetchDate;

/// Avvia il recupero asincrono dei distributori e prezzi nella zona indicata tramite API MIMIT Carburanti (Prezzi Benzina)
- (void)fetchStationsAroundCoordinate:(CLLocationCoordinate2D)coordinate
                             radiusKm:(int)radiusKm
                           completion:(void (^)(NSArray<FuelStation *> *stations, NSError *error))completion;

/// Metodo legacy per aggiornare le medie MIMIT
- (void)fetchOnlinePricesAroundCoordinate:(CLLocationCoordinate2D)coordinate
                               completion:(void (^)(BOOL success, NSString *statusMessage))completion;

/// Calcola la spesa stimata per il carburante per una determinata distanza in metri
- (double)fuelCostForDistance:(CLLocationDistance)distanceMeters;

/// Calcola la spesa stimata per il carburante specificando il tipo
- (double)fuelCostForDistance:(CLLocationDistance)distanceMeters fuelType:(FuelType)type;

/// Calcola la stima del pedaggio autostradale italiano per una distanza in metri (tariffa media ~0.075 €/km)
- (double)estimatedTollCostForDistance:(CLLocationDistance)distanceMeters hasTolls:(BOOL)hasTolls;

/// Stringa formattata riassuntiva dei costi (es. "⛽ 5.40 € • 🛣️ 3.80 € • Tot. 9.20 €")
- (NSString *)formattedCostSummaryForFuelCost:(double)fuelCost tollCost:(double)tollCost;

/// Restituisce annotazioni MKPointAnnotation per i distributori in cache per il tipo carburante selezionato
- (NSArray<FuelStationAnnotation *> *)annotationsForCachedStations;

@end

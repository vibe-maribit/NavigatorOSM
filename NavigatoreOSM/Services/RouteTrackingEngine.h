#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import "RoutingService.h"

@class RouteTrackingEngine;

@protocol RouteTrackingEngineDelegate <NSObject>
@optional
/// Notifica l'avanzamento ad una nuova manovra del percorso
- (void)routeTrackingEngine:(RouteTrackingEngine *)engine
        didAdvanceToStepIndex:(NSUInteger)stepIndex
      remainingDistanceToStep:(CLLocationDistance)distToStep;

/// Notifica l'arrivo alla destinazione finale
- (void)routeTrackingEngineDidArriveAtDestination:(RouteTrackingEngine *)engine;

/// Notifica il rilevamento confermato di fuori rotta (> soglia di tolleranza per letture consecutive in movimento)
- (void)routeTrackingEngineDidDetectOffRoute:(RouteTrackingEngine *)engine
                                  atLocation:(CLLocation *)location;
@end

@interface RouteTrackingEngine : NSObject

@property (nonatomic, weak) id<RouteTrackingEngineDelegate> delegate;

@property (nonatomic, strong, readonly) RouteInfo *activeRoute;
@property (nonatomic, assign, readonly) BOOL hasActiveRoute;

/// Posizione veicolo interpolata a 60/30 FPS (mezzeria esatta della rotta durante la navigazione)
@property (nonatomic, assign, readonly) CLLocationCoordinate2D currentCoordinate;

/// Direzione veicolo interpolata (tangente alla mezzeria stradale, priva di oscillazioni spurie)
@property (nonatomic, assign, readonly) CLLocationDirection currentHeading;

/// Velocità filtrata del veicolo in m/s (usata come gradiente per avanzare lungo il tracciato)
@property (nonatomic, assign, readonly) double smoothedSpeed;

/// Distanza in metri percorsa lungo la polyline dall'inizio del percorso
@property (nonatomic, assign, readonly) double currentRouteDistance;

/// Distanza totale del percorso attivo in metri
@property (nonatomic, assign, readonly) double totalRouteDistance;

/// Indice della manovra (step) attuale
@property (nonatomic, assign, readonly) NSUInteger currentStepIndex;

/// Indice del passaggio stradale su cui si sta attualmente transitando
@property (nonatomic, assign, readonly) NSUInteger currentRoadStepIndex;

/// Distanza stradale rimanente in metri verso la manovra attuale
@property (nonatomic, assign, readonly) CLLocationDistance remainingDistanceToStep;

/// Distanza stradale totale rimanente in metri verso la destinazione
@property (nonatomic, assign, readonly) CLLocationDistance remainingDistanceToDestination;

/// Durata stimata rimanente verso la destinazione in secondi
@property (nonatomic, assign, readonly) NSTimeInterval remainingDuration;

/// YES se l'ultimo fix GPS ha confermato che ci si trova entro il range ragionevole del percorso
@property (nonatomic, assign, readonly) BOOL isConfirmedOnRoute;

/// Distanza perpendicolare dell'ultimo fix GPS dalla mezzeria (metri)
@property (nonatomic, assign, readonly) double lastGPSPerpendicularDistance;

/// Imposta o sostituisce il percorso attivo con la posizione iniziale
- (void)setActiveRoute:(RouteInfo *)route initialLocation:(CLLocation *)location;

/// Rimuove il percorso attivo e reimposta lo stato
- (void)clearActiveRoute;

/// Elabora il fix GPS grezzo (~1 Hz), verifica la tolleranza e riconcilia il progresso senza scatti laterali
- (void)processGPSLocation:(CLLocation *)location heading:(CLLocationDirection)rawHeading;

/// Chiamato dal display loop (CADisplayLink ad es. 30 FPS): avanza lungo la rotta usando il gradiente di velocità
- (void)updateTickWithDeltaTime:(NSTimeInterval)dt;

@end

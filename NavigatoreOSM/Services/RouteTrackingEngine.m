#import "RouteTrackingEngine.h"

typedef struct {
    MKMapPoint startPoint;
    MKMapPoint endPoint;
    double lengthMeters;
    double cumulativeStartMeters;
    double cumulativeEndMeters;
    double bearingDegrees;
    double dx;
    double dy;
    double lenSq;
} RouteSegment;

typedef struct {
    double routeDistanceMeters;
} StepProgress;

static double InterpolateAngle(double current, double target, double factor) {
    if (factor <= 0.0) return current;
    if (factor >= 1.0) return target;
    double diff = target - current;
    while (diff < -180.0) diff += 360.0;
    while (diff > 180.0) diff -= 360.0;
    double result = current + diff * factor;
    while (result < 0.0) result += 360.0;
    while (result >= 360.0) result -= 360.0;
    return result;
}

@interface RouteTrackingEngine () {
    RouteSegment *_segments;
    NSUInteger _segmentCount;

    StepProgress *_stepProgress;
    NSUInteger _stepCount;

    NSUInteger _currentSegmentIndex;
    NSTimeInterval _lastFixTimestamp;
    double _lastFixProjectedProgress;
    NSInteger _offRouteConsecutiveCount;
    NSTimeInterval _firstOffRouteTimestamp;
    NSTimeInterval _lastOffRouteTriggerTimestamp;
}

@property (nonatomic, strong, readwrite) RouteInfo *activeRoute;
@property (nonatomic, assign, readwrite) BOOL hasActiveRoute;
@property (nonatomic, assign, readwrite) CLLocationCoordinate2D currentCoordinate;
@property (nonatomic, assign, readwrite) CLLocationDirection currentHeading;
@property (nonatomic, assign, readwrite) double smoothedSpeed;
@property (nonatomic, assign, readwrite) double currentRouteDistance;
@property (nonatomic, assign, readwrite) double totalRouteDistance;
@property (nonatomic, assign, readwrite) NSUInteger currentStepIndex;
@property (nonatomic, assign, readwrite) NSUInteger currentRoadStepIndex;
@property (nonatomic, assign, readwrite) CLLocationDistance remainingDistanceToStep;
@property (nonatomic, assign, readwrite) CLLocationDistance remainingDistanceToDestination;
@property (nonatomic, assign, readwrite) NSTimeInterval remainingDuration;
@property (nonatomic, assign, readwrite) BOOL isConfirmedOnRoute;
@property (nonatomic, assign, readwrite) double lastGPSPerpendicularDistance;

@end

@implementation RouteTrackingEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _segments = NULL;
        _segmentCount = 0;
        _stepProgress = NULL;
        _stepCount = 0;
        _hasActiveRoute = NO;
        _isConfirmedOnRoute = NO;
        _smoothedSpeed = 0.0;
        _currentRouteDistance = 0.0;
        _totalRouteDistance = 0.0;
        _currentSegmentIndex = 0;
        _currentStepIndex = 0;
        _offRouteConsecutiveCount = 0;
        _lastFixTimestamp = 0;
    }
    return self;
}

- (void)dealloc {
    [self freeBuffers];
}

- (void)freeBuffers {
    if (_segments) {
        free(_segments);
        _segments = NULL;
        _segmentCount = 0;
    }
    if (_stepProgress) {
        free(_stepProgress);
        _stepProgress = NULL;
        _stepCount = 0;
    }
}

- (void)clearActiveRoute {
    [self freeBuffers];
    self.activeRoute = nil;
    self.hasActiveRoute = NO;
    self.isConfirmedOnRoute = NO;
    self.currentRouteDistance = 0.0;
    self.totalRouteDistance = 0.0;
    self.currentStepIndex = 0;
    self.remainingDistanceToStep = 0.0;
    self.remainingDistanceToDestination = 0.0;
    self.remainingDuration = 0;
    _currentSegmentIndex = 0;
    _offRouteConsecutiveCount = 0;
    _firstOffRouteTimestamp = 0;
    _lastOffRouteTriggerTimestamp = 0;
    _lastFixTimestamp = 0;
}

#pragma mark - Inizializzazione & Pre-indicizzazione Percorso

- (void)setActiveRoute:(RouteInfo *)route initialLocation:(CLLocation *)location {
    [self clearActiveRoute];
    if (!route || !route.polyline || route.polyline.pointCount < 2) {
        return;
    }

    self.activeRoute = route;
    self.hasActiveRoute = YES;

    MKPolyline *poly = route.polyline;
    NSUInteger pCount = poly.pointCount;
    MKMapPoint *pts = poly.points;

    _segmentCount = pCount - 1;
    _segments = malloc(sizeof(RouteSegment) * _segmentCount);

    double accumDist = 0.0;
    for (NSUInteger i = 0; i < _segmentCount; i++) {
        MKMapPoint a = pts[i];
        MKMapPoint b = pts[i + 1];
        double dx = b.x - a.x;
        double dy = b.y - a.y;
        double len = MKMetersBetweenMapPoints(a, b);

        double rad = atan2(dx, -dy);
        double deg = rad * (180.0 / M_PI);
        if (deg < 0.0) deg += 360.0;

        _segments[i].startPoint = a;
        _segments[i].endPoint = b;
        _segments[i].dx = dx;
        _segments[i].dy = dy;
        _segments[i].lenSq = dx * dx + dy * dy;
        _segments[i].lengthMeters = len;
        _segments[i].cumulativeStartMeters = accumDist;
        accumDist += len;
        _segments[i].cumulativeEndMeters = accumDist;
        _segments[i].bearingDegrees = deg;
    }
    self.totalRouteDistance = accumDist;

    // Pre-indicizzazione posizioni manovre (steps) lungo la mezzeria del percorso
    if (route.steps.count > 0) {
        _stepCount = route.steps.count;
        _stepProgress = malloc(sizeof(StepProgress) * _stepCount);

        for (NSUInteger s = 0; s < _stepCount; s++) {
            ManeuverStep *step = route.steps[s];
            double perpD = 0, progD = 0;
            NSUInteger sIdx = 0;
            [self projectCoordinateOnAllSegments:step.coordinate
                         outDistanceToPolyline:&perpD
                           outProgressDistance:&progD
                              outSegmentIndex:&sIdx];
            _stepProgress[s].routeDistanceMeters = progD;
        }
        // L'ultimo step corrisponde alla destinazione finale
        _stepProgress[_stepCount - 1].routeDistanceMeters = self.totalRouteDistance;
    }

    // Inizializza posizione iniziale lungo la polyline
    CLLocationCoordinate2D startCoord = location ? location.coordinate : MKCoordinateForMapPoint(pts[0]);
    double initialPerpDist = 0;
    double initialProgDist = 0;
    NSUInteger initialSegIdx = 0;
    [self projectCoordinateOnAllSegments:startCoord
                 outDistanceToPolyline:&initialPerpDist
                   outProgressDistance:&initialProgDist
                      outSegmentIndex:&initialSegIdx];

    self.currentRouteDistance = initialProgDist;
    _currentSegmentIndex = initialSegIdx;

    if (location && location.speed > 0) {
        self.smoothedSpeed = location.speed;
    } else {
        self.smoothedSpeed = 0.0;
    }

    [self updateCoordinatesForCurrentProgress];

    // Trova il primo step non ancora superato
    self.currentStepIndex = 0;
    for (NSUInteger s = 0; s < _stepCount; s++) {
        if (_stepProgress[s].routeDistanceMeters > self.currentRouteDistance + 15.0) {
            self.currentStepIndex = s;
            break;
        }
    }
    [self updateRemainingMetrics];

    self.isConfirmedOnRoute = (initialPerpDist <= 45.0);
    _offRouteConsecutiveCount = 0;
    _lastFixTimestamp = [[NSDate date] timeIntervalSince1970];
    _lastFixProjectedProgress = self.currentRouteDistance;
}

#pragma mark - Proiezione Geometrica su Polyline

- (void)projectCoordinateOnAllSegments:(CLLocationCoordinate2D)coord
                 outDistanceToPolyline:(double *)outPerpDist
                   outProgressDistance:(double *)outProgDist
                      outSegmentIndex:(NSUInteger *)outSegIndex {
    [self projectCoordinate:coord
                fromSegment:0
                  toSegment:_segmentCount > 0 ? _segmentCount - 1 : 0
       outDistanceToPolyline:outPerpDist
         outProgressDistance:outProgDist
            outSegmentIndex:outSegIndex];
}

- (void)projectCoordinate:(CLLocationCoordinate2D)coord
              fromSegment:(NSUInteger)startSeg
                toSegment:(NSUInteger)endSeg
     outDistanceToPolyline:(double *)outPerpDist
       outProgressDistance:(double *)outProgDist
          outSegmentIndex:(NSUInteger *)outSegIndex {

    if (_segmentCount == 0 || !_segments) {
        if (outPerpDist) *outPerpDist = DBL_MAX;
        if (outProgDist) *outProgDist = 0.0;
        if (outSegIndex) *outSegIndex = 0;
        return;
    }

    MKMapPoint P = MKMapPointForCoordinate(coord);
    double minPerpDist = DBL_MAX;
    double bestProgDist = 0.0;
    NSUInteger bestSeg = startSeg;

    endSeg = MIN(endSeg, _segmentCount - 1);

    for (NSUInteger i = startSeg; i <= endSeg; i++) {
        RouteSegment seg = _segments[i];
        MKMapPoint a = seg.startPoint;
        double dx = seg.dx;
        double dy = seg.dy;
        double t = 0.0;

        if (seg.lenSq > 0.0) {
            t = ((P.x - a.x) * dx + (P.y - a.y) * dy) / seg.lenSq;
            if (t < 0.0) t = 0.0;
            else if (t > 1.0) t = 1.0;
        }

        MKMapPoint proj = MKMapPointMake(a.x + t * dx, a.y + t * dy);
        double dist = MKMetersBetweenMapPoints(P, proj);

        if (dist < minPerpDist) {
            minPerpDist = dist;
            bestProgDist = seg.cumulativeStartMeters + (t * seg.lengthMeters);
            bestSeg = i;
        }
    }

    if (outPerpDist) *outPerpDist = minPerpDist;
    if (outProgDist) *outProgDist = bestProgDist;
    if (outSegIndex) *outSegIndex = bestSeg;
}

#pragma mark - Elaborazione Fix GPS Grezzo & Tolleranza (Riconciliazione)

- (void)processGPSLocation:(CLLocation *)location heading:(CLLocationDirection)rawHeading {
    if (!self.hasActiveRoute || !location || (location.coordinate.latitude == 0.0 && location.coordinate.longitude == 0.0)) {
        return;
    }

    // 1. Proiezione del punto GPS sulla mezzeria stradale in una finestra locale
    NSUInteger windowStart = (_currentSegmentIndex > 4) ? (_currentSegmentIndex - 4) : 0;
    NSUInteger windowEnd = MIN(_segmentCount - 1, _currentSegmentIndex + 30);

    double perpDist = 0.0;
    double projectedProgress = 0.0;
    NSUInteger bestSeg = _currentSegmentIndex;

    [self projectCoordinate:location.coordinate
                fromSegment:windowStart
                  toSegment:windowEnd
       outDistanceToPolyline:&perpDist
         outProgressDistance:&projectedProgress
            outSegmentIndex:&bestSeg];

    // Se fuori finestra (es. deviazione improvvisa o shortcut), effettua scansione completa
    if (perpDist > 60.0 && _segmentCount > 35) {
        double fullPerp = 0.0;
        double fullProg = 0.0;
        NSUInteger fullSeg = 0;
        [self projectCoordinateOnAllSegments:location.coordinate
                       outDistanceToPolyline:&fullPerp
                         outProgressDistance:&fullProg
                            outSegmentIndex:&fullSeg];
        if (fullPerp < perpDist) {
            perpDist = fullPerp;
            projectedProgress = fullProg;
            bestSeg = fullSeg;
        }
    }

    self.lastGPSPerpendicularDistance = perpDist;

    // 2. Calcolo della soglia di tolleranza / range ragionevole basato sull'accuratezza GPS
    double accuracy = location.horizontalAccuracy > 0 ? location.horizontalAccuracy : 15.0;
    double reasonableRange = MAX(35.0, accuracy * 1.6);
    reasonableRange = MIN(reasonableRange, 65.0); // Tetto massimo per non accettare strade parallele

    // 3. Filtraggio ed interpolazione della velocità per il gradiente
    if (location.speed >= 0.0) {
        double rawSpeed = location.speed;
        // Filtro esponenziale per rimuovere picchi spuri mantenendo reattività
        self.smoothedSpeed = (self.smoothedSpeed * 0.40) + (rawSpeed * 0.60);
    } else if (_lastFixTimestamp > 0) {
        NSTimeInterval dtFix = [[NSDate date] timeIntervalSince1970] - _lastFixTimestamp;
        if (dtFix > 0.4 && dtFix < 3.0) {
            double derived = fabs(projectedProgress - _lastFixProjectedProgress) / dtFix;
            if (derived < 45.0) { // < 160 km/h
                self.smoothedSpeed = (self.smoothedSpeed * 0.50) + (derived * 0.50);
            }
        }
    }
    if (self.smoothedSpeed < 0.25) {
        self.smoothedSpeed = 0.0; // Auto ferma (semaforo, sosta)
    }

    _lastFixTimestamp = [[NSDate date] timeIntervalSince1970];
    _lastFixProjectedProgress = projectedProgress;

    // 4. Verifica Corrispondenza Itinerario (Map-Matching / Dead Reckoning Reconciliation)
    if (perpDist <= reasonableRange) {
        // CONFERMATO ENTRO IL RANGE RAGIONEVOLE DELLA ROTTA!
        self.isConfirmedOnRoute = YES;
        _offRouteConsecutiveCount = 0;
        _firstOffRouteTimestamp = 0;

        // Regola fondamentale richiesta dall'utente:
        // NON inseguire la posizione laterale segnalata dal GPS che potrebbe essere inesatta!
        // La posizione laterale rimane RIGOROSAMENTE bloccata sulla mezzeria della polyline.
        // Riconcilia solo il progresso longitudinale in avanti/indietro:
        double progressDelta = projectedProgress - self.currentRouteDistance;

        if (self.smoothedSpeed < 0.6) {
            // Se fermi, il rumore del GPS non deve far tremare l'auto avanti e indietro
            if (fabs(progressDelta) > 28.0) {
                self.currentRouteDistance += (progressDelta * 0.20);
            }
        } else {
            // In movimento: correzione graduale per eliminare scatti
            if (fabs(progressDelta) < 35.0) {
                // Piccola differenza ordinaria: nudge del 25%
                self.currentRouteDistance += (progressDelta * 0.25);
            } else if (progressDelta >= 35.0 && progressDelta < 90.0) {
                // Il veicolo ha accelerato più del previsto: catch-up del 50%
                self.currentRouteDistance += (progressDelta * 0.50);
            } else if (progressDelta <= -35.0 && progressDelta > -90.0) {
                // Rallentamento brusco: correzione del 30%
                self.currentRouteDistance += (progressDelta * 0.30);
            } else {
                // Grande scarto (es. salto GPS): allinea
                self.currentRouteDistance = projectedProgress;
            }
        }

        if (self.currentRouteDistance < 0.0) self.currentRouteDistance = 0.0;
        if (self.currentRouteDistance > self.totalRouteDistance) self.currentRouteDistance = self.totalRouteDistance;

    } else {
        // FIX FUORI DAL RANGE RAGIONEVOLE!
        self.isConfirmedOnRoute = NO;

        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (_offRouteConsecutiveCount == 0 || _firstOffRouteTimestamp <= 0) {
            _firstOffRouteTimestamp = now;
        }
        _offRouteConsecutiveCount++;

        // Richiede almeno 6 fix consecutivi E almeno 3.0 secondi di deviazione confermata
        NSTimeInterval timeOffRoute = now - _firstOffRouteTimestamp;
        NSTimeInterval timeSinceLastTrigger = (_lastOffRouteTriggerTimestamp > 0) ? (now - _lastOffRouteTriggerTimestamp) : 999.0;

        if (_offRouteConsecutiveCount >= 6 && timeOffRoute >= 3.0) {
            // Applica debounce minimo di 15 secondi tra notifiche di fuori rotta
            if (timeSinceLastTrigger >= 15.0) {
                _lastOffRouteTriggerTimestamp = now;
                if ([self.delegate respondsToSelector:@selector(routeTrackingEngineDidDetectOffRoute:atLocation:)]) {
                    [self.delegate routeTrackingEngineDidDetectOffRoute:self atLocation:location];
                }
            }
            // Mantieni contatore parzialmente attivo senza azzerarlo a 0 per non ripetere il ciclo
            _offRouteConsecutiveCount = 3;
        }
    }
}

#pragma mark - Display Loop Tick (Avanzamento a 30 FPS con Gradiente di Velocità)

- (void)updateTickWithDeltaTime:(NSTimeInterval)dt {
    if (!self.hasActiveRoute || _segmentCount == 0) {
        return;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval timeSinceLastFix = (_lastFixTimestamp > 0) ? (now - _lastFixTimestamp) : 0;

    // Watchdog anti-freeze e anti-ghost navigation:
    // Se non arrivano fix GPS da più di 1.8 secondi (sosta ad autogrill, galleria o interruzione stream),
    // applica una frenata inerziale progressiva verso lo 0.
    if (timeSinceLastFix > 1.8) {
        if (self.smoothedSpeed > 0.1) {
            self.smoothedSpeed = MAX(0.0, self.smoothedSpeed - (6.0 * dt));
        }
    }
    if (timeSinceLastFix > 3.5) {
        self.smoothedSpeed = 0.0;
    }

    // Se siamo confermati fuori rotta da 2 o più cicli, blocchiamo l'avanzamento sulla vecchia rotta
    if (!self.isConfirmedOnRoute && _offRouteConsecutiveCount >= 2) {
        self.smoothedSpeed = 0.0;
    }

    // 1. Avanzamento continuo lungo la polyline: distanza = velocità * dt
    if (self.smoothedSpeed > 0.05) {
        double distanceStep = self.smoothedSpeed * dt;
        self.currentRouteDistance += distanceStep;
        if (self.currentRouteDistance > self.totalRouteDistance) {
            self.currentRouteDistance = self.totalRouteDistance;
        }
    }

    // 2. Calcolo coordinate e direzione interpolate al millimetro
    [self updateCoordinatesForCurrentProgress];

    // 3. Calcolo avanzamento manovre e countdown
    [self updateRemainingMetrics];

    // 4. Controllo passaggio alla prossima manovra
    if (self.remainingDistanceToStep <= 25.0 && self.currentStepIndex + 1 < _stepCount) {
        self.currentStepIndex++;
        [self updateRemainingMetrics];

        if ([self.delegate respondsToSelector:@selector(routeTrackingEngine:didAdvanceToStepIndex:remainingDistanceToStep:)]) {
            [self.delegate routeTrackingEngine:self
                         didAdvanceToStepIndex:self.currentStepIndex
                       remainingDistanceToStep:self.remainingDistanceToStep];
        }
    } else if (self.remainingDistanceToDestination <= 20.0 && self.currentStepIndex + 1 >= _stepCount) {
        if ([self.delegate respondsToSelector:@selector(routeTrackingEngineDidArriveAtDestination:)]) {
            [self.delegate routeTrackingEngineDidArriveAtDestination:self];
        }
    }
}

- (void)updateCoordinatesForCurrentProgress {
    if (_segmentCount == 0 || !_segments) return;

    // Trova il segmento che include self.currentRouteDistance
    NSUInteger segIdx = _currentSegmentIndex;
    if (self.currentRouteDistance >= _segments[segIdx].cumulativeEndMeters) {
        while (segIdx + 1 < _segmentCount && self.currentRouteDistance >= _segments[segIdx].cumulativeEndMeters) {
            segIdx++;
        }
    } else if (self.currentRouteDistance < _segments[segIdx].cumulativeStartMeters) {
        while (segIdx > 0 && self.currentRouteDistance < _segments[segIdx].cumulativeStartMeters) {
            segIdx--;
        }
    }
    _currentSegmentIndex = segIdx;

    RouteSegment seg = _segments[segIdx];
    double segStart = seg.cumulativeStartMeters;
    double segLen = seg.lengthMeters;
    double u = 0.0;
    if (segLen > 0.0) {
        u = (self.currentRouteDistance - segStart) / segLen;
        if (u < 0.0) u = 0.0;
        else if (u > 1.0) u = 1.0;
    }

    MKMapPoint pt = MKMapPointMake(seg.startPoint.x + (u * seg.dx), seg.startPoint.y + (u * seg.dy));
    self.currentCoordinate = MKCoordinateForMapPoint(pt);

    // Direzione tangente alla mezzeria stradale con rotazione fluida
    double targetBearing = seg.bearingDegrees;
    if (self.smoothedSpeed > 0.20) {
        self.currentHeading = InterpolateAngle(self.currentHeading, targetBearing, 0.18);
    }
}

- (void)updateRemainingMetrics {
    if (_stepCount > self.currentStepIndex && _stepProgress) {
        double stepDist = _stepProgress[self.currentStepIndex].routeDistanceMeters;
        self.remainingDistanceToStep = MAX(0.0, stepDist - self.currentRouteDistance);
    } else {
        self.remainingDistanceToStep = 0.0;
    }

    // Determina su quale segmento stradale (step) ci troviamo attualmente
    if (_stepCount > 0 && _stepProgress) {
        NSUInteger roadIdx = 0;
        for (NSUInteger s = 0; s < _stepCount; s++) {
            if (s + 1 < _stepCount) {
                if (self.currentRouteDistance >= _stepProgress[s].routeDistanceMeters &&
                    self.currentRouteDistance < _stepProgress[s + 1].routeDistanceMeters) {
                    roadIdx = s;
                    break;
                }
            } else {
                roadIdx = s;
            }
        }
        self.currentRoadStepIndex = roadIdx;
    } else {
        self.currentRoadStepIndex = 0;
    }

    self.remainingDistanceToDestination = MAX(0.0, self.totalRouteDistance - self.currentRouteDistance);

    if (self.totalRouteDistance > 0.0 && self.activeRoute.totalDuration > 0.0) {
        self.remainingDuration = self.activeRoute.totalDuration * (self.remainingDistanceToDestination / self.totalRouteDistance);
    } else {
        self.remainingDuration = 0;
    }
}

@end

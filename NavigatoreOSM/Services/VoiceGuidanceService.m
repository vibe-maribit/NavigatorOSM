#import "VoiceGuidanceService.h"
#import "LocalizationManager.h"

@interface VoiceGuidanceService () <AVSpeechSynthesizerDelegate>
@property (nonatomic, strong) AVSpeechSynthesizer *synthesizer;
@property (nonatomic, copy) NSString *lastSpokenPhrase;
@property (nonatomic, strong) NSDate *lastSpokenTime;

// Checkpoint per la manovra attualmente tracciata
@property (nonatomic, assign) NSUInteger trackedStepIndex;
@property (nonatomic, assign) BOOL didSpeak1000m;
@property (nonatomic, assign) BOOL didSpeak500m;
@property (nonatomic, assign) BOOL didSpeak200m;
@property (nonatomic, assign) BOOL didSpeakNow;
@end

@implementation VoiceGuidanceService

+ (instancetype)sharedService {
    static VoiceGuidanceService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VoiceGuidanceService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _synthesizer = [[AVSpeechSynthesizer alloc] init];
        _synthesizer.delegate = self;
        _isMuted = NO;
        _trackedStepIndex = NSNotFound;
    }
    return self;
}

- (void)stopSpeaking {
    if (self.synthesizer.isSpeaking) {
        [self.synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
}

- (void)resetManeuverTracking {
    self.trackedStepIndex = NSNotFound;
    self.didSpeak1000m = NO;
    self.didSpeak500m = NO;
    self.didSpeak200m = NO;
    self.didSpeakNow = NO;
    [self stopSpeaking];
}

- (void)speak:(NSString *)text {
    if (self.isMuted || !text || text.length == 0) return;

    // Throttle globale: evita qualsiasi ripetizione della stessa frase entro 15 secondi
    // e non sovrapporre frasi diverse a meno di 4 secondi l'una dall'altra
    NSDate *now = [NSDate date];
    if (self.lastSpokenTime) {
        NSTimeInterval elapsed = [now timeIntervalSinceDate:self.lastSpokenTime];
        if ([text isEqualToString:self.lastSpokenPhrase] && elapsed < 15.0) {
            return;
        }
        if (elapsed < 3.5 && self.synthesizer.isSpeaking) {
            return;
        }
    }

    [self stopSpeaking];

    self.lastSpokenPhrase = text;
    self.lastSpokenTime = now;

    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    NSString *langCode = [[LocalizationManager sharedManager] speechVoiceLanguage];
    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:langCode];
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95; // Scandita per la guida
    utterance.pitchMultiplier = 1.0;
    utterance.volume = 1.0;

    [self.synthesizer speakUtterance:utterance];
}

- (void)speakManeuver:(NSString *)instruction distanceInMeters:(double)distance stepIndex:(NSUInteger)stepIndex {
    if (self.isMuted || !instruction || instruction.length == 0) return;

    // Se siamo passati a una nuova manovra, resetta i checkpoint per il nuovo step
    if (self.trackedStepIndex != stepIndex) {
        self.trackedStepIndex = stepIndex;
        self.didSpeak1000m = NO;
        self.didSpeak500m = NO;
        self.didSpeak200m = NO;
        self.didSpeakNow = NO;
    }

    // Logica checkpoint rigorosa: ogni avviso viene pronunciato ESATTAMENTE UNA VOLTA per manovra
    if (distance > 750 && distance <= 1200) {
        if (!self.didSpeak1000m) {
            self.didSpeak1000m = YES;
            NSString *fmt = NLString(@"VOICE_1000M", @"Tra circa un chilometro, %@");
            [self speak:[NSString stringWithFormat:fmt, [instruction lowercaseString]]];
        }
    } else if (distance > 350 && distance <= 600) {
        if (!self.didSpeak500m) {
            self.didSpeak500m = YES;
            NSString *fmt = NLString(@"VOICE_500M", @"Tra 500 metri, %@");
            [self speak:[NSString stringWithFormat:fmt, [instruction lowercaseString]]];
        }
    } else if (distance > 100 && distance <= 250) {
        if (!self.didSpeak200m) {
            self.didSpeak200m = YES;
            NSString *fmt = NLString(@"VOICE_200M", @"Tra 200 metri, %@");
            [self speak:[NSString stringWithFormat:fmt, [instruction lowercaseString]]];
        }
    } else if (distance <= 45 && distance > 10) {
        if (!self.didSpeakNow) {
            self.didSpeakNow = YES;
            NSString *fmt = NLString(@"VOICE_NOW", @"Ora, %@");
            [self speak:[NSString stringWithFormat:fmt, [instruction lowercaseString]]];
        }
    }
}

- (void)speakManeuver:(NSString *)instruction distanceInMeters:(double)distance {
    [self speakManeuver:instruction distanceInMeters:distance stepIndex:0];
}

@end

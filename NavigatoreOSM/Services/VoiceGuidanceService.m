#import "VoiceGuidanceService.h"

@interface VoiceGuidanceService () <AVSpeechSynthesizerDelegate>
@property (nonatomic, strong) AVSpeechSynthesizer *synthesizer;
@property (nonatomic, strong) AVSpeechSynthesisVoice *italianVoice;
@property (nonatomic, copy) NSString *lastSpokenPhrase;
@property (nonatomic, strong) NSDate *lastSpokenTime;
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
        _italianVoice = [AVSpeechSynthesisVoice voiceWithLanguage:@"it-IT"];
        _isMuted = NO;
    }
    return self;
}

- (void)stopSpeaking {
    if (self.synthesizer.isSpeaking) {
        [self.synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
}

- (void)speak:(NSString *)text {
    if (self.isMuted || !text || text.length == 0) return;

    // Evita di ripetere la medesima frase negli ultimi 8 secondi
    if ([text isEqualToString:self.lastSpokenPhrase] &&
        self.lastSpokenTime &&
        [[NSDate date] timeIntervalSinceDate:self.lastSpokenTime] < 8.0) {
        return;
    }

    [self stopSpeaking];

    self.lastSpokenPhrase = text;
    self.lastSpokenTime = [NSDate date];

    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    utterance.voice = self.italianVoice;
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95; // Leggermente più scandita per l'auto
    utterance.pitchMultiplier = 1.0;
    utterance.volume = 1.0;

    [self.synthesizer speakUtterance:utterance];
}

- (void)speakManeuver:(NSString *)instruction distanceInMeters:(double)distance {
    if (self.isMuted) return;

    NSString *phrase = nil;
    if (distance > 800) {
        phrase = [NSString stringWithFormat:@"Tra circa un chilometro, %@", [instruction lowercaseString]];
    } else if (distance > 350) {
        phrase = [NSString stringWithFormat:@"Tra 500 metri, %@", [instruction lowercaseString]];
    } else if (distance > 150) {
        phrase = [NSString stringWithFormat:@"Tra 200 metri, %@", [instruction lowercaseString]];
    } else if (distance > 30) {
        phrase = [NSString stringWithFormat:@"Ora %@", [instruction lowercaseString]];
    } else {
        phrase = instruction;
    }

    [self speak:phrase];
}

@end

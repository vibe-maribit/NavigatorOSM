#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, VoiceGuidanceMode) {
    VoiceGuidanceModeAll = 0,        // Completa (Manovre di svolta + Allerte)
    VoiceGuidanceModeAlertsOnly = 1, // Solo Allerte (Autovelox, Limiti, Ricalcolo, Arrivo)
    VoiceGuidanceModeMuted = 2       // Disattivata (Silenzio assoluto)
};

extern NSString *const kVoiceGuidanceModeChangedNotification;
extern NSString *const kPrefVoiceGuidanceMode;

@interface VoiceGuidanceService : NSObject

@property (nonatomic, assign) VoiceGuidanceMode voiceMode;
@property (nonatomic, assign) BOOL isMuted; // Wrapper retro-compatibile: YES se voiceMode == VoiceGuidanceModeMuted

+ (instancetype)sharedService;

- (void)cycleVoiceMode;
- (NSString *)currentModeTitle;
- (NSString *)currentModeIcon;

- (void)speak:(NSString *)text;
- (void)speakAlert:(NSString *)text; // Pronunciato sia in Completa sia in Solo Allerte
- (void)speakManeuver:(NSString *)instruction distanceInMeters:(double)distance stepIndex:(NSUInteger)stepIndex;
- (void)speakManeuver:(NSString *)instruction distanceInMeters:(double)distance;
- (void)resetManeuverTracking;
- (void)stopSpeaking;

@end

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface VoiceGuidanceService : NSObject

@property (nonatomic, assign) BOOL isMuted;

+ (instancetype)sharedService;

- (void)speak:(NSString *)text;
- (void)speakManeuver:(NSString *)instruction distanceInMeters:(double)distance stepIndex:(NSUInteger)stepIndex;
- (void)speakManeuver:(NSString *)instruction distanceInMeters:(double)distance;
- (void)resetManeuverTracking;
- (void)stopSpeaking;

@end

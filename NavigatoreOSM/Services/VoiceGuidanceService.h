#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface VoiceGuidanceService : NSObject

@property (nonatomic, assign) BOOL isMuted;

+ (instancetype)sharedService;

- (void)speak:(NSString *)text;
- (void)speakManeuver:(NSString *)instruction distanceInMeters:(double)distance;
- (void)stopSpeaking;

@end

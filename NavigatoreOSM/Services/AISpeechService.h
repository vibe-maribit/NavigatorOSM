#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

extern NSString *const kPrefAISpeechBaseURL;
extern NSString *const kPrefAISpeechAPIKey;
extern NSString *const kPrefAISTTEnabled;
extern NSString *const kPrefAITTSEnabled;
extern NSString *const kPrefAITTSVoice;
extern NSString *const kAISpeechSettingsChangedNotification;

@interface AISpeechService : NSObject

@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, assign) BOOL isSTTEnabled;
@property (nonatomic, assign) BOOL isExternalTTSEnabled;
@property (nonatomic, copy) NSString *selectedVoice;

@property (nonatomic, readonly) BOOL isRecording;

+ (instancetype)sharedService;

// Voci supportate
+ (NSArray<NSString *> *)availableVoices;
+ (NSString *)displayNameForVoice:(NSString *)voice;

// Registrazione microfono
- (void)startRecordingWithCompletion:(void(^)(BOOL success, NSError *error))completion;
- (void)stopRecordingWithCompletion:(void(^)(NSURL *audioURL, NSError *error))completion;
- (void)cancelRecording;

// Trascrizione vocale (STT)
- (void)transcribeAudioAtURL:(NSURL *)audioURL
                    language:(NSString *)language
                  completion:(void(^)(NSString *transcription, NSError *error))completion;

// Sintesi vocale (TTS)
- (void)synthesizeSpeech:(NSString *)text
                   voice:(NSString *)voice
              completion:(void(^)(NSData *mp3Data, NSError *error))completion;

// Riproduzione audio MP3
- (void)playAudioData:(NSData *)data completion:(void(^)(BOOL success))completion;
- (void)stopPlayback;

// Riproduzione campione vocale per anteprima
- (void)playSampleForVoice:(NSString *)voice completion:(void(^)(BOOL success, NSError *error))completion;

@end

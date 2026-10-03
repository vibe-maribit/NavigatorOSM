#import "AISpeechService.h"
#import "LocalizationManager.h"

NSString *const kPrefAISpeechBaseURL = @"AISpeechBaseURL";
NSString *const kPrefAISpeechAPIKey = @"AISpeechAPIKey";
NSString *const kPrefAISTTEnabled = @"AISTTEnabled";
NSString *const kPrefAITTSEnabled = @"AITTSEnabled";
NSString *const kPrefAITTSVoice = @"AITTSVoice";
NSString *const kAISpeechSettingsChangedNotification = @"AISpeechSettingsChangedNotification";

static NSString *const kDefaultBaseURL = @"https://speech.applikat.it";
static NSString *const kDefaultAPIKey = @"sk-speech-i5pdahJ68pyIby6Vj6YRkTufC80uj91CKhZQxKCof0d0cz0RbIck2T5Cabsi";
static NSString *const kDefaultVoice = @"alloy";

@interface AISpeechService () <AVAudioRecorderDelegate, AVAudioPlayerDelegate>
@property (nonatomic, strong) AVAudioRecorder *audioRecorder;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, copy) void (^playbackCompletion)(BOOL success);
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign, readwrite) BOOL isRecording;
@end

@implementation AISpeechService

+ (instancetype)sharedService {
    static AISpeechService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AISpeechService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        config.timeoutIntervalForResource = 20.0;
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"NavigatoreOSM/1.3.16 (iPad Mini 1; iOS 9.3.5; AISpeech)"
        };
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - Voci Supportate

+ (NSArray<NSString *> *)availableVoices {
    return @[@"alloy", @"echo", @"fable", @"onyx", @"nova", @"shimmer"];
}

+ (NSString *)displayNameForVoice:(NSString *)voice {
    if ([voice isEqualToString:@"alloy"]) return @"Alloy (Neutro, bilanciato)";
    if ([voice isEqualToString:@"echo"]) return @"Echo (Maschile, chiaro)";
    if ([voice isEqualToString:@"fable"]) return @"Fable (Espressivo, caldo)";
    if ([voice isEqualToString:@"onyx"]) return @"Onyx (Maschile, profondo)";
    if ([voice isEqualToString:@"nova"]) return @"Nova (Femminile, brillante)";
    if ([voice isEqualToString:@"shimmer"]) return @"Shimmer (Femminile, morbido)";
    return voice ?: @"Alloy";
}

#pragma mark - Proprietà & Preferenze

- (NSString *)baseURL {
    NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey:kPrefAISpeechBaseURL];
    if (val.length > 0) return val;
    return kDefaultBaseURL;
}

- (void)setBaseURL:(NSString *)baseURL {
    NSString *trimmed = [baseURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:kPrefAISpeechBaseURL];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kAISpeechSettingsChangedNotification object:self];
}

- (NSString *)apiKey {
    NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey:kPrefAISpeechAPIKey];
    if (val.length > 0) return val;
    return kDefaultAPIKey;
}

- (void)setApiKey:(NSString *)apiKey {
    NSString *trimmed = [apiKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:kPrefAISpeechAPIKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kAISpeechSettingsChangedNotification object:self];
}

- (BOOL)isSTTEnabled {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:kPrefAISTTEnabled]) {
        return YES; // Attivo di default
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:kPrefAISTTEnabled];
}

- (void)setIsSTTEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kPrefAISTTEnabled];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kAISpeechSettingsChangedNotification object:self];
}

- (BOOL)isExternalTTSEnabled {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:kPrefAITTSEnabled]) {
        return NO; // Spento di default (strettamente opzionale)
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:kPrefAITTSEnabled];
}

- (void)setIsExternalTTSEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kPrefAITTSEnabled];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kAISpeechSettingsChangedNotification object:self];
}

- (NSString *)selectedVoice {
    NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey:kPrefAITTSVoice];
    if (val.length > 0) return val;
    return kDefaultVoice;
}

- (void)setSelectedVoice:(NSString *)voice {
    if (!voice || voice.length == 0) voice = kDefaultVoice;
    [[NSUserDefaults standardUserDefaults] setObject:voice forKey:kPrefAITTSVoice];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kAISpeechSettingsChangedNotification object:self];
}

#pragma mark - Registrazione Audio Microfono

- (NSURL *)recordingFileURL {
    NSString *tempDir = NSTemporaryDirectory();
    NSString *path = [tempDir stringByAppendingPathComponent:@"voice_search.m4a"];
    return [NSURL fileURLWithPath:path];
}

- (void)startRecordingWithCompletion:(void(^)(BOOL success, NSError *error))completion {
    if (self.isRecording) {
        if (completion) completion(YES, nil);
        return;
    }

    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *sessErr = nil;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:&sessErr];
    [session setActive:YES error:&sessErr];

    if ([session respondsToSelector:@selector(requestRecordPermission:)]) {
        [session requestRecordPermission:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!granted) {
                    NSError *err = [NSError errorWithDomain:@"AISpeechError" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Permesso microfono non concesso"}];
                    if (completion) completion(NO, err);
                    return;
                }
                [self setupAndStartRecorderWithCompletion:completion];
            });
        }];
    } else {
        [self setupAndStartRecorderWithCompletion:completion];
    }
}

- (void)setupAndStartRecorderWithCompletion:(void(^)(BOOL success, NSError *error))completion {
    NSURL *fileURL = [self recordingFileURL];
    [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];

    NSDictionary *recordSettings = @{
        AVFormatIDKey: @(kAudioFormatMPEG4AAC),
        AVSampleRateKey: @(16000.0),
        AVNumberOfChannelsKey: @(1),
        AVEncoderAudioQualityKey: @(AVAudioQualityMedium)
    };

    NSError *recErr = nil;
    self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:fileURL settings:recordSettings error:&recErr];
    self.audioRecorder.delegate = self;

    if (recErr || !self.audioRecorder) {
        NSLog(@"[AISpeechService] Errore inizializzazione recorder: %@", recErr);
        if (completion) completion(NO, recErr);
        return;
    }

    BOOL ok = [self.audioRecorder record];
    self.isRecording = ok;
    if (completion) completion(ok, ok ? nil : [NSError errorWithDomain:@"AISpeechError" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Impossibile avviare registrazione"}]);
}

- (void)stopRecordingWithCompletion:(void(^)(NSURL *audioURL, NSError *error))completion {
    if (!self.isRecording || !self.audioRecorder) {
        if (completion) completion(nil, [NSError errorWithDomain:@"AISpeechError" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Nessuna registrazione attiva"}]);
        return;
    }

    [self.audioRecorder stop];
    self.isRecording = NO;
    NSURL *fileURL = self.audioRecorder.url;
    self.audioRecorder = nil;

    // Ripristina sessione audio per riproduzione
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    });

    if (completion) completion(fileURL, nil);
}

- (void)cancelRecording {
    if (self.audioRecorder) {
        [self.audioRecorder stop];
        [self.audioRecorder deleteRecording];
        self.audioRecorder = nil;
    }
    self.isRecording = NO;
}

#pragma mark - Trascrizione Vocale (STT)

- (void)transcribeAudioAtURL:(NSURL *)audioURL
                    language:(NSString *)language
                  completion:(void(^)(NSString *transcription, NSError *error))completion {
    if (!audioURL || ![[NSFileManager defaultManager] fileExistsAtPath:audioURL.path]) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"AISpeechError" code:-4 userInfo:@{NSLocalizedDescriptionKey: @"File audio non trovato"}]);
        }
        return;
    }

    NSData *audioData = [NSData dataWithContentsOfURL:audioURL];
    if (!audioData || audioData.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"AISpeechError" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"File audio vuoto"}]);
        }
        return;
    }

    NSString *lang = (language.length > 0) ? language : @"it";
    NSURL *base = [NSURL URLWithString:self.baseURL];
    NSString *scheme = base.scheme ?: @"https";
    NSString *host = base.host ?: @"speech.applikat.it";

    // Se l'host è il server speech.applikat.it usiamo l'endpoint whisper specializzato
    NSString *urlString;
    NSString *fieldName = @"audio_file";
    if ([host containsString:@"applikat.it"]) {
        NSString *prompt = [@"Indirizzo stradale italiano via piazza corso numero civico" stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        urlString = [NSString stringWithFormat:@"%@://%@/stt/asr?task=transcribe&language=%@&output=txt&initial_prompt=%@", scheme, host, lang, prompt];
    } else {
        // Fallback OpenAI standard
        urlString = [NSString stringWithFormat:@"%@://%@/v1/audio/transcriptions", scheme, host];
        fieldName = @"file";
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 12.0;

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.apiKey];
    [request setValue:authHeader forHTTPHeaderField:@"Authorization"];

    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];

    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"voice.m4a\"\r\n", fieldName] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: audio/m4a\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:audioData];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];

    // Se usiamo OpenAI standard, aggiungi parametro model
    if (![host containsString:@"applikat.it"]) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"Content-Disposition: form-data; name=\"model\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"whisper-1\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"Content-Disposition: form-data; name=\"language\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@\r\n", lang] dataUsingEncoding:NSUTF8StringEncoding]];
    }

    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    request.HTTPBody = body;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[AISpeechService] Errore rete STT: %@", error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
            }
            return;
        }

        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode < 200 || httpResp.statusCode >= 300) {
            NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[AISpeechService] Risposta HTTP %ld STT: %@", (long)httpResp.statusCode, respStr);
            NSError *err = [NSError errorWithDomain:@"AISpeechError" code:httpResp.statusCode userInfo:@{NSLocalizedDescriptionKey: respStr ?: @"Errore server STT"}];
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
            }
            return;
        }

        NSString *resultText = nil;
        // Prova prima a deserializzare JSON
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]] && json[@"text"]) {
            resultText = [json[@"text"] description];
        } else {
            resultText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }

        // Pulisci il testo
        resultText = [resultText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        resultText = [resultText stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(resultText, nil); });
        }
    }];
    [task resume];
}

#pragma mark - Sintesi Vocale (TTS)

- (void)synthesizeSpeech:(NSString *)text
                   voice:(NSString *)voice
              completion:(void(^)(NSData *mp3Data, NSError *error))completion {
    if (!text || text.length == 0) {
        if (completion) completion(nil, [NSError errorWithDomain:@"AISpeechError" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"Testo vuoto"}]);
        return;
    }

    NSURL *base = [NSURL URLWithString:self.baseURL];
    NSString *scheme = base.scheme ?: @"https";
    NSString *host = base.host ?: @"speech.applikat.it";

    NSString *urlString;
    if ([self.baseURL containsString:@"/tts/v1"]) {
        urlString = [NSString stringWithFormat:@"%@/audio/speech", [self.baseURL stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]];
    } else if ([host containsString:@"applikat.it"]) {
        urlString = [NSString stringWithFormat:@"%@://%@/tts/v1/audio/speech", scheme, host];
    } else {
        urlString = [NSString stringWithFormat:@"%@://%@/v1/audio/speech", scheme, host];
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 4.0; // Fail-fast per non bloccare la navigazione
    [request setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSString *voiceName = voice ?: self.selectedVoice;
    NSDictionary *payload = @{
        @"model": @"tts-1",
        @"input": text,
        @"voice": voiceName
    };

    NSError *jsonErr = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonErr];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
            }
            return;
        }

        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode < 200 || httpResp.statusCode >= 300 || !data || data.length == 0) {
            NSError *err = [NSError errorWithDomain:@"AISpeechError" code:httpResp.statusCode userInfo:@{NSLocalizedDescriptionKey: @"Errore sintesi audio TTS"}];
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
            }
            return;
        }

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(data, nil); });
        }
    }];
    [task resume];
}

#pragma mark - Riproduzione Audio MP3

- (void)playAudioData:(NSData *)data completion:(void(^)(BOOL success))completion {
    if (!data || data.length == 0) {
        if (completion) completion(NO);
        return;
    }

    [self stopPlayback];

    NSError *err = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    [session setActive:YES error:nil];

    self.audioPlayer = [[AVAudioPlayer alloc] initWithData:data error:&err];
    if (err || !self.audioPlayer) {
        NSLog(@"[AISpeechService] Errore riproduzione AVAudioPlayer: %@", err);
        if (completion) completion(NO);
        return;
    }

    self.playbackCompletion = completion;
    self.audioPlayer.delegate = self;
    [self.audioPlayer prepareToPlay];
    [self.audioPlayer play];
}

- (void)stopPlayback {
    if (self.audioPlayer) {
        [self.audioPlayer stop];
        self.audioPlayer = nil;
    }
    if (self.playbackCompletion) {
        self.playbackCompletion(NO);
        self.playbackCompletion = nil;
    }
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    self.audioPlayer = nil;
    if (self.playbackCompletion) {
        self.playbackCompletion(flag);
        self.playbackCompletion = nil;
    }
}

#pragma mark - Anteprima Voce

- (void)playSampleForVoice:(NSString *)voice completion:(void(^)(BOOL success, NSError *error))completion {
    NSString *sampleText = [NSString stringWithFormat:@"Questa è la voce neurale %@.", [voice capitalizedString]];
    __weak AISpeechService *weakSelf = self;
    [self synthesizeSpeech:sampleText voice:voice completion:^(NSData *mp3Data, NSError *error) {
        if (error || !mp3Data) {
            if (completion) completion(NO, error);
            return;
        }
        [weakSelf playAudioData:mp3Data completion:^(BOOL success) {
            if (completion) completion(success, nil);
        }];
    }];
}

@end

#import <Foundation/Foundation.h>

extern NSString *const kAppLanguagePreferenceChangedNotification;

@interface LocalizationManager : NSObject

+ (instancetype)sharedManager;

/// Current active language code: @"it" or @"en"
@property (nonatomic, copy, readonly) NSString *currentLanguage;

/// User preference: @"auto", @"en", @"it"
@property (nonatomic, copy) NSString *selectedLanguagePreference;

/// Returns YES if current language is Italian
- (BOOL)isItalian;

/// Returns localized string for key, or fallback if key not found
- (NSString *)localizedStringForKey:(NSString *)key fallback:(NSString *)fallback;

/// Returns BCP-47 speech code for AVSpeechSynthesizer (e.g. @"it-IT" or @"en-US")
- (NSString *)speechVoiceLanguage;

@end

/// Convenience function for localized strings
static inline NSString *NLString(NSString *key, NSString *fallback) {
    return [[LocalizationManager sharedManager] localizedStringForKey:key fallback:fallback];
}

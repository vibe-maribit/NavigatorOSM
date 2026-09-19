#import "LocalizationManager.h"

NSString *const kAppLanguagePreferenceChangedNotification = @"AppLanguagePreferenceChangedNotification";
static NSString *const kLanguagePreferenceKey = @"AppLanguagePreference";

@interface LocalizationManager ()
@property (nonatomic, copy, readwrite) NSString *currentLanguage;
@property (nonatomic, strong) NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *translations;
@end

@implementation LocalizationManager

+ (instancetype)sharedManager {
    static LocalizationManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LocalizationManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupTranslations];
        [self refreshLanguage];
    }
    return self;
}

- (void)setupTranslations {
    self.translations = @{
        @"it": @{
            // Settings
            @"SETTINGS_TITLE": @"⚙️ Impostazioni",
            @"CLOSE": @"✕ Chiudi",
            @"SEC_VERSION": @"ℹ️ VERSIONE SOFTWARE & SISTEMA",
            @"SEC_LANGUAGE": @"🌐 LINGUA APPLICAZIONE",
            @"SEC_GPS": @"🛰️ RICEVITORE GPS DI RETE (DA SMARTPHONE ANDROID)",
            @"SEC_CYDIA": @"📲 AGGIORNAMENTI AUTOMATICI ONLINE (CYDIA OTA)",
            @"SEC_VOICE": @"🔊 GUIDA VOCALE",
            @"SEC_MAP": @"🗺️ MAPPE & ASPETTO",
            @"APP_VERSION": @"Versione Applicazione",
            @"BUILD_DATE": @"Data di Compilazione",
            @"PLATFORM": @"Piattaforma",
            @"INTERFACE_LANG": @"Lingua Interfaccia",
            @"LANG_AUTO": @"Auto (Sistema)",
            @"LANG_EN": @"English",
            @"LANG_IT": @"Italiano",
            @"PROTOCOL": @"Protocollo Ricezione",
            @"PORT": @"Porta Ricezione (Default 8888)",
            @"SERVER_IP": @"IP Server Android (per TCP)",
            @"DIAGNOSTICS": @"Diagnostica Ricezione",
            @"LAST_LOCATION": @"Ultima Posizione Ricevuta",
            @"CYDIA_SOURCE": @"Sorgente Cydia",
            @"OTA_INSTRUCTIONS": @"Istruzioni OTA:",
            @"OTA_STEPS": @"Apri Cydia > Sorgenti > Modifica > Aggiungi",
            @"VOICE_SWITCH": @"Attiva Istruzioni Vocali",
            @"VOICE_MODE": @"Modalità Voce",
            @"VOICE_ALL": @"🔊 Completa",
            @"VOICE_ALERTS": @"⚠️ Solo Allerte",
            @"VOICE_MUTED": @"🔇 Muto",
            @"SHOW_FUEL_ON_MAP": @"Mostra Distributori su Mappa",
            @"DETOUR_REROUTE": @"⚠️ Fuori rotta • 🔄 Ricalcola",
            @"RECALCULATING_DETOUR": @"🔄 Ricalcolo percorso...",
            @"MAP_STYLE": @"Stile Mappa",
            @"MAP_DAY": @"Giorno",
            @"MAP_NIGHT": @"Notte",
            @"MAP_SAT": @"Satellite",
            @"SAVE_EXIT": @"💾 Salva ed Esci",
            @"COPIED_TITLE": @"Copiato!",
            @"COPIED_CYDIA_MSG": @"L'indirizzo del repository Cydia è stato copiato negli appunti.\n\nOra apri Cydia > Sorgenti > Modifica > Aggiungi e incolla l'URL.",
            @"NO_PACKETS": @"Nessun pacchetto ricevuto",
            @"LISTENING_UDP": @"In ascolto UDP",
            @"CONNECTED_TCP": @"Connesso TCP",
            @"STOPPED": @"Fermo",
            @"SEC_FUEL": @"⛽ CARBURANTE & COSTI DI VIAGGIO",
            @"FUEL_TYPE": @"Tipo Carburante",
            @"FUEL_PETROL": @"Benzina",
            @"FUEL_DIESEL": @"Diesel",
            @"FUEL_ELECTRIC": @"Elettrico",
            @"FUEL_CONSUMPTION": @"Consumo Medio",
            @"FUEL_PRICE": @"Prezzo Carburante",
            @"UPDATE_ONLINE_PRICES": @"Aggiorna Prezzi Online (MIMIT)",
            @"FETCHING_PRICES": @"MIMIT Carburanti",
            @"FETCHING_PRICES_MSG": @"Recupero dei prezzi medi dai distributori in zona...",
            @"TAP_TO_UPDATE": @"Tocca per aggiornare",
            @"SUCCESS": @"Completato",
            @"ERROR": @"Errore",
            @"ROUTE_OPTIONS": @"Opzioni:",
            @"AVOID_TOLLS": @"🚫 No Pedaggio",
            @"AVOID_HIGHWAYS": @"🛣️ No Autostrade",
            @"SEARCHING_NO_TOLLS": @"Ricerca itinerari senza pedaggio...",
            @"SEARCHING_NO_HWY": @"Ricerca itinerari senza autostrade...",
            @"SEARCHING_NO_TOLLS_NO_HWY": @"Ricerca itinerari senza pedaggi e senza autostrade...",
            @"NO_TOLLS": @"🛣️ Senza pedaggio",
            @"SEC_TRAFFIC_VELOX": @"🚦 TRAFFICO LIVE & 📸 AUTOVELOX",
            @"TRAFFIC_ENABLED": @"Traffico in Tempo Reale",
            @"TOMTOM_KEY": @"Chiave API TomTom (Traffico)",
            @"SPEED_CAMERA_ALERTS": @"Avvisi Visivi & Vocali Autovelox",
            @"TRAFFIC_KEY_TITLE": @"Traffico in Tempo Reale",
            @"TRAFFIC_KEY_MSG": @"Il livello del traffico è attivo ma richiede una chiave API TomTom per visualizzare il flusso in tempo reale.\n\nPuoi registrarti gratuitamente su developer.tomtom.com (2500 richieste/giorno) e inserirla nelle Impostazioni.",

            // Main View & Voice
            @"READY_3D": @"Navigatore pronto con visuale 3D prospettica.",
            @"SEARCH_PLACEHOLDER": @"  🔍 Cerca destinazione o indirizzo...",
            @"WAITING_GPS": @"GPS: In attesa di segnale...",
            @"GPS_LOCKED": @"GPS: Segnale agganciato",
            @"TRAFFIC_ON": @"Traffico attivato.",
            @"TRAFFIC_OFF": @"Traffico disattivato.",
            @"SAT_MODE": @"Modalità satellite attivata.",
            @"NIGHT_MODE": @"Modalità notturna attivata.",
            @"DAY_MODE": @"Mappa standard attivata.",
            @"NAV_ENDED": @"Navigazione terminata.",
            @"SEARCHING_ROUTES": @"Ricerca itinerari alternativi...",
            @"NO_ROUTE_FOUND": @"Impossibile trovare un percorso per questa destinazione.",
            @"CALC_ERROR": @"Errore nel calcolo del percorso.",
            @"FOUND_ROUTES_VOICE": @"Trovati %lu itinerari. Tocca quello desiderato per iniziare.",
            @"SEARCHING_POI": @"Ricerca %@ nelle vicinanze in corso...",
            @"ARRIVED": @"Sei arrivato a destinazione.",
            @"RECALCULATING": @"Ricalcolo del percorso in corso...",
            @"NEW_ROUTE_READY": @"Nuovo percorso pronto. Continua a guidare.",
            @"THEN_STREET": @"Poi %@ su %@",
            @"READY_TO_DRIVE": @"Pronto per la guida",
            @"TAP_TO_START": @"Tocca 'Cerca' o 'POI' per iniziare",
            @"START_NAVIGATION": @"▶ Avvia Navigazione",
            @"CANCEL": @"Annulla",
            @"TRAFFIC_SMOOTH": @"🟢 Traffico regolare",
            @"TRAFFIC_SLOW": @"🟡 Rallentamenti",
            @"TRAFFIC_HEAVY": @"🔴 Traffico intenso",
            @"BADGE_OPTIMAL": @"⭐ Ottimale",
            @"BADGE_FASTEST": @"🚀 Più Veloce",
            @"BADGE_SHORTEST": @"🍃 Più Breve",
            @"BADGE_ALTERNATIVE": @"⚖️ Alternativa",
            @"BADGE_SCENIC": @"🍃 Panoramica",
            @"RECOMMENDED": @"Consigliato",
            @"OVERSPEED": @"ECCESSO!",
            @"SPEED_KMH": @"KM/H",
            @"FUEL": @"Benzina",
            @"RESTAURANTS": @"Ristoranti",
            @"PARKING": @"Parcheggi",
            @"CAFE": @"Bar",
            @"PHARMACY": @"Farmacie",
            @"POI_NEARBY": @"%@ %lu nelle vicinanze",
            @"NAVIGATE_TO": @"Naviga verso questo luogo",
            @"ROUTE_TO_DEST": @"Rotta",
            @"SEARCH_TITLE": @"Cerca Destinazione",
            @"SEARCH_INPUT_PLACEHOLDER": @"Cerca via, città o luogo...",
            @"RECENT_DESTINATIONS": @"🕒 DESTINAZIONI RECENTI",
            @"CLEAR_HISTORY": @"🗑️ Cancella cronologia destinazioni",
            @"SHOW_ALL_MAP": @"📍 Mostra tutti i %lu risultati sulla mappa",
            @"RECENT_DEST_SUB": @"Destinazione recente",
            @"VOICE_1000M": @"Tra circa un chilometro, %@",
            @"VOICE_500M": @"Tra 500 metri, %@",
            @"VOICE_200M": @"Tra 200 metri, %@",
            @"VOICE_NOW": @"Ora, %@",
            @"ROUTE_SUMMARY": @"📋 Riepilogo Itinerario",
            @"FIND_MORE_ROUTES": @"🔄 Ricalcola / Altri itinerari",
            @"MORE_ROUTES": @"🔄 Altri",
            @"REPEAT_VOICE": @"🔊 Ripeti voce",
            @"STEP_HEADER": @"Passaggio %lu di %lu",
            @"TOTAL_REMAINING": @"Rimanente: %@ • %@",
            @"POI_FOUND_VOICE": @"Trovati %lu %@ nelle vicinanze.",
            @"NO_STEPS": @"Nessun passaggio disponibile."
        },

        @"en": @{
            // Settings
            @"SETTINGS_TITLE": @"⚙️ Settings",
            @"CLOSE": @"✕ Close",
            @"SEC_VERSION": @"ℹ️ SOFTWARE & SYSTEM VERSION",
            @"SEC_LANGUAGE": @"🌐 APPLICATION LANGUAGE",
            @"SEC_GPS": @"🛰️ NETWORK GPS RECEIVER (FROM ANDROID)",
            @"SEC_CYDIA": @"📲 AUTOMATIC OTA UPDATES (CYDIA)",
            @"SEC_VOICE": @"🔊 VOICE GUIDANCE",
            @"SEC_MAP": @"🗺️ MAPS & APPEARANCE",
            @"APP_VERSION": @"Application Version",
            @"BUILD_DATE": @"Build Date",
            @"PLATFORM": @"Platform",
            @"INTERFACE_LANG": @"Interface Language",
            @"LANG_AUTO": @"Auto (System)",
            @"LANG_EN": @"English",
            @"LANG_IT": @"Italiano",
            @"PROTOCOL": @"Receiver Protocol",
            @"PORT": @"Receiver Port (Default 8888)",
            @"SERVER_IP": @"Android Server IP (for TCP)",
            @"DIAGNOSTICS": @"Receiver Diagnostics",
            @"LAST_LOCATION": @"Last Known Position",
            @"CYDIA_SOURCE": @"Cydia Source",
            @"OTA_INSTRUCTIONS": @"OTA Instructions:",
            @"OTA_STEPS": @"Open Cydia > Sources > Edit > Add",
            @"VOICE_SWITCH": @"Enable Spoken Directions",
            @"VOICE_MODE": @"Voice Guidance",
            @"VOICE_ALL": @"🔊 Full",
            @"VOICE_ALERTS": @"⚠️ Alerts Only",
            @"VOICE_MUTED": @"🔇 Muted",
            @"SHOW_FUEL_ON_MAP": @"Show Fuel Stations on Map",
            @"DETOUR_REROUTE": @"⚠️ Off Route • 🔄 Reroute",
            @"RECALCULATING_DETOUR": @"🔄 Recalculating route...",
            @"MAP_STYLE": @"Map Style",
            @"MAP_DAY": @"Day",
            @"MAP_NIGHT": @"Night",
            @"MAP_SAT": @"Satellite",
            @"SAVE_EXIT": @"💾 Save and Exit",
            @"COPIED_TITLE": @"Copied!",
            @"COPIED_CYDIA_MSG": @"The Cydia repository URL has been copied to clipboard.\n\nNow open Cydia > Sources > Edit > Add and paste the URL.",
            @"NO_PACKETS": @"No packets received",
            @"LISTENING_UDP": @"Listening UDP",
            @"CONNECTED_TCP": @"Connected TCP",
            @"STOPPED": @"Stopped",
            @"SEC_FUEL": @"⛽ FUEL & TRIP COSTS",
            @"FUEL_TYPE": @"Fuel Type",
            @"FUEL_PETROL": @"Petrol",
            @"FUEL_DIESEL": @"Diesel",
            @"FUEL_ELECTRIC": @"Electric",
            @"FUEL_CONSUMPTION": @"Average Consumption",
            @"FUEL_PRICE": @"Fuel Price",
            @"UPDATE_ONLINE_PRICES": @"Update Live Prices (MIMIT)",
            @"FETCHING_PRICES": @"MIMIT Fuel Prices",
            @"FETCHING_PRICES_MSG": @"Fetching average local fuel prices...",
            @"TAP_TO_UPDATE": @"Tap to update now",
            @"SUCCESS": @"Success",
            @"ERROR": @"Error",
            @"ROUTE_OPTIONS": @"Options:",
            @"AVOID_TOLLS": @"🚫 Avoid Tolls",
            @"AVOID_HIGHWAYS": @"🛣️ Avoid Highways",
            @"SEARCHING_NO_TOLLS": @"Searching toll-free routes...",
            @"SEARCHING_NO_HWY": @"Searching routes avoiding highways...",
            @"SEARCHING_NO_TOLLS_NO_HWY": @"Searching toll-free non-highway routes...",
            @"NO_TOLLS": @"🛣️ Toll-free",
            @"SEC_TRAFFIC_VELOX": @"🚦 LIVE TRAFFIC & 📸 SPEED CAMERAS",
            @"TRAFFIC_ENABLED": @"Real-Time Traffic Flow",
            @"TOMTOM_KEY": @"TomTom API Key (Traffic)",
            @"SPEED_CAMERA_ALERTS": @"Speed Camera Visual & Voice Alerts",
            @"TRAFFIC_KEY_TITLE": @"Real-Time Traffic Flow",
            @"TRAFFIC_KEY_MSG": @"The traffic layer is enabled but requires a TomTom API key to download live flow tiles.\n\nYou can sign up for free at developer.tomtom.com (2500 requests/day) and enter it in Settings.",

            // Main View & Voice
            @"READY_3D": @"Navigator ready with 3D cockpit perspective.",
            @"SEARCH_PLACEHOLDER": @"  🔍 Search destination or address...",
            @"WAITING_GPS": @"GPS: Waiting for satellite fix...",
            @"GPS_LOCKED": @"GPS: Locked onto fix",
            @"TRAFFIC_ON": @"Live traffic flow enabled.",
            @"TRAFFIC_OFF": @"Live traffic flow disabled.",
            @"SAT_MODE": @"Satellite mode activated.",
            @"NIGHT_MODE": @"Night mode activated.",
            @"DAY_MODE": @"Standard map activated.",
            @"NAV_ENDED": @"Navigation ended.",
            @"SEARCHING_ROUTES": @"Searching alternative routes...",
            @"NO_ROUTE_FOUND": @"Unable to find a route to this destination.",
            @"CALC_ERROR": @"Error calculating route.",
            @"FOUND_ROUTES_VOICE": @"Found %lu routes. Tap your preferred route to start.",
            @"SEARCHING_POI": @"Searching nearby %@...",
            @"ARRIVED": @"You have arrived at your destination.",
            @"RECALCULATING": @"Recalculating route...",
            @"NEW_ROUTE_READY": @"New route ready. Continue driving.",
            @"THEN_STREET": @"Then %@ onto %@",
            @"READY_TO_DRIVE": @"Ready to drive",
            @"TAP_TO_START": @"Tap 'Search' or 'POI' to begin",
            @"START_NAVIGATION": @"▶ Start Navigation",
            @"CANCEL": @"Cancel",
            @"TRAFFIC_SMOOTH": @"🟢 Smooth Flow",
            @"TRAFFIC_SLOW": @"🟡 Slowdowns",
            @"TRAFFIC_HEAVY": @"🔴 Heavy Traffic",
            @"BADGE_OPTIMAL": @"⭐ Optimal",
            @"BADGE_FASTEST": @"🚀 Fastest",
            @"BADGE_SHORTEST": @"🍃 Shortest",
            @"BADGE_ALTERNATIVE": @"⚖️ Alternative",
            @"BADGE_SCENIC": @"🍃 Scenic",
            @"RECOMMENDED": @"Recommended",
            @"OVERSPEED": @"OVERSPEED!",
            @"SPEED_KMH": @"KM/H",
            @"FUEL": @"Fuel",
            @"RESTAURANTS": @"Restaurants",
            @"PARKING": @"Parking",
            @"CAFE": @"Cafe",
            @"PHARMACY": @"Pharmacy",
            @"POI_NEARBY": @"%@ %lu nearby",
            @"NAVIGATE_TO": @"Navigate to this place",
            @"ROUTE_TO_DEST": @"Route",
            @"SEARCH_TITLE": @"Search Destination",
            @"SEARCH_INPUT_PLACEHOLDER": @"Search street, city or place...",
            @"RECENT_DESTINATIONS": @"🕒 RECENT DESTINATIONS",
            @"CLEAR_HISTORY": @"🗑️ Clear destination history",
            @"SHOW_ALL_MAP": @"📍 Show all %lu results on map",
            @"RECENT_DEST_SUB": @"Recent destination",
            @"VOICE_1000M": @"In about one kilometer, %@",
            @"VOICE_500M": @"In 500 meters, %@",
            @"VOICE_200M": @"In 200 meters, %@",
            @"VOICE_NOW": @"Now, %@",
            @"ROUTE_SUMMARY": @"📋 Route Summary",
            @"FIND_MORE_ROUTES": @"🔄 Recalculate / Other routes",
            @"MORE_ROUTES": @"🔄 Alternatives",
            @"REPEAT_VOICE": @"🔊 Repeat instruction",
            @"STEP_HEADER": @"Step %lu of %lu",
            @"TOTAL_REMAINING": @"Remaining: %@ • %@",
            @"POI_FOUND_VOICE": @"Found %lu %@ nearby.",
            @"NO_STEPS": @"No steps available."
        }
    };
}

- (void)refreshLanguage {
    NSString *pref = [[NSUserDefaults standardUserDefaults] stringForKey:kLanguagePreferenceKey];
    if (!pref || [pref isEqualToString:@"auto"] || pref.length == 0) {
        NSArray *preferredLangs = [NSLocale preferredLanguages];
        NSString *primary = preferredLangs.count > 0 ? preferredLangs[0] : @"en";
        if ([primary hasPrefix:@"it"]) {
            self.currentLanguage = @"it";
        } else {
            self.currentLanguage = @"en";
        }
    } else if ([pref isEqualToString:@"it"]) {
        self.currentLanguage = @"it";
    } else {
        self.currentLanguage = @"en";
    }
}

- (NSString *)selectedLanguagePreference {
    NSString *pref = [[NSUserDefaults standardUserDefaults] stringForKey:kLanguagePreferenceKey];
    return pref ?: @"auto";
}

- (void)setSelectedLanguagePreference:(NSString *)preference {
    if (!preference) preference = @"auto";
    [[NSUserDefaults standardUserDefaults] setObject:preference forKey:kLanguagePreferenceKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [self refreshLanguage];

    [[NSNotificationCenter defaultCenter] postNotificationName:kAppLanguagePreferenceChangedNotification object:nil];
}

- (BOOL)isItalian {
    return [self.currentLanguage isEqualToString:@"it"];
}

- (NSString *)localizedStringForKey:(NSString *)key fallback:(NSString *)fallback {
    if (!key) return fallback ?: @"";
    NSDictionary *dict = self.translations[self.currentLanguage];
    NSString *val = dict[key];
    if (val) return val;

    // Fallback to English dictionary
    NSDictionary *enDict = self.translations[@"en"];
    val = enDict[key];
    if (val) return val;

    return fallback ?: key;
}

- (NSString *)speechVoiceLanguage {
    return [self isItalian] ? @"it-IT" : @"en-US";
}

@end

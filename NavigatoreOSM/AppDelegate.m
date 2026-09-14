#import "AppDelegate.h"
#import "Controllers/NavigationViewController.h"
#import <AVFoundation/AVFoundation.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. Evita lo spegnimento dello schermo durante la navigazione
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    // 2. Configura la sessione audio per consentire la voce guida anche in background
    @try {
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setCategory:AVAudioSessionCategoryPlayback
                      withOptions:AVAudioSessionCategoryOptionDuckOthers
                            error:nil];
        [audioSession setActive:YES error:nil];
    } @catch (NSException *exception) {
        NSLog(@"[AppDelegate] Errore configurazione AVAudioSession: %@", exception);
    }

    // 3. Inizializza la finestra principale e il NavigationViewController
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    NavigationViewController *navVC = [[NavigationViewController alloc] init];
    UINavigationController *rootNavController = [[UINavigationController alloc] initWithRootViewController:navVC];
    rootNavController.navigationBarHidden = YES;

    self.window.rootViewController = rootNavController;
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Mantieni attivo lo schermo se l'app torna attiva
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

@end

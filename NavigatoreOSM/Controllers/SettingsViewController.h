#import <UIKit/UIKit.h>

@class SettingsViewController;

@protocol SettingsViewControllerDelegate <NSObject>
@optional
- (void)settingsViewControllerDidUpdateSettings:(SettingsViewController *)controller;
@end

@interface SettingsViewController : UITableViewController

@property (nonatomic, weak) id<SettingsViewControllerDelegate> delegate;

@end

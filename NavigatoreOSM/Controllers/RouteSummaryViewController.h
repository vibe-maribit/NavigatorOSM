#import <UIKit/UIKit.h>
#import "../Services/RoutingService.h"

@class RouteSummaryViewController;

@protocol RouteSummaryViewControllerDelegate <NSObject>
@optional
- (void)routeSummaryViewControllerDidRequestRecalculate:(RouteSummaryViewController *)controller;
- (void)routeSummaryViewControllerDidRequestRepeatVoice:(RouteSummaryViewController *)controller;
- (void)routeSummaryViewControllerDidClose:(RouteSummaryViewController *)controller;
- (void)routeSummaryViewController:(RouteSummaryViewController *)controller didSelectStepIndex:(NSUInteger)stepIndex;
@end

@interface RouteSummaryViewController : UIViewController

@property (nonatomic, strong) RouteInfo *route;
@property (nonatomic, assign) NSUInteger currentStepIndex;
@property (nonatomic, weak) id<RouteSummaryViewControllerDelegate> delegate;

@end

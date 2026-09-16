#import <UIKit/UIKit.h>
#import "../Services/RoutingService.h"

@class RouteSelectorView;

@protocol RouteSelectorViewDelegate <NSObject>
- (void)routeSelectorView:(RouteSelectorView *)view didSelectRouteIndex:(NSUInteger)index;
- (void)routeSelectorView:(RouteSelectorView *)view didConfirmStartRoute:(RouteInfo *)selectedRoute;
- (void)routeSelectorViewDidCancel:(RouteSelectorView *)view;
@optional
- (void)routeSelectorViewDidRequestRecalculate:(RouteSelectorView *)view;
- (void)routeSelectorView:(RouteSelectorView *)view didToggleAvoidTolls:(BOOL)avoidTolls avoidHighways:(BOOL)avoidHighways;
@end

@interface RouteSelectorView : UIView

@property (nonatomic, weak) id<RouteSelectorViewDelegate> delegate;
@property (nonatomic, readonly) NSUInteger selectedIndex;
@property (nonatomic, readonly) NSArray<RouteInfo *> *routes;

/// Opzioni al volo
@property (nonatomic, assign) BOOL avoidTolls;
@property (nonatomic, assign) BOOL avoidHighways;

- (void)setRoutes:(NSArray<RouteInfo *> *)routes;
- (void)resetToggles;

@end

#import <UIKit/UIKit.h>
#import "../Services/RoutingService.h"

@class RouteSelectorView;

@protocol RouteSelectorViewDelegate <NSObject>
- (void)routeSelectorView:(RouteSelectorView *)view didSelectRouteIndex:(NSUInteger)index;
- (void)routeSelectorView:(RouteSelectorView *)view didConfirmStartRoute:(RouteInfo *)selectedRoute;
- (void)routeSelectorViewDidCancel:(RouteSelectorView *)view;
@end

@interface RouteSelectorView : UIView

@property (nonatomic, weak) id<RouteSelectorViewDelegate> delegate;
@property (nonatomic, readonly) NSUInteger selectedIndex;
@property (nonatomic, readonly) NSArray<RouteInfo *> *routes;

- (void)setRoutes:(NSArray<RouteInfo *> *)routes;

@end

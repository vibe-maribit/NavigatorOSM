#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@protocol NetworkGPSReceiverDelegate <NSObject>
- (void)networkGPSDidUpdateLocation:(CLLocation *)location heading:(CLLocationDirection)heading;
@end

@interface NetworkGPSReceiver : NSObject

@property (nonatomic, weak) id<NetworkGPSReceiverDelegate> delegate;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, assign) NSInteger port;

+ (instancetype)sharedReceiver;
- (void)startListeningOnPort:(NSInteger)port;
- (void)stopListening;

@end

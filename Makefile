export ARCHS = armv7
export TARGET = iphone:clang:9.3:9.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = NavigatoreOSM

NavigatoreOSM_FILES = NavigatoreOSM/main.m \
                      NavigatoreOSM/AppDelegate.m \
                      NavigatoreOSM/Controllers/NavigationViewController.m \
                      NavigatoreOSM/Controllers/SearchViewController.m \
                      NavigatoreOSM/Controllers/SettingsViewController.m \
                      NavigatoreOSM/Controllers/RouteSummaryViewController.m \
                      NavigatoreOSM/Overlays/OSMTileOverlay.m \
                      NavigatoreOSM/Overlays/TrafficTileOverlay.m \
                      NavigatoreOSM/Services/RoutingService.m \
                      NavigatoreOSM/Services/RouteTrackingEngine.m \
                      NavigatoreOSM/Services/FuelPriceService.m \
                      NavigatoreOSM/Services/VoiceGuidanceService.m \
                      NavigatoreOSM/Services/LocalizationManager.m \
                      NavigatoreOSM/Services/NetworkGPSReceiver.m \
                      NavigatoreOSM/Services/TollGuruService.m \
                      NavigatoreOSM/Services/SpeedCameraService.m \
                      NavigatoreOSM/Views/ManeuverHUDView.m \
                      NavigatoreOSM/Views/ModernTripBarView.m \
                      NavigatoreOSM/Views/SpeedometerView.m \
                      NavigatoreOSM/Views/RouteSelectorView.m \
                      NavigatoreOSM/Views/QuickPOIShelfView.m \
                      NavigatoreOSM/Views/POIResultsCardView.m \
                      NavigatoreOSM/Views/VehicleAnnotationView.m \
                      NavigatoreOSM/Views/SpeedCameraAnnotationView.m \
                      NavigatoreOSM/Views/FuelStationAnnotationView.m

NavigatoreOSM_FRAMEWORKS = UIKit Foundation CoreGraphics CoreLocation MapKit AVFoundation QuartzCore
NavigatoreOSM_CFLAGS = -fobjc-arc -INavigatoreOSM -O2

include $(THEOS_MAKE_PATH)/application.mk

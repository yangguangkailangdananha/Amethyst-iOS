#import <UIKit/UIKit.h>
#include <dlfcn.h>

#define realUIIdiom UIDevice.currentDevice.userInterfaceIdiom
extern NSNotificationName UIPresentationControllerPresentationTransitionWillBeginNotification;

@interface UIDevice(hook)
- (NSString *)completeOSVersion;
@end

@interface UIImageView(hook)
@property(nonatomic) BOOL isSizeFixed;
@end

@interface UIImage(hook)
- (UIImage *)hook_imageWithSize:(CGSize)size;
@end

@interface UIBarButtonItem(addition)
- (UIView *)buttonGlassView;
@end

// private functions
// The symbol only exists in the iOS 26+ UIKit. Resolve it lazily with dlsym so
// the app still links when built against an older iPhoneOS SDK.
static inline BOOL (*_UISolariumEnabledPointer(void))(void) {
    static BOOL (*symbol)(void);
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        symbol = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "_UISolariumEnabled");
    });
    return symbol;
}
#define _UISolariumEnabled _UISolariumEnabledPointer()

@interface UIBarButtonItem(private)
- (UIView *)view;
// Introduced with the iOS 26 SDK. Declared here so the code also compiles with
// older SDKs (the call site is guarded by @available(iOS 19.0, *)).
@property(nonatomic) BOOL sharesBackground;
@end

@interface UIContextMenuInteraction(private)
- (void)_presentMenuAtLocation:(CGPoint)location;
@end
@interface _UIContextMenuStyle : NSObject <NSCopying>
@property(nonatomic) NSInteger preferredLayout;
+ (instancetype)defaultStyle;
@end

@interface UIDevice(private)
- (NSString *)buildVersion;
- (void)_setActiveUserInterfaceIdiom:(NSInteger)idiom;
@end

@interface UIImage(private)
- (UIImage *)_imageWithSize:(CGSize)size;
@end

@interface UIScreen(private)
- (void)_setUserInterfaceIdiom:(NSInteger)idiom;
@end

@interface UISegmentedControl(private)
- (NSArray *)_uiktest_labelsWithState:(NSUInteger)state;
@end

@interface UITextField(private)
@property(assign, nonatomic) NSInteger nonEditingLinebreakMode;
@end

@interface UIWindow(global)
+ (UIWindow *)mainWindow;
+ (UIWindow *)externalWindow;
@end

@protocol _UIPointerInteractionDriver<NSObject>
@property (assign, nonatomic) UIView *view;
@end

@interface UIPointerInteraction(private)
- (NSArray <id<_UIPointerInteractionDriver>> *)drivers;
- (id<_UIPointerInteractionDriver>)driver;
@end

@interface UIPopoverPresentationController(private)
- (BOOL)_isDismissing;
@end

/*
@interface WFTextTokenTextView : UITextField
@property(nonatomic) NSString* placeholder
@end
*/

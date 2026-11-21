#import <UIKit/UIKit.h>

#define TYPE_INSTALLED 0
#define TYPE_RELEASE 1
#define TYPE_SNAPSHOT 2
#define TYPE_OLDBETA 3
#define TYPE_OLDALPHA 4

@interface MinecraftResourceUtils : NSObject

+ (void)processVersion:(NSMutableDictionary *)json inheritsFrom:(NSMutableDictionary *)inheritsFrom;
+ (void)tweakVersionJson:(NSMutableDictionary *)json;

+ (NSObject *)findVersion:(NSString *)version inList:(NSArray *)list;
+ (NSObject *)findNearestVersion:(NSObject *)version expectedType:(int)type;

// Returns the LWJGL version requested by a version JSON (e.g. "3.3.3"), or nil
// when the version does not depend on LWJGL.
+ (NSString *)requiredLWJGLVersionForVersionJSON:(NSDictionary *)json;

// Returns YES when the version uses org.lwjgl.sdl (Minecraft 26.3+ / SDL3).
// Versions using LWJGL 3.4.x with GLFW (26.1/26.2) return NO.
+ (BOOL)requiresSDLForVersionJSON:(NSDictionary *)json;

// Returns YES when the version can run with the libraries bundled in the app.
// Minecraft 26.x switched from GLFW to SDL3 (org.lwjgl.sdl, LWJGL 3.4+), which
// the iOS GLFW bridge does not implement, so those versions are rejected unless
// debug.allow_unsupported_versions is enabled.
+ (BOOL)isVersionJSONLaunchable:(NSDictionary *)json;

// Human readable reason for a version being rejected, or nil when it can run.
+ (NSString *)unsupportedReasonForVersionJSON:(NSDictionary *)json;

@end

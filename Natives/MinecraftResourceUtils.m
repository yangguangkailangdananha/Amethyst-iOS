#include <CommonCrypto/CommonDigest.h>

#import "authenticator/BaseAuthenticator.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "MinecraftResourceUtils.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@implementation MinecraftResourceUtils

// Handle inheritsFrom
+ (void)processVersion:(NSMutableDictionary *)json inheritsFrom:(NSMutableDictionary *)inheritsFrom {
    [self insertSafety:inheritsFrom from:json arr:@[
        @"assetIndex", @"assets", @"id",
        @"inheritsFrom",
        @"mainClass", @"minecraftArguments",
        @"optifineLib", @"releaseTime", @"time", @"type"
    ]];
    inheritsFrom[@"arguments"] = json[@"arguments"];

    for (NSMutableDictionary *lib in json[@"libraries"]) {
        NSString *libName = [lib[@"name"] substringToIndex:[lib[@"name"] rangeOfString:@":" options:NSBackwardsSearch].location];
        int i;
        for (i = 0; i < [inheritsFrom[@"libraries"] count]; i++) {
            NSMutableDictionary *libAdded = inheritsFrom[@"libraries"][i];
            NSString *libAddedName = [libAdded[@"name"] substringToIndex:[libAdded[@"name"] rangeOfString:@":" options:NSBackwardsSearch].location];

            if ([libAdded[@"name"] hasPrefix:libName]) {
                inheritsFrom[@"libraries"][i] = lib;
                i = -1;
                break;
            }
        }

        if (i != -1) {
            [inheritsFrom[@"libraries"] addObject:lib];
        }
    }

    //inheritsFrom[@"inheritsFrom"] = nil;
}

+ (void)insertSafety:(NSMutableDictionary *)targetVer from:(NSDictionary *)fromVer arr:(NSArray *)arr {
    for (NSString *key in arr) {
        if (([fromVer[key] isKindOfClass:NSString.class] && [fromVer[key] length] > 0) || targetVer[key] == nil) {
            targetVer[key] = fromVer[key];
        } else {
            NSLog(@"[MCDL] insertSafety: how to insert %@?", key);
        }
    }
}

+ (NSInteger)numberOfArgsToSkipForArg:(NSString *)arg {
    if (![arg isKindOfClass:NSString.class]) {
        // Skip non-string arg
        return 1;
    } else if ([arg hasPrefix:@"-cp"]) {
        // Skip "-cp <classpath>"
        return 2;
    } else if ([arg hasPrefix:@"-Djava.library.path="]) {
        return 1;
    } else if ([arg hasPrefix:@"-XX:HeapDumpPath"]) {
        return 1;
    } else {
        return 0;
    }
}

+ (void)tweakVersionJson:(NSMutableDictionary *)json {
    // Exclude some libraries
    for (NSMutableDictionary *library in json[@"libraries"]) {
        library[@"skip"] = @(
            // Exclude platform-dependant libraries
            library[@"downloads"][@"classifiers"] != nil ||
            library[@"natives"] != nil ||
            // Exclude LWJGL libraries
            [library[@"name"] hasPrefix:@"org.lwjgl"]
        );

        NSString *versionStr = [library[@"name"] componentsSeparatedByString:@":"][2];
        NSArray<NSString *> *version = [versionStr componentsSeparatedByString:@"."];
        if ([library[@"name"] hasPrefix:@"net.java.dev.jna:jna:"]) {
            // Special handling for LabyMod 1.8.9 and Forge 1.12.2(?)
            // we have libjnidispatch 5.13.0 in Frameworks directory
            uint32_t bundledVer = 5 << 16 | 13 << 8 | 0;
            uint32_t requiredVer = (char)version[0].intValue << 16 | (char)version[1].intValue << 8 | (char)version[2].intValue;
            if (requiredVer > bundledVer) {
                if (getPrefBool(@"java.allow_newer_jna")) {
                    NSLog(@"[MCDL] Warning: JNA version required by %@ is %@ > 5.13.0, keeping the version-specified build (patched native library may not match).", json[@"id"], versionStr);
                    continue;
                }
                // The bundled libjnidispatch.dylib and the Platform class patch are
                // built for 5.13.0, so a newer jar would be loaded against an older
                // native library. Keep the bundled version for consistency.
                NSLog(@"[MCDL] Note: %@ requests JNA %@ > bundled 5.13.0, using bundled 5.13.0 to keep the patched native library matched.", json[@"id"], versionStr);
            }
            library[@"name"] = @"net.java.dev.jna:jna:5.13.0";
            library[@"downloads"][@"artifact"][@"path"] = @"net/java/dev/jna/jna/5.13.0/jna-5.13.0.jar";
            library[@"downloads"][@"artifact"][@"url"] = @"https://repo1.maven.org/maven2/net/java/dev/jna/jna/5.13.0/jna-5.13.0.jar";
            library[@"downloads"][@"artifact"][@"sha1"] = @"1200e7ebeedbe0d10062093f32925a912020e747";
        } else if ([library[@"name"] hasPrefix:@"org.ow2.asm:asm-all:"]) {
            // Early versions of the ASM library get repalced with 5.0.4 because Pojav's LWJGL is compiled for
            // Java 8, which is not supported by old ASM versions. Mod loaders like Forge, which depend on this
            // library, often include lwjgl in their class transformations, which causes errors with old ASM versions.
            if(version[0].intValue >= 5) continue;
            library[@"name"] = @"org.ow2.asm:asm-all:5.0.4";
            library[@"downloads"][@"artifact"][@"path"] = @"org/ow2/asm/asm-all/5.0.4/asm-all-5.0.4.jar";
            library[@"downloads"][@"artifact"][@"sha1"] = @"e6244859997b3d4237a552669279780876228909";
            library[@"downloads"][@"artifact"][@"url"] = @"https://repo1.maven.org/maven2/org/ow2/asm/asm-all/5.0.4/asm-all-5.0.4.jar";
        }
    }

    // Add the client as a library
    NSMutableDictionary *client = [[NSMutableDictionary alloc] init];
    client[@"downloads"] = [[NSMutableDictionary alloc] init];
    if (json[@"downloads"][@"client"] == nil) {
        client[@"downloads"][@"artifact"] = [[NSMutableDictionary alloc] init];
        client[@"skip"] = @YES;
    } else {
        client[@"downloads"][@"artifact"] = json[@"downloads"][@"client"];
    }
    client[@"downloads"][@"artifact"][@"path"] = [NSString stringWithFormat:@"../versions/%1$@/%1$@.jar", json[@"id"]];
    client[@"name"] = [NSString stringWithFormat:@"%@.jar", json[@"id"]];
    [json[@"libraries"] addObject:client];

    // Parse Forge 1.17+ additional JVM Arguments
    if (json[@"inheritsFrom"] == nil || json[@"arguments"][@"jvm"] == nil) {
        return;
    }
    json[@"arguments"][@"jvm_processed"] = [[NSMutableArray alloc] init];
    NSDictionary *varArgMap = @{
        @"${classpath_separator}": @":",
        @"${library_directory}": [NSString stringWithFormat:@"%s/libraries", getenv("GAME_DIR")],
        @"${version_name}": json[@"id"]
    };
    int argsToSkip = 0;
    for (NSString *arg in json[@"arguments"][@"jvm"]) {
        if (argsToSkip == 0) {
            argsToSkip = [self numberOfArgsToSkipForArg:arg];
        }
        if (argsToSkip == 0) {
            NSString *argStr = arg;
            for (NSString *key in varArgMap.allKeys) {
                argStr = [argStr stringByReplacingOccurrencesOfString:key withString:varArgMap[key]];
            }
            [json[@"arguments"][@"jvm_processed"] addObject:argStr];
        } else {
            argsToSkip--;
        }
    }
}

+ (NSObject *)findVersion:(NSString *)version inList:(NSArray *)list {
    return [list filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(id == %@)", version]].firstObject;
}

+ (NSObject *)findNearestVersion:(NSObject *)version expectedType:(int)type {
    if (type != TYPE_RELEASE && type != TYPE_SNAPSHOT) {
        // Only support finding for releases and snapshot for now
        return nil;
    }

    if ([version isKindOfClass:NSString.class]){
        // Find in inheritsFrom
        NSDictionary *versionDict = parseJSONFromFile([NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("GAME_DIR"), version]);
        NSAssert(versionDict != nil, @"version should not be null");
        if (versionDict[@"inheritsFrom"] == nil) {
            // How then?
            return nil; 
        }
        NSObject *inheritsFrom = [self findVersion:versionDict[@"inheritsFrom"] inList:remoteVersionList];
        if (type == TYPE_RELEASE) {
            return inheritsFrom;
        } else if (type == TYPE_SNAPSHOT) {
            return [self findNearestVersion:inheritsFrom expectedType:type];
        }
    }

    NSString *versionType = [version valueForKey:@"type"];
    int index = [remoteVersionList indexOfObject:(NSDictionary *)version];
    if ([versionType isEqualToString:@"release"] && type == TYPE_SNAPSHOT) {
        // Returns the (possible) latest snapshot for the version
        NSDictionary *result = remoteVersionList[index + 1];
        // Sometimes, a release is followed with another release (1.16->1.16.1), go lower in this case
        if ([result[@"type"] isEqualToString:@"release"]) {
            return [self findNearestVersion:result expectedType:type];
        }
        return result;
    } else if ([versionType isEqualToString:@"snapshot"] && type == TYPE_RELEASE) {
        while (remoteVersionList.count > abs(index)) {
            // In case the snapshot has yet attached to a release, perform a reverse find
            NSDictionary *result = remoteVersionList[abs(index)];
            // Returns the corresponding release for the snapshot, or latest release if none found
            if ([result[@"type"] isEqualToString:@"release"]) {
                return result;
            }
            // Continue to decrement, later abs() it
            index--;
        }
    }

    // No idea on handling everything else
    return nil;
}

#pragma mark - Runtime compatibility

static BOOL AMEVersionAtLeast(NSString *version, int major, int minor) {
    NSArray<NSString *> *parts = [version componentsSeparatedByString:@"."];
    int actualMajor = parts.count > 0 ? parts[0].intValue : 0;
    int actualMinor = parts.count > 1 ? parts[1].intValue : 0;
    if (actualMajor != major) {
        return actualMajor > major;
    }
    return actualMinor >= minor;
}

+ (NSString *)requiredLWJGLVersionForVersionJSON:(NSDictionary *)json {
    NSString *lwjglVersion = nil;
    NSArray *libraries = json[@"libraries"];
    if (![libraries isKindOfClass:NSArray.class]) {
        return nil;
    }
    for (NSDictionary *library in libraries) {
        NSString *name = library[@"name"];
        if (![name isKindOfClass:NSString.class]) {
            continue;
        }
        NSArray<NSString *> *parts = [name componentsSeparatedByString:@":"];
        if (parts.count < 3 || ![parts[0] isEqualToString:@"org.lwjgl"]) {
            continue;
        }
        // Minecraft 26.x dropped lwjgl-glfw in favour of lwjgl-sdl.
        if ([parts[1] isEqualToString:@"lwjgl"] || [parts[1] isEqualToString:@"lwjgl-sdl"]) {
            lwjglVersion = parts[2];
        }
    }
    return lwjglVersion;
}

+ (BOOL)requiresSDLForVersionJSON:(NSDictionary *)json {
    NSArray *libraries = json[@"libraries"];
    if (![libraries isKindOfClass:NSArray.class]) {
        return NO;
    }
    for (NSDictionary *library in libraries) {
        NSString *name = library[@"name"];
        if ([name isKindOfClass:NSString.class] && [name hasPrefix:@"org.lwjgl:lwjgl-sdl"]) {
            return YES;
        }
    }
    return NO;
}

+ (NSString *)unsupportedReasonForVersionJSON:(NSDictionary *)json {
    if (getPrefBool(@"debug.allow_unsupported_versions")) {
        return nil;
    }

    NSString *lwjglVersion = [self requiredLWJGLVersionForVersionJSON:json];
    if (lwjglVersion.length == 0) {
        return nil;
    }

    BOOL requiresSDL = [self requiresSDLForVersionJSON:json];

    if (requiresSDL) {
        // Experimental MC 26.x path: the SDL3 runtime + Amethyst video driver is
        // bundled under Frameworks/lwjgl343. Allow it when present so the
        // feature/mc26-native build can be tested on device; regular builds do
        // not ship that directory and keep refusing the version.
        NSString *sdlRuntime = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/lwjgl343/libSDL3.dylib"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:sdlRuntime]) {
            return nil;
        }
        // Minecraft 26.3+ replaced GLFW with SDL3 (org.lwjgl.sdl).
        return [NSString stringWithFormat:localize(@"launcher.error.unsupported_version.reason.sdl", nil), lwjglVersion];
    }
    if (AMEVersionAtLeast(lwjglVersion, 3, 4)) {
        // 26.1/26.2 still use GLFW, but newer native libraries are not bundled and
        // the GLFW bridge of this build is compiled against 3.3.3.
        return [NSString stringWithFormat:localize(@"launcher.error.unsupported_version.reason.lwjgl", nil), lwjglVersion];
    }
    return nil;
}

+ (BOOL)isVersionJSONLaunchable:(NSDictionary *)json {
    return [self unsupportedReasonForVersionJSON:json] == nil;
}

@end

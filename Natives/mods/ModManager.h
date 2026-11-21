#import <Foundation/Foundation.h>

// ModManager handles everything that concerns the "mods" folder of the selected
// instance profile: resolving the right directory, listing/importing/enabling
// mods and reading basic metadata out of mod jars.
@interface ModManager : NSObject

#pragma mark Paths

+ (NSDictionary *)currentProfile;
+ (NSString *)gameDirectoryForProfile:(NSDictionary *)profile;
+ (NSString *)modsDirectoryForProfile:(NSDictionary *)profile createIfNeeded:(BOOL)create;

#pragma mark Profile metadata

// Base Minecraft version (e.g. "1.21.11") of the profile's selected version.
+ (NSString *)minecraftVersionForProfile:(NSDictionary *)profile;
// Mod loader of the profile: fabric, quilt, forge, neoforge or vanilla.
+ (NSString *)modLoaderForProfile:(NSDictionary *)profile;
// Human readable description, e.g. "Fabric · 1.21.11".
+ (NSString *)profileDescription:(NSDictionary *)profile;

#pragma mark Installed mods

// Each entry contains: path, fileName, displayName, identifier, version, size,
// enabled.
+ (NSArray<NSDictionary *> *)listModsInDirectory:(NSString *)directory;
+ (BOOL)setMod:(NSDictionary *)mod enabled:(BOOL)enabled;
+ (BOOL)deleteMod:(NSDictionary *)mod error:(NSError *__autoreleasing *)error;

#pragma mark Import

// Accepts .jar files as well as .zip/.mrpack archives that contain mod jars.
// Returns the file names copied into the mods directory, or nil on error.
+ (NSArray<NSString *> *)importFileAtPath:(NSString *)path
                            intoDirectory:(NSString *)directory
                                    error:(NSError *__autoreleasing *)error;

#pragma mark Helpers

+ (NSString *)formatSize:(unsigned long long)size;

@end

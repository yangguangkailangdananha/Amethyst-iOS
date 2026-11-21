#import "LauncherPreferences.h"
#import "ModManager.h"
#import "PLProfiles.h"
#import "UnzipKit.h"
#import "utils.h"

#define fm NSFileManager.defaultManager

static NSError *ModManagerError(NSString *message) {
    return [NSError errorWithDomain:@"ModManager"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

@interface ModManager ()
+ (NSDictionary *)versionJSONForProfile:(NSDictionary *)profile;
+ (NSString *)baseMinecraftVersionFrom:(NSString *)versionId;
+ (NSDictionary *)metadataForModAtPath:(NSString *)path;
+ (NSDictionary *)parseModsToml:(NSData *)data;
@end

@implementation ModManager

#pragma mark - Paths

+ (NSDictionary *)currentProfile {
    NSDictionary *profile = PLProfiles.current.selectedProfile;
    if ([profile isKindOfClass:NSDictionary.class] && profile.count > 0) {
        return profile;
    }
    return @{@"name": @"(Default)", @"lastVersionId": @"latest-release"};
}

+ (NSString *)gameDirectoryForProfile:(NSDictionary *)profile {
    NSString *instanceName = getPrefObject(@"general.game_directory");
    if (instanceName.length == 0) {
        instanceName = @"default";
    }
    NSString *instancePath = [NSString stringWithFormat:@"%s/instances/%@", getenv("AME_HOME"), instanceName];

    NSString *gameDir = profile[@"gameDir"];
    if (![gameDir isKindOfClass:NSString.class] || gameDir.length == 0) {
        gameDir = @".";
    }
    return [instancePath stringByAppendingPathComponent:gameDir].stringByStandardizingPath;
}

+ (NSString *)modsDirectoryForProfile:(NSDictionary *)profile createIfNeeded:(BOOL)create {
    NSString *modsPath = [[self gameDirectoryForProfile:profile] stringByAppendingPathComponent:@"mods"];
    if (create) {
        [fm createDirectoryAtPath:modsPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return modsPath;
}

#pragma mark - Profile metadata

+ (NSDictionary *)versionJSONForProfile:(NSDictionary *)profile {
    NSString *versionId = profile[@"lastVersionId"];
    if (versionId.length == 0) {
        NSDictionary *latest = getPrefObject(@"internal.latest_version");
        versionId = latest[@"release"] ?: @"latest-release";
    }
    NSString *path = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("GAME_DIR"), versionId];
    NSMutableDictionary *json = parseJSONFromFile(path);
    if (json[@"NSErrorObject"]) {
        return nil;
    }
    return json;
}

// "fabric-loader-<loader>-<game>" -> "<game>", "1.21.1-forge-52.0.0" -> "1.21.1"
+ (NSString *)baseMinecraftVersionFrom:(NSString *)versionId {
    if (![versionId isKindOfClass:NSString.class] || versionId.length == 0) {
        return nil;
    }

    for (NSString *prefix in @[@"fabric-loader-", @"quilt-loader-"]) {
        if ([versionId hasPrefix:prefix]) {
            NSString *rest = [versionId substringFromIndex:prefix.length];
            NSRange dash = [rest rangeOfString:@"-"];
            if (dash.location != NSNotFound) {
                return [rest substringFromIndex:dash.location + 1];
            }
            return rest;
        }
    }

    for (NSString *marker in @[@"-neoforge-", @"-forge-"]) {
        NSRange range = [versionId rangeOfString:marker];
        if (range.location != NSNotFound) {
            return [versionId substringToIndex:range.location];
        }
    }

    return versionId;
}

+ (NSString *)minecraftVersionForProfile:(NSDictionary *)profile {
    NSDictionary *json = [self versionJSONForProfile:profile];
    NSString *versionId = json[@"id"];
    if (![versionId isKindOfClass:NSString.class] || versionId.length == 0) {
        versionId = profile[@"lastVersionId"];
    }

    // Loader based profiles inherit from the actual game version.
    NSString *inheritsFrom = json[@"inheritsFrom"];
    if ([inheritsFrom isKindOfClass:NSString.class] && inheritsFrom.length > 0) {
        return [self baseMinecraftVersionFrom:inheritsFrom];
    }
    return [self baseMinecraftVersionFrom:versionId];
}

+ (NSString *)modLoaderForProfile:(NSDictionary *)profile {
    NSDictionary *json = [self versionJSONForProfile:profile];
    for (NSDictionary *library in json[@"libraries"]) {
        NSString *name = library[@"name"];
        if (![name isKindOfClass:NSString.class]) {
            continue;
        }
        if ([name hasPrefix:@"net.fabricmc:fabric-loader"]) {
            return @"fabric";
        }
        if ([name hasPrefix:@"org.quiltmc:quilt-loader"]) {
            return @"quilt";
        }
        if ([name hasPrefix:@"net.neoforged:neoforge"] || [name hasPrefix:@"net.neoforged.fancymodloader"]) {
            return @"neoforge";
        }
        if ([name hasPrefix:@"net.minecraftforge:forge"] || [name hasPrefix:@"net.minecraftforge:fmlloader"]) {
            return @"forge";
        }
    }

    // Fall back to the version id naming scheme used by the installers.
    NSString *versionId = profile[@"lastVersionId"];
    if ([versionId isKindOfClass:NSString.class]) {
        if ([versionId containsString:@"neoforge"]) return @"neoforge";
        if ([versionId containsString:@"forge"]) return @"forge";
        if ([versionId containsString:@"quilt"]) return @"quilt";
        if ([versionId containsString:@"fabric"]) return @"fabric";
    }
    return @"vanilla";
}

+ (NSString *)profileDescription:(NSDictionary *)profile {
    NSString *loader = [self modLoaderForProfile:profile];
    NSString *version = [self minecraftVersionForProfile:profile];
    NSString *loaderName = loader.uppercaseString;
    if ([loader isEqualToString:@"vanilla"]) {
        loaderName = @"Vanilla";
    } else if ([loader isEqualToString:@"neoforge"]) {
        loaderName = @"NeoForge";
    }
    if (version.length == 0) {
        return loaderName;
    }
    return [NSString stringWithFormat:@"%@ · %@", loaderName, version];
}

#pragma mark - Installed mods

+ (NSDictionary *)metadataForModAtPath:(NSString *)path {
    NSString *fallbackName = path.lastPathComponent;
    NSMutableDictionary *result = @{
        @"displayName": fallbackName,
        @"identifier": fallbackName,
        @"version": @""
    }.mutableCopy;

    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:nil];
    if (archive == nil) {
        return result;
    }

    // Fabric
    NSData *data = [archive extractDataFromFile:@"fabric.mod.json" error:nil];
    if (data.length > 0) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:NSDictionary.class]) {
            NSString *name = json[@"name"];
            NSString *identifier = json[@"id"];
            NSString *version = json[@"version"];
            if (name.length > 0) result[@"displayName"] = name;
            if (identifier.length > 0) result[@"identifier"] = identifier;
            if (version.length > 0) result[@"version"] = version;
            return result;
        }
    }

    // Quilt
    data = [archive extractDataFromFile:@"quilt.mod.json" error:nil];
    if (data.length > 0) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *loader = json[@"quilt_loader"];
        if ([loader isKindOfClass:NSDictionary.class]) {
            NSString *identifier = loader[@"id"];
            NSString *version = loader[@"version"];
            if (identifier.length > 0) {
                result[@"identifier"] = identifier;
                result[@"displayName"] = identifier;
            }
            if (version.length > 0) result[@"version"] = version;
            return result;
        }
    }

    // Forge / NeoForge
    for (NSString *tomlName in @[@"META-INF/neoforge.mods.toml", @"META-INF/mods.toml"]) {
        data = [archive extractDataFromFile:tomlName error:nil];
        if (data.length == 0) {
            continue;
        }
        NSDictionary *parsed = [self parseModsToml:data];
        if (parsed[@"modId"]) {
            result[@"identifier"] = parsed[@"modId"];
            result[@"displayName"] = parsed[@"displayName"] ?: parsed[@"modId"];
            if (parsed[@"version"]) result[@"version"] = parsed[@"version"];
            return result;
        }
    }

    // Legacy Forge
    data = [archive extractDataFromFile:@"mcmod.info" error:nil];
    if (data.length > 0) {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *info = nil;
        if ([json isKindOfClass:NSDictionary.class]) {
            NSArray *modList = ((NSDictionary *)json)[@"modList"];
            info = [modList isKindOfClass:NSArray.class] ? modList.firstObject : json;
        } else if ([json isKindOfClass:NSArray.class] && [json count] > 0) {
            info = [json firstObject];
        }
        if ([info isKindOfClass:NSDictionary.class]) {
            NSString *name = info[@"name"];
            NSString *identifier = info[@"modid"];
            NSString *version = info[@"version"];
            if (name.length > 0) result[@"displayName"] = name;
            if (identifier.length > 0) result[@"identifier"] = identifier;
            if (version.length > 0) result[@"version"] = version;
        }
    }

    return result;
}

+ (NSDictionary *)parseModsToml:(NSData *)data {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text.length == 0) {
        return @{};
    }

    NSMutableDictionary *result = [NSMutableDictionary new];
    for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([line hasPrefix:@"#"] || ![line containsString:@"="]) {
            continue;
        }
        NSRange separator = [line rangeOfString:@"="];
        NSString *key = [[line substringToIndex:separator.location]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *value = [[line substringFromIndex:separator.location + 1]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
        if (key.length == 0 || value.length == 0) {
            continue;
        }
        if ([key isEqualToString:@"modId"] && result[@"modId"] == nil) {
            result[@"modId"] = value;
        } else if ([key isEqualToString:@"displayName"] && result[@"displayName"] == nil) {
            result[@"displayName"] = value;
        } else if ([key isEqualToString:@"version"] && result[@"version"] == nil) {
            result[@"version"] = value;
        }
    }
    return result;
}

+ (NSArray<NSDictionary *> *)listModsInDirectory:(NSString *)directory {
    [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

    NSMutableArray<NSDictionary *> *mods = [NSMutableArray new];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:directory error:nil];
    for (NSString *file in files) {
        if ([file hasPrefix:@"."] || [file isEqualToString:@"__MACOSX"]) {
            continue;
        }
        BOOL enabled = YES;
        NSString *fileName = file;
        if ([file hasSuffix:@".disabled"]) {
            enabled = NO;
            fileName = [file stringByDeletingPathExtension];
        }
        if (![fileName.pathExtension isEqualToString:@"jar"]) {
            continue;
        }

        NSString *path = [directory stringByAppendingPathComponent:file];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) {
            continue;
        }

        NSMutableDictionary *metadata = [[self metadataForModAtPath:path] mutableCopy];
        metadata[@"path"] = path;
        metadata[@"fileName"] = file;
        metadata[@"enabled"] = @(enabled);
        NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil];
        metadata[@"size"] = @([attributes[NSFileSize] unsignedLongLongValue]);
        [mods addObject:metadata];
    }

    [mods sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *nameA = a[@"displayName"] ?: a[@"fileName"];
        NSString *nameB = b[@"displayName"] ?: b[@"fileName"];
        return [nameA localizedCaseInsensitiveCompare:nameB];
    }];
    return mods;
}

+ (BOOL)setMod:(NSDictionary *)mod enabled:(BOOL)enabled {
    NSString *path = mod[@"path"];
    if (![path isKindOfClass:NSString.class] || ![fm fileExistsAtPath:path]) {
        return NO;
    }

    NSString *newPath = path;
    if (enabled && [path hasSuffix:@".disabled"]) {
        newPath = [path stringByDeletingPathExtension];
    } else if (!enabled && ![path hasSuffix:@".disabled"]) {
        newPath = [path stringByAppendingString:@".disabled"];
    }
    if ([newPath isEqualToString:path]) {
        return YES;
    }
    return [fm moveItemAtPath:path toPath:newPath error:nil];
}

+ (BOOL)deleteMod:(NSDictionary *)mod error:(NSError *__autoreleasing *)error {
    NSString *path = mod[@"path"];
    if (![path isKindOfClass:NSString.class] || ![fm fileExistsAtPath:path]) {
        if (error) *error = ModManagerError(localize(@"mods.error.mod_missing", nil));
        return NO;
    }
    return [fm removeItemAtPath:path error:error];
}

#pragma mark - Import

+ (NSArray<NSString *> *)importFileAtPath:(NSString *)path
                            intoDirectory:(NSString *)directory
                                    error:(NSError *__autoreleasing *)error {
    [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *extension = path.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"jar"]) {
        NSString *fileName = path.lastPathComponent;
        NSString *destination = [directory stringByAppendingPathComponent:fileName];
        [fm removeItemAtPath:destination error:nil];
        NSError *copyError = nil;
        if (![fm copyItemAtPath:path toPath:destination error:&copyError]) {
            if (error) *error = copyError ?: ModManagerError(localize(@"mods.error.copy_failed", nil));
            return nil;
        }
        return @[fileName];
    }

    if (![extension isEqualToString:@"zip"] && ![extension isEqualToString:@"mrpack"]) {
        if (error) *error = ModManagerError([NSString stringWithFormat:
            localize(@"mods.error.unsupported_file", nil), extension]);
        return nil;
    }

    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:error];
    if (archive == nil) {
        return nil;
    }

    NSMutableArray<NSString *> *installed = [NSMutableArray new];
    __block NSError *extractError = nil;
    [archive performOnFilesInArchive:^(UZKFileInfo *fileInfo, BOOL *stop) {
        if (fileInfo.isDirectory || ![fileInfo.filename.pathExtension.lowercaseString isEqualToString:@"jar"]) {
            return;
        }
        NSString *fileName = fileInfo.filename.lastPathComponent;
        if (fileName.length == 0) {
            return;
        }
        NSString *destination = [directory stringByAppendingPathComponent:fileName];
        NSError *innerError = nil;
        NSData *data = [archive extractData:fileInfo error:&innerError];
        if (data.length == 0 || ![data writeToFile:destination options:NSDataWritingAtomic error:&innerError]) {
            extractError = innerError ?: ModManagerError([NSString stringWithFormat:
                localize(@"mods.error.extract_failed", nil), fileName]);
            *stop = YES;
            return;
        }
        [installed addObject:fileName];
        NSLog(@"[Mods] Extracted %@", fileName);
    } error:&extractError];

    if (extractError != nil) {
        if (error) *error = extractError;
        return nil;
    }
    if (installed.count == 0) {
        if (error) *error = ModManagerError(localize(@"mods.error.no_jars", nil));
        return nil;
    }
    return installed;
}

#pragma mark - Helpers

+ (NSString *)formatSize:(unsigned long long)size {
    return [NSByteCountFormatter stringFromByteCount:(long long)size countStyle:NSByteCountFormatterCountStyleFile];
}

@end

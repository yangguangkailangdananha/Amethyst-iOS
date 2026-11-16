#import "MinecraftResourceDownloadTask.h"
#import "ModrinthAPI.h"
#import "PLProfiles.h"
#import "utils.h"

static BOOL AMESharesValues(NSArray<NSString *> *left, NSArray<NSString *> *right) {
    if (left.count == 0 || right.count == 0) {
        return YES;
    }
    NSMutableSet *values = [NSMutableSet setWithArray:left];
    [values intersectSet:[NSSet setWithArray:right]];
    return values.count > 0;
}

@implementation ModrinthAPI

- (instancetype)init {
    return [super initWithURL:@"https://api.modrinth.com/v2"];
}

- (NSMutableArray *)searchModWithFilters:(NSDictionary<NSString *, NSString *> *)searchFilters previousPageResult:(NSMutableArray *)modrinthSearchResult {
    int limit = 50;

    NSMutableString *facetString = [NSMutableString new];
    [facetString appendString:@"["];
    [facetString appendFormat:@"[\"project_type:%@\"]", searchFilters[@"isModpack"].boolValue ? @"modpack" : @"mod"];
    if (searchFilters[@"mcVersion"].length > 0) {
        [facetString appendFormat:@",[\"versions:%@\"]", searchFilters[@"mcVersion"]];
    }
    if (searchFilters[@"loader"].length > 0) {
        [facetString appendFormat:@",[\"categories:%@\"]", searchFilters[@"loader"]];
    }
    [facetString appendString:@"]"];

    NSDictionary *params = @{
        @"facets": facetString,
        @"query": [searchFilters[@"name"] stringByReplacingOccurrencesOfString:@" " withString:@"+"],
        @"limit": @(limit),
        @"index": @"relevance",
        @"offset": @(modrinthSearchResult.count)
    };
    NSDictionary *response = [self getEndpoint:@"search" params:params];
    if (!response) {
        return nil;
    }

    NSMutableArray *result = modrinthSearchResult ?: [NSMutableArray new];
    for (NSDictionary *hit in response[@"hits"]) {
        BOOL isModpack = [hit[@"project_type"] isEqualToString:@"modpack"];
        [result addObject:@{
            @"apiSource": @(1), // Constant MODRINTH
            @"isModpack": @(isModpack),
            @"id": hit[@"project_id"],
            @"title": hit[@"title"],
            @"description": hit[@"description"],
            @"imageUrl": hit[@"icon_url"]
        }.mutableCopy];
    }
    self.reachedLastPage = result.count >= [response[@"total_hits"] unsignedLongValue];
    return result;
}

- (void)loadDetailsOfMod:(NSMutableDictionary *)item {
    NSArray *response = [self getEndpoint:[NSString stringWithFormat:@"project/%@/version", item[@"id"]] params:nil];
    if (![response isKindOfClass:NSArray.class]) {
        return;
    }

    NSMutableArray<NSString *> *names = [NSMutableArray new];
    NSMutableArray<NSString *> *mcNames = [NSMutableArray new];
    NSMutableArray<NSString *> *urls = [NSMutableArray new];
    NSMutableArray *hashes = [NSMutableArray new];
    NSMutableArray<NSNumber *> *sizes = [NSMutableArray new];
    NSMutableArray<NSString *> *fileNames = [NSMutableArray new];
    NSMutableArray<NSArray<NSString *> *> *gameVersions = [NSMutableArray new];
    NSMutableArray<NSArray<NSString *> *> *loaders = [NSMutableArray new];
    NSMutableArray<NSArray<NSDictionary *> *> *dependencies = [NSMutableArray new];

    for (NSDictionary *version in response) {
        NSArray<NSDictionary *> *files = version[@"files"];
        NSDictionary *file;
        for (NSDictionary *candidate in files) {
            if ([candidate[@"primary"] boolValue]) {
                file = candidate;
                break;
            }
        }
        file = file ?: files.firstObject;
        if (![file[@"url"] isKindOfClass:NSString.class]) {
            continue;
        }

        NSArray<NSString *> *versionGames = [version[@"game_versions"] isKindOfClass:NSArray.class]
            ? version[@"game_versions"] : @[];
        NSArray<NSString *> *versionLoaders = [version[@"loaders"] isKindOfClass:NSArray.class]
            ? version[@"loaders"] : @[];
        [names addObject:version[@"name"] ?: version[@"version_number"] ?: @"Unknown"];
        [mcNames addObject:versionGames.firstObject ?: @"Unknown"];
        [sizes addObject:file[@"size"] ?: @0];
        [urls addObject:file[@"url"]];
        [hashes addObject:file[@"hashes"][@"sha1"] ?: [NSNull null]];
        [fileNames addObject:file[@"filename"] ?: [NSURL URLWithString:file[@"url"]].lastPathComponent ?: @"mod.jar"];
        [gameVersions addObject:versionGames];
        [loaders addObject:versionLoaders];
        [dependencies addObject:[version[@"dependencies"] isKindOfClass:NSArray.class]
            ? version[@"dependencies"] : @[]];
    }

    item[@"versionNames"] = names;
    item[@"mcVersionNames"] = mcNames;
    item[@"versionSizes"] = sizes;
    item[@"versionUrls"] = urls;
    item[@"versionHashes"] = hashes;
    item[@"versionFileNames"] = fileNames;
    item[@"versionGameVersions"] = gameVersions;
    item[@"versionLoaders"] = loaders;
    item[@"versionDependencies"] = dependencies;
    item[@"versionDetailsLoaded"] = @(YES);
}

- (NSDictionary *)modDetailForVersion:(NSDictionary *)version projectID:(NSString *)projectID {
    NSArray<NSDictionary *> *files = version[@"files"];
    NSDictionary *file;
    for (NSDictionary *candidate in files) {
        if ([candidate[@"primary"] boolValue]) {
            file = candidate;
            break;
        }
    }
    file = file ?: files.firstObject;
    if (![file[@"url"] isKindOfClass:NSString.class]) {
        return nil;
    }
    NSArray *gameVersions = [version[@"game_versions"] isKindOfClass:NSArray.class]
        ? version[@"game_versions"] : @[];
    NSArray *loaders = [version[@"loaders"] isKindOfClass:NSArray.class]
        ? version[@"loaders"] : @[];
    NSArray *versionDependencies = [version[@"dependencies"] isKindOfClass:NSArray.class]
        ? version[@"dependencies"] : @[];
    return @{
        @"apiSource": @1,
        @"isModpack": @NO,
        @"id": projectID,
        @"title": projectID,
        @"versionNames": @[version[@"name"] ?: version[@"version_number"] ?: @"Unknown"],
        @"mcVersionNames": @[gameVersions.firstObject ?: @"Unknown"],
        @"versionSizes": @[file[@"size"] ?: @0],
        @"versionUrls": @[file[@"url"] ?: @""],
        @"versionHashes": @[file[@"hashes"][@"sha1"] ?: [NSNull null]],
        @"versionFileNames": @[file[@"filename"] ?: @"mod.jar"],
        @"versionGameVersions": @[gameVersions],
        @"versionLoaders": @[loaders],
        @"versionDependencies": @[versionDependencies]
    };
}

- (void)addRequiredDependencies:(NSArray<NSDictionary *> *)dependencies
                  gameVersions:(NSArray<NSString *> *)gameVersions
                       loaders:(NSArray<NSString *> *)loaders
                    downloader:(MinecraftResourceDownloadTask *)downloader
                       toPath:(NSString *)modsPath
                       visited:(NSMutableSet<NSString *> *)visited
                         tasks:(NSMutableArray<NSURLSessionDownloadTask *> *)tasks {
    for (NSDictionary *dependency in dependencies) {
        if (![dependency[@"dependency_type"] isEqualToString:@"required"]) {
            continue;
        }
        NSString *projectID = dependency[@"project_id"];
        if (![projectID isKindOfClass:NSString.class] || projectID.length == 0 ||
            [visited containsObject:projectID]) {
            continue;
        }
        [visited addObject:projectID];

        NSArray *versions = [self getEndpoint:[NSString stringWithFormat:@"project/%@/version", projectID] params:nil];
        if (![versions isKindOfClass:NSArray.class]) {
            [downloader finishDownloadWithErrorString:self.lastError.localizedDescription];
            return;
        }

        NSDictionary *selectedVersion;
        NSString *versionID = dependency[@"version_id"];
        for (NSDictionary *candidate in versions) {
            if ([versionID isKindOfClass:NSString.class] && [candidate[@"id"] isEqualToString:versionID]) {
                selectedVersion = candidate;
                break;
            }
            if (![versionID isKindOfClass:NSString.class] &&
                AMESharesValues(candidate[@"game_versions"], gameVersions) &&
                AMESharesValues(candidate[@"loaders"], loaders)) {
                selectedVersion = candidate;
                break;
            }
        }
        if (!selectedVersion) {
            [downloader finishDownloadWithErrorString:[NSString stringWithFormat:
                localize(@"mod.error.missing_dependency", nil), projectID]];
            return;
        }

        NSDictionary *detail = [self modDetailForVersion:selectedVersion projectID:projectID];
        if (!detail) {
            [downloader finishDownloadWithErrorString:localize(@"mod.error.invalid_download", nil)];
            return;
        }
        NSArray *dependencyTasks = [super downloader:downloader
            submitModDownloadTasksFromDetail:detail atIndex:0 toPath:modsPath];
        [tasks addObjectsFromArray:dependencyTasks];
        [self addRequiredDependencies:selectedVersion[@"dependencies"]
            gameVersions:selectedVersion[@"game_versions"]
            loaders:selectedVersion[@"loaders"]
            downloader:downloader toPath:modsPath visited:visited tasks:tasks];
        if (downloader.progress.cancelled) {
            return;
        }
    }
}

- (NSArray<NSURLSessionDownloadTask *> *)downloader:(MinecraftResourceDownloadTask *)downloader
                  submitModDownloadTasksFromDetail:(NSDictionary *)modDetail
                                           atIndex:(NSUInteger)selectedVersion
                                            toPath:(NSString *)modsPath {
    NSMutableArray<NSURLSessionDownloadTask *> *tasks = [[super downloader:downloader
        submitModDownloadTasksFromDetail:modDetail atIndex:selectedVersion toPath:modsPath] mutableCopy];
    NSMutableSet<NSString *> *visited = [NSMutableSet new];
    if ([modDetail[@"id"] isKindOfClass:NSString.class]) {
        [visited addObject:modDetail[@"id"]];
    }
    [self addRequiredDependencies:modDetail[@"versionDependencies"][selectedVersion]
        gameVersions:modDetail[@"versionGameVersions"][selectedVersion]
        loaders:modDetail[@"versionLoaders"][selectedVersion]
        downloader:downloader toPath:modsPath visited:visited tasks:tasks];
    return tasks;
}

- (void)downloader:(MinecraftResourceDownloadTask *)downloader submitDownloadTasksFromPackage:(NSString *)packagePath toPath:(NSString *)destPath {
    NSError *error;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:packagePath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to open modpack package: %@", error.localizedDescription]];
        return;
    }

    NSData *indexData = [archive extractDataFromFile:@"modrinth.index.json" error:&error];
    NSDictionary* indexDict = [NSJSONSerialization JSONObjectWithData:indexData options:kNilOptions error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to parse modrinth.index.json: %@", error.localizedDescription]];
        return;
    }

    downloader.progress.totalUnitCount = [indexDict[@"files"] count];
    for (NSDictionary *indexFile in indexDict[@"files"]) {
/*
        if ([indexFile[@"downloads"] count] > 1) {
            [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Unhandled multiple files download %@", indexFile[@"downloads"]]];
            return;
        }
*/
        NSString *url = [indexFile[@"downloads"] firstObject];
        NSString *sha = indexFile[@"hashes"][@"sha1"];
        NSString *path = [destPath stringByAppendingPathComponent:indexFile[@"path"]];
        NSUInteger size = [indexFile[@"fileSize"] unsignedLongLongValue];
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:url size:size sha:sha altName:nil toPath:path];
        if (task) {
            [downloader.fileList addObject:indexFile[@"path"]];
            [task resume];
        } else if (!downloader.progress.cancelled) {
            downloader.progress.completedUnitCount++;
        } else {
            return; // cancelled
        }
    }

    [ModpackUtils archive:archive extractDirectory:@"overrides" toPath:destPath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to extract overrides from modpack package: %@", error.localizedDescription]];
        return;
    }

    [ModpackUtils archive:archive extractDirectory:@"client-overrides" toPath:destPath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to extract client-overrides from modpack package: %@", error.localizedDescription]];
        return;
    }

    // Delete package cache
    [NSFileManager.defaultManager removeItemAtPath:packagePath error:nil];

    // Download dependency client json (if available)
    NSDictionary<NSString *, NSString *> *depInfo = [ModpackUtils infoForDependencies:indexDict[@"dependencies"]];
    if (depInfo[@"json"]) {
        NSString *jsonPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("GAME_DIR"), depInfo[@"id"]];
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:depInfo[@"json"] size:0 sha:nil altName:nil toPath:jsonPath];
        [task resume];
    }
    // TODO: automation for Forge

    // Create profile
    NSString *tmpIconPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"icon.png"];
    PLProfiles.current.profiles[indexDict[@"name"]] = @{
        @"gameDir": [NSString stringWithFormat:@"./custom_gamedir/%@", destPath.lastPathComponent],
        @"name": indexDict[@"name"],
        @"lastVersionId": depInfo[@"id"],
        @"icon": [NSString stringWithFormat:@"data:image/png;base64,%@",
            [[NSData dataWithContentsOfFile:tmpIconPath]
            base64EncodedStringWithOptions:0]]
    }.mutableCopy;
    PLProfiles.current.selectedProfileName = indexDict[@"name"];
}

@end

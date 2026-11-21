#import <CommonCrypto/CommonDigest.h>

#import "AFNetworking.h"
#import "LauncherPreferences.h"
#import "ModSiteAPI.h"
#import "utils.h"

#define kCurseForgeGameIDMinecraft 432
#define kCurseForgeClassIDMod 6
#define kModrinthBaseURL @"https://api.modrinth.com/v2"
#define kCurseForgeBaseURL @"https://api.curseforge.com/v1"
#define kModrinthUserAgent @"Amethyst-iOS-ModBrowser/1.0 (https://github.com/AngelAuraMC/Amethyst-iOS)"

static NSError *ModSiteError(NSString *message) {
    return [NSError errorWithDomain:@"ModSiteAPI"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

// JSON nulls and unexpected types must never end up in the dictionaries that the
// UI displays, otherwise -[NSNull length] crashes at runtime.
static NSString *ModSiteString(id value, NSString *fallback) {
    if ([value isKindOfClass:NSString.class] && ([value length] > 0 || fallback == nil)) {
        return value;
    }
    return fallback ?: @"";
}

static BOOL ModSiteVerifySHA1(NSString *expected, NSString *path) {
    if (expected.length == 0) {
        return YES;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        return NO;
    }
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *localSHA = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [localSHA appendFormat:@"%02x", digest[i]];
    }
    return [expected.lowercaseString isEqualToString:localSHA];
}

@implementation ModSiteAPI

+ (NSArray<NSString *> *)sourceNames {
    return @[@"Modrinth", @"CurseForge"];
}

+ (instancetype)apiForSourceName:(NSString *)sourceName {
    if ([sourceName isEqualToString:@"CurseForge"]) {
        return [CurseForgeSiteAPI new];
    }
    return [ModrinthSiteAPI new];
}

- (NSString *)sourceName {
    return @"";
}

- (BOOL)isAvailable {
    return YES;
}

- (NSString *)unavailableReason {
    return nil;
}

- (NSArray<NSDictionary *> *)searchQuery:(NSString *)query
                             gameVersion:(NSString *)gameVersion
                                  loader:(NSString *)loader
                                  offset:(NSUInteger)offset {
    return nil;
}

- (NSArray<NSDictionary *> *)versionsForProject:(NSDictionary *)project
                                    gameVersion:(NSString *)gameVersion
                                         loader:(NSString *)loader {
    return nil;
}

#pragma mark - CurseForge API key

+ (NSString *)curseForgeAPIKey {
    id key = getPrefObject(@"mods.curseforge_api_key");
    return [key isKindOfClass:NSString.class] ? key : @"";
}

+ (void)setCurseForgeAPIKey:(NSString *)key {
    setPrefObject(@"mods.curseforge_api_key", key ?: @"");
}

#pragma mark - Networking helpers

- (id)GET:(NSString *)endpoint
      base:(NSString *)base
    params:(NSDictionary *)params
   headers:(NSDictionary *)headers {
    __block id result = nil;
    __block NSError *requestError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.responseSerializer = [AFJSONResponseSerializer serializer];
    manager.responseSerializer.acceptableContentTypes =
        [NSSet setWithObjects:@"application/json", @"text/json", @"text/plain", nil];
    manager.requestSerializer.timeoutInterval = 30;

    NSMutableDictionary *allHeaders = [headers mutableCopy] ?: [NSMutableDictionary new];
    if (allHeaders[@"User-Agent"] == nil) {
        allHeaders[@"User-Agent"] = kModrinthUserAgent;
    }
    allHeaders[@"Accept"] = allHeaders[@"Accept"] ?: @"application/json";
    for (NSString *key in allHeaders) {
        [manager.requestSerializer setValue:allHeaders[key] forHTTPHeaderField:key];
    }

    NSString *url = [base stringByAppendingPathComponent:endpoint];
    [manager GET:url parameters:params headers:nil progress:nil
    success:^(NSURLSessionTask *task, id responseObject) {
        result = responseObject;
        dispatch_semaphore_signal(semaphore);
    } failure:^(NSURLSessionTask *task, NSError *error) {
        requestError = error;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (requestError != nil) {
        NSLog(@"[Mods] Request to %@ failed: %@", url, requestError.localizedDescription);
        self.lastError = requestError;
    }
    return result;
}

+ (void)downloadURL:(NSString *)urlString
             toPath:(NSString *)path
               sha1:(NSString *)sha1
           progress:(void (^)(double fraction))progress
         completion:(void (^)(NSError *error))completion {
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (url == nil || url.scheme.length == 0) {
        completion(ModSiteError(localize(@"mods.error.bad_url", nil)));
        return;
    }

    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 120;
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];

    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    __block NSURLSessionDownloadTask *task = nil;
    task = [manager downloadTaskWithRequest:request
    progress:^(NSProgress *downloadProgress) {
        if (progress != nil) {
            progress(downloadProgress.fractionCompleted);
        }
    }
    destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        return [NSURL fileURLWithPath:path];
    }
    completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        if (error != nil) {
            completion(error);
            return;
        }
        if (!ModSiteVerifySHA1(sha1, path)) {
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            completion(ModSiteError(localize(@"mods.error.checksum", nil)));
            return;
        }
        completion(nil);
    }];
    [task resume];
}

@end

#pragma mark - Modrinth

@implementation ModrinthSiteAPI

- (NSString *)sourceName {
    return @"Modrinth";
}

- (NSArray<NSDictionary *> *)searchQuery:(NSString *)query
                             gameVersion:(NSString *)gameVersion
                                  loader:(NSString *)loader
                                  offset:(NSUInteger)offset {
    NSMutableString *facets = [NSMutableString stringWithString:@"[[\"project_type:mod\"]"];
    if (gameVersion.length > 0) {
        [facets appendFormat:@",[\"versions:%@\"]", gameVersion];
    }
    if (loader.length > 0 && ![loader isEqualToString:@"vanilla"]) {
        [facets appendFormat:@",[\"categories:%@\"]", loader];
    }
    [facets appendString:@"]"];

    NSDictionary *params = @{
        @"query": query.length > 0 ? query : @"",
        @"facets": facets,
        @"limit": @(20),
        @"index": @"relevance",
        @"offset": @(offset)
    };

    id response = [self GET:@"search" base:kModrinthBaseURL params:params headers:nil];
    if (![response isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSMutableArray<NSDictionary *> *projects = [NSMutableArray new];
    for (NSDictionary *hit in response[@"hits"]) {
        if (![hit isKindOfClass:NSDictionary.class]) {
            continue;
        }
        [projects addObject:@{
            @"id": ModSiteString(hit[@"project_id"], @""),
            @"title": ModSiteString(hit[@"title"], @""),
            @"summary": ModSiteString(hit[@"description"], @""),
            @"iconURL": ModSiteString(hit[@"icon_url"], @""),
            @"author": ModSiteString(hit[@"author"], @""),
            @"downloads": [hit[@"downloads"] isKindOfClass:NSNumber.class] ? hit[@"downloads"] : @0
        }.mutableCopy];
    }

    NSUInteger total = [response[@"total_hits"] unsignedIntegerValue];
    self.reachedLastPage = (offset + projects.count) >= total;
    return projects;
}

- (NSArray<NSDictionary *> *)versionsForProject:(NSDictionary *)project
                                    gameVersion:(NSString *)gameVersion
                                         loader:(NSString *)loader {
    NSMutableDictionary *params = [NSMutableDictionary new];
    if (gameVersion.length > 0) {
        params[@"game_versions"] = [NSString stringWithFormat:@"[\"%@\"]", gameVersion];
    }
    if (loader.length > 0 && ![loader isEqualToString:@"vanilla"]) {
        params[@"loaders"] = [NSString stringWithFormat:@"[\"%@\"]", loader];
    }

    NSString *projectId = project[@"id"];
    if (![projectId isKindOfClass:NSString.class] || projectId.length == 0) {
        self.lastError = ModSiteError(localize(@"mods.error.missing_project", nil));
        return nil;
    }

    id response = [self GET:[NSString stringWithFormat:@"project/%@/version", projectId]
        base:kModrinthBaseURL params:params headers:nil];
    if (![response isKindOfClass:NSArray.class]) {
        return nil;
    }

    NSMutableArray<NSDictionary *> *files = [NSMutableArray new];
    for (NSDictionary *version in response) {
        if (![version isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSArray *versionFiles = version[@"files"];
        NSDictionary *chosen = nil;
        for (NSDictionary *candidate in versionFiles) {
            if ([candidate[@"primary"] boolValue]) {
                chosen = candidate;
                break;
            }
        }
        if (chosen == nil) {
            chosen = versionFiles.firstObject;
        }
        if (chosen == nil || ![chosen[@"url"] isKindOfClass:NSString.class] || [chosen[@"url"] length] == 0) {
            continue;
        }
        NSString *fileName = ModSiteString(chosen[@"filename"], @"");
        [files addObject:@{
            @"name": ModSiteString(version[@"name"], fileName),
            @"filename": fileName,
            @"url": ModSiteString(chosen[@"url"], @""),
            @"size": [chosen[@"size"] isKindOfClass:NSNumber.class] ? chosen[@"size"] : @0,
            @"sha1": ModSiteString(chosen[@"hashes"][@"sha1"], @""),
            @"gameVersions": [version[@"game_versions"] isKindOfClass:NSArray.class] ? version[@"game_versions"] : @[],
            @"loaders": [version[@"loaders"] isKindOfClass:NSArray.class] ? version[@"loaders"] : @[]
        }.mutableCopy];
    }
    return files;
}

@end

#pragma mark - CurseForge

@implementation CurseForgeSiteAPI

- (NSString *)sourceName {
    return @"CurseForge";
}

- (NSString *)apiKey {
    return [ModSiteAPI curseForgeAPIKey];
}

- (BOOL)isAvailable {
    return self.apiKey.length > 0;
}

- (NSString *)unavailableReason {
    return localize(@"mods.error.curseforge_key", nil);
}

- (NSDictionary *)headers {
    return @{@"x-api-key": self.apiKey ?: @"", @"Accept": @"application/json"};
}

// Forge=1, Fabric=4, Quilt=5, NeoForge=6
- (NSNumber *)loaderTypeForLoader:(NSString *)loader {
    if ([loader isEqualToString:@"forge"]) return @1;
    if ([loader isEqualToString:@"fabric"]) return @4;
    if ([loader isEqualToString:@"quilt"]) return @5;
    if ([loader isEqualToString:@"neoforge"]) return @6;
    return nil;
}

- (NSArray<NSDictionary *> *)searchQuery:(NSString *)query
                             gameVersion:(NSString *)gameVersion
                                  loader:(NSString *)loader
                                  offset:(NSUInteger)offset {
    if (!self.isAvailable) {
        self.lastError = ModSiteError(self.unavailableReason);
        return nil;
    }

    NSMutableDictionary *params = @{
        @"gameId": @(kCurseForgeGameIDMinecraft),
        @"classId": @(kCurseForgeClassIDMod),
        @"searchFilter": query.length > 0 ? query : @"",
        @"index": @(offset),
        @"pageSize": @(20),
        @"sortField": @2, // popular
        @"sortOrder": @"desc"
    }.mutableCopy;
    if (gameVersion.length > 0) {
        params[@"gameVersion"] = gameVersion;
    }
    NSNumber *loaderType = [self loaderTypeForLoader:loader];
    if (loaderType != nil) {
        params[@"modLoaderType"] = loaderType;
    }

    id response = [self GET:@"mods/search" base:kCurseForgeBaseURL params:params headers:[self headers]];
    if (![response isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSMutableArray<NSDictionary *> *projects = [NSMutableArray new];
    for (NSDictionary *item in response[@"data"]) {
        if (![item isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSDictionary *logo = [item[@"logo"] isKindOfClass:NSDictionary.class] ? item[@"logo"] : nil;
        NSArray *authors = [item[@"authors"] isKindOfClass:NSArray.class] ? item[@"authors"] : nil;
        NSString *author = authors.count > 0 && [authors[0] isKindOfClass:NSDictionary.class]
            ? ModSiteString(authors[0][@"name"], @"") : @"";
        [projects addObject:@{
            @"id": [item[@"id"] isKindOfClass:NSNumber.class] ? item[@"id"] : @0,
            @"title": ModSiteString(item[@"name"], @""),
            @"summary": ModSiteString(item[@"summary"], @""),
            @"iconURL": ModSiteString(logo[@"thumbnailUrl"], ModSiteString(logo[@"url"], @"")),
            @"author": author,
            @"downloads": [item[@"downloadCount"] isKindOfClass:NSNumber.class] ? item[@"downloadCount"] : @0
        }.mutableCopy];
    }

    NSDictionary *pagination = response[@"pagination"];
    NSUInteger total = [pagination[@"totalCount"] unsignedIntegerValue];
    self.reachedLastPage = total > 0 ? (offset + projects.count) >= total : projects.count < 20;
    return projects;
}

- (NSArray<NSDictionary *> *)versionsForProject:(NSDictionary *)project
                                    gameVersion:(NSString *)gameVersion
                                         loader:(NSString *)loader {
    if (!self.isAvailable) {
        self.lastError = ModSiteError(self.unavailableReason);
        return nil;
    }

    NSMutableDictionary *params = @{@"pageSize": @(50), @"index": @(0)}.mutableCopy;
    if (gameVersion.length > 0) {
        params[@"gameVersion"] = gameVersion;
    }
    NSNumber *loaderType = [self loaderTypeForLoader:loader];
    if (loaderType != nil) {
        params[@"modLoaderType"] = loaderType;
    }

    NSString *projectId = [project[@"id"] description];
    id response = [self GET:[NSString stringWithFormat:@"mods/%@/files", projectId]
        base:kCurseForgeBaseURL params:params headers:[self headers]];
    if (![response isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSMutableArray<NSDictionary *> *files = [NSMutableArray new];
    for (NSDictionary *file in response[@"data"]) {
        if (![file isKindOfClass:NSDictionary.class]) {
            continue;
        }
        unsigned long long fileId = [file[@"id"] unsignedLongLongValue];
        NSString *fileName = ModSiteString(file[@"fileName"], @"");
        NSString *url = file[@"downloadUrl"];
        if (![url isKindOfClass:NSString.class] || url.length == 0) {
            // Authors may disable third party downloads; the CDN link still works.
            url = [NSString stringWithFormat:@"https://edge.forgecdn.net/files/%llu/%llu/%@",
                fileId / 1000, fileId % 1000, fileName];
        }
        NSString *sha1 = @"";
        for (NSDictionary *hash in file[@"hashes"]) {
            // algo 1 = SHA1
            if ([hash[@"algo"] intValue] == 1) {
                sha1 = ModSiteString(hash[@"value"], @"");
                break;
            }
        }
        NSArray *gameVersions = [file[@"gameVersions"] isKindOfClass:NSArray.class] ? file[@"gameVersions"] : @[];
        [files addObject:@{
            @"name": ModSiteString(file[@"displayName"], fileName),
            @"filename": fileName,
            @"url": ModSiteString(url, @""),
            @"size": [file[@"fileLength"] isKindOfClass:NSNumber.class] ? file[@"fileLength"] : @0,
            @"sha1": sha1,
            @"gameVersions": gameVersions,
            @"loaders": @[]
        }.mutableCopy];
    }
    return files;
}

@end

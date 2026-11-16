#import "AFNetworking.h"
#import "MinecraftResourceDownloadTask.h"
#import "ModpackAPI.h"
#import "utils.h"

@implementation ModpackAPI

#pragma mark Interface methods

- (instancetype)initWithURL:(NSString *)url {
    self = [super init];
    self.baseURL = url;
    return self;
}

- (void)loadDetailsOfMod:(NSMutableDictionary *)item {
    [self doesNotRecognizeSelector:_cmd];
}

- (NSMutableArray *)searchModWithFilters:(NSDictionary<NSString *, NSString *> *)searchFilters previousPageResult:(NSMutableArray *)prevResult {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (void)downloader:(MinecraftResourceDownloadTask *)downloader submitDownloadTasksFromPackage:(NSString *)packagePath toPath:(NSString *)destPath {
    [self doesNotRecognizeSelector:_cmd];
}

- (id)getEndpoint:(NSString *)endpoint params:(NSDictionary *)params {
    __block id result;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    NSString *url = [self.baseURL stringByAppendingPathComponent:endpoint];
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    [manager GET:url parameters:params headers:nil progress:nil
    success:^(NSURLSessionTask *task, id obj) {
        result = obj;
        dispatch_group_leave(group);
    } failure:^(NSURLSessionTask *operation, NSError *error) {
        self.lastError = error;
        dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    //NSLog(@"%@", result);
    return result;
}

- (void)installModpackFromDetail:(NSDictionary *)modDetail atIndex:(NSUInteger)selectedVersion {
    // Pass details to LauncherNavigationController
    NSDictionary* userInfo = @{
        @"detail": modDetail,
        @"index": @(selectedVersion)
    };
    [NSNotificationCenter.defaultCenter
        postNotificationName:@"InstallModpack"
        object:self userInfo:userInfo];
}

- (void)installModFromDetail:(NSDictionary *)modDetail atIndex:(NSUInteger)selectedVersion {
    [NSNotificationCenter.defaultCenter
        postNotificationName:@"InstallMod"
        object:self
        userInfo:@{
            @"detail": modDetail,
            @"index": @(selectedVersion)
        }];
}

- (NSArray<NSURLSessionDownloadTask *> *)downloader:(MinecraftResourceDownloadTask *)downloader
                  submitModDownloadTasksFromDetail:(NSDictionary *)modDetail
                                           atIndex:(NSUInteger)selectedVersion
                                            toPath:(NSString *)modsPath {
    NSString *url = modDetail[@"versionUrls"][selectedVersion];
    if (![url isKindOfClass:NSString.class] || url.length == 0) {
        [downloader finishDownloadWithErrorString:localize(@"mod.error.invalid_download", nil)];
        return @[];
    }
    NSString *sha = modDetail[@"versionHashes"][selectedVersion];
    if ([sha isKindOfClass:NSNull.class]) {
        sha = nil;
    }
    NSUInteger size = [modDetail[@"versionSizes"][selectedVersion] unsignedLongLongValue];
    NSString *fileName = modDetail[@"versionFileNames"][selectedVersion];
    if (![fileName isKindOfClass:NSString.class] || fileName.length == 0) {
        fileName = [NSString stringWithFormat:@"%@-%@.jar", modDetail[@"id"], modDetail[@"versionNames"][selectedVersion]];
    }
    fileName = fileName.lastPathComponent;
    NSString *path = [modsPath stringByAppendingPathComponent:fileName];
    NSURLSessionDownloadTask *task = [downloader createModDownloadTask:url size:size sha:sha altName:nil toPath:path];
    return task ? @[task] : @[];
}

@end

#import <Foundation/Foundation.h>

// Abstraction over the mod hosting sites supported by the launcher.
// Modrinth works out of the box; CurseForge requires a personal API key that
// the user can paste in the mod browser.
@interface ModSiteAPI : NSObject

@property(nonatomic, readonly) NSString *sourceName;
@property(nonatomic) NSError *lastError;
@property(nonatomic) BOOL reachedLastPage;

+ (NSArray<NSString *> *)sourceNames;
+ (instancetype)apiForSourceName:(NSString *)sourceName;

- (BOOL)isAvailable;
- (NSString *)unavailableReason;

// Both methods block until the request finishes; call them from a background
// queue. They return nil on error (see lastError).
// Project dictionary: id, title, summary, iconURL, author, downloads.
- (NSArray<NSDictionary *> *)searchQuery:(NSString *)query
                             gameVersion:(NSString *)gameVersion
                                  loader:(NSString *)loader
                                  offset:(NSUInteger)offset;

// File dictionary: name, filename, url, size, sha1, gameVersions, loaders.
- (NSArray<NSDictionary *> *)versionsForProject:(NSDictionary *)project
                                    gameVersion:(NSString *)gameVersion
                                         loader:(NSString *)loader;

// CurseForge specific; ignored by other sites.
+ (NSString *)curseForgeAPIKey;
+ (void)setCurseForgeAPIKey:(NSString *)key;

+ (void)downloadURL:(NSString *)urlString
             toPath:(NSString *)path
               sha1:(NSString *)sha1
           progress:(void (^)(double fraction))progress
         completion:(void (^)(NSError *error))completion;

@end

@interface ModrinthSiteAPI : ModSiteAPI
@end

@interface CurseForgeSiteAPI : ModSiteAPI
@end

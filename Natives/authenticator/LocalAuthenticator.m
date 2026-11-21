#import <CommonCrypto/CommonDigest.h>
#import "BaseAuthenticator.h"

@interface LocalAuthenticator ()
+ (NSString *)offlineUUIDForUsername:(NSString *)username;
@end

@implementation LocalAuthenticator

// Minecraft derives the UUID of offline players with
// java.util.UUID.nameUUIDFromBytes("OfflinePlayer:<name>".getBytes(UTF_8)),
// which is a name based (version 3, MD5) UUID. Using the same value keeps
// singleplayer world data and offline-mode server identities consistent with
// the official behaviour, instead of the all-zero UUID used before.
+ (NSString *)offlineUUIDForUsername:(NSString *)username {
    NSString *name = username.length > 0 ? username : @"";
    NSString *seed = [@"OfflinePlayer:" stringByAppendingString:name];
    NSData *seedData = [seed dataUsingEncoding:NSUTF8StringEncoding];

    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(seedData.bytes, (CC_LONG)seedData.length, digest);

    // Set the version (3) and the IETF variant bits.
    digest[6] = (unsigned char)((digest[6] & 0x0F) | 0x30);
    digest[8] = (unsigned char)((digest[8] & 0x3F) | 0x80);

    return [NSString stringWithFormat:
        @"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        digest[0], digest[1], digest[2], digest[3],
        digest[4], digest[5], digest[6], digest[7],
        digest[8], digest[9], digest[10], digest[11],
        digest[12], digest[13], digest[14], digest[15]];
}

- (void)loginWithCallback:(Callback)callback {
    NSString *username = self.authData[@"input"] ?: self.authData[@"username"];

    self.authData[@"oldusername"] = self.authData[@"username"] = username;
    self.authData[@"profileId"] = [[self class] offlineUUIDForUsername:username];
    self.authData[@"accessToken"] = @"0";
    if (self.authData[@"clientToken"] == nil) {
        self.authData[@"clientToken"] = [[NSUUID UUID] UUIDString];
    }
    // Local accounts never expire: the absence of "expiresAt" is what marks the
    // account as local when it is loaded again.
    [self.authData removeObjectForKey:@"expiresAt"];

    callback(nil, [super saveChanges]);
}

- (void)refreshTokenWithCallback:(Callback)callback {
    // Migrate accounts created by older builds (all-zero UUID) so that offline
    // servers and world data keep a stable player identity.
    NSString *profileId = self.authData[@"profileId"];
    if (profileId.length == 0 || [profileId hasPrefix:@"00000000-0000-0000-0000-000000000000"]) {
        self.authData[@"profileId"] = [[self class] offlineUUIDForUsername:self.authData[@"username"]];
        if (self.authData[@"accessToken"] == nil) {
            self.authData[@"accessToken"] = @"0";
        }
        [super saveChanges];
    }
    callback(nil, YES);
}

@end

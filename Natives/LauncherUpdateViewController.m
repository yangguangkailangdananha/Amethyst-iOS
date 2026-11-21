#import "LauncherUpdateViewController.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "ios_uikit_bridge.h"
#import "utils.h"

// Public release feed. The build workflow publishes the IPA/TIPA here.
static NSString *const kUpdateRepo = @"yangguangkailangdananha/amethyst-ios-builder";
static NSString *const kUpdateAPI = @"https://api.github.com/repos/%@/releases/latest";

@interface LauncherUpdateViewController () <NSURLSessionDownloadDelegate>
@property(nonatomic, strong) UILabel *currentVersionLabel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UITextView *notesView;
@property(nonatomic, strong) UIProgressView *progressView;
@property(nonatomic, strong) UIButton *checkButton;
@property(nonatomic, strong) UIButton *downloadButton;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, copy) NSString *latestTag;
@property(nonatomic, copy) NSString *latestAssetName;
@property(nonatomic, strong) NSURL *latestAssetURL;
@property(nonatomic, strong) NSString *downloadedPath;
@end

@implementation LauncherUpdateViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"update.title", nil);
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40],
    ]];

    NSString *current = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"1.0";
    self.currentVersionLabel = [self labelWithText:[NSString stringWithFormat:localize(@"update.current", nil), current]];
    self.currentVersionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [stack addArrangedSubview:self.currentVersionLabel];

    self.statusLabel = [self labelWithText:localize(@"update.idle", nil)];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:self.statusLabel];

    self.notesView = [[UITextView alloc] init];
    self.notesView.editable = NO;
    self.notesView.scrollEnabled = NO;
    self.notesView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.notesView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.notesView.layer.cornerRadius = 8;
    self.notesView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    self.notesView.hidden = YES;
    [stack addArrangedSubview:self.notesView];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.hidden = YES;
    [stack addArrangedSubview:self.progressView];

    self.checkButton = [self buttonWithTitle:localize(@"update.check", nil) action:@selector(checkForUpdates)];
    [stack addArrangedSubview:self.checkButton];

    self.downloadButton = [self buttonWithTitle:localize(@"update.download", nil) action:@selector(downloadUpdate)];
    self.downloadButton.hidden = YES;
    [stack addArrangedSubview:self.downloadButton];

    UILabel *hint = [self labelWithText:localize(@"update.hint", nil)];
    hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    hint.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:hint];

    self.session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration
                                                delegate:self
                                           delegateQueue:NSOperationQueue.mainQueue];
    [self checkForUpdates];
}

- (void)dealloc {
    [self.session invalidateAndCancel];
}

- (UILabel *)labelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 10;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 16, 12, 16);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)setStatus:(NSString *)status {
    self.statusLabel.text = status;
}

static NSComparisonResult compareVersions(NSString *a, NSString *b) {
    NSArray *pa = [a componentsSeparatedByString:@"."];
    NSArray *pb = [b componentsSeparatedByString:@"."];
    NSUInteger n = MAX(pa.count, pb.count);
    for (NSUInteger i = 0; i < n; i++) {
        long va = i < pa.count ? [(NSString *)pa[i] longLongValue] : 0;
        long vb = i < pb.count ? [(NSString *)pb[i] longLongValue] : 0;
        if (va < vb) return NSOrderedAscending;
        if (va > vb) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (void)checkForUpdates {
    self.downloadButton.hidden = YES;
    self.notesView.hidden = YES;
    self.progressView.hidden = YES;
    [self setStatus:localize(@"update.checking", nil)];

    NSString *urlString = [NSString stringWithFormat:kUpdateAPI, kUpdateRepo];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"Amethyst-iOS" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 20;

    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [self setStatus:[NSString stringWithFormat:localize(@"update.error", nil), error.localizedDescription]];
            return;
        }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode == 404) {
            [self setStatus:localize(@"update.none", nil)];
            return;
        }
        if (http.statusCode != 200 || data.length == 0) {
            [self setStatus:[NSString stringWithFormat:localize(@"update.error", nil),
                             [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode]]];
            return;
        }
        NSError *jsonError = nil;
        NSDictionary *release = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || ![release isKindOfClass:NSDictionary.class]) {
            [self setStatus:[NSString stringWithFormat:localize(@"update.error", nil), jsonError.localizedDescription ?: @"JSON"]];
            return;
        }
        NSString *tag = release[@"tag_name"] ?: @"";
        NSString *version = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
        NSString *current = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"1.0";
        if (version.length == 0) {
            [self setStatus:localize(@"update.none", nil)];
            return;
        }
        if (compareVersions(version, current) != NSOrderedDescending) {
            [self setStatus:[NSString stringWithFormat:localize(@"update.latest", nil), version]];
            return;
        }

        NSArray *assets = release[@"assets"];
        NSDictionary *chosen = nil;
        for (NSDictionary *asset in assets) {
            NSString *name = asset[@"name"];
            if ([name hasSuffix:@".tipa"] || [name hasSuffix:@".ipa"]) {
                chosen = asset;
                if ([name containsString:@"trollstore"] || [name hasSuffix:@".tipa"]) {
                    break;
                }
            }
        }
        if (!chosen) {
            [self setStatus:localize(@"update.noasset", nil)];
            return;
        }

        self.latestTag = tag;
        self.latestAssetName = chosen[@"name"];
        self.latestAssetURL = [NSURL URLWithString:chosen[@"browser_download_url"]];
        [self setStatus:[NSString stringWithFormat:localize(@"update.available", nil), version, chosen[@"name"]]];
        NSString *notes = release[@"body"] ?: @"";
        self.notesView.text = notes;
        self.notesView.hidden = notes.length == 0;
        self.downloadButton.hidden = NO;
    }] resume];
}

- (void)downloadUpdate {
    if (!self.latestAssetURL) {
        return;
    }
    self.downloadButton.enabled = NO;
    self.progressView.hidden = NO;
    self.progressView.progress = 0;
    [self setStatus:[NSString stringWithFormat:localize(@"update.downloading", nil), self.latestAssetName]];
    [[self.session downloadTaskWithURL:self.latestAssetURL] resume];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressView.progress = (float)((double)totalBytesWritten / (double)totalBytesExpectedToWrite);
        });
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [documents stringByAppendingPathComponent:@"Updates"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *dest = [dir stringByAppendingPathComponent:self.latestAssetName];
    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
    NSError *error = nil;
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:dest] error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.downloadButton.enabled = YES;
        self.progressView.hidden = YES;
        if (error) {
            [self setStatus:[NSString stringWithFormat:localize(@"update.error", nil), error.localizedDescription]];
            return;
        }
        self.downloadedPath = dest;
        [self setStatus:[NSString stringWithFormat:localize(@"update.downloaded", nil), dest.lastPathComponent]];
        [self presentInstallOptions];
    });
}

- (void)presentInstallOptions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"update.install_title", nil)
                                                                   message:localize(@"update.install_message", nil)
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"update.install_trollstore", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        NSString *remote = self.latestAssetURL.absoluteString;
        NSString *scheme = [NSString stringWithFormat:@"apple-magnifier://install?url=%@",
                            [remote stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:scheme] options:@{} completionHandler:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"update.share_file", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        UIActivityViewController *share = [[UIActivityViewController alloc]
                                           initWithActivityItems:@[[NSURL fileURLWithPath:self.downloadedPath]]
                                           applicationActivities:nil];
        share.popoverPresentationController.sourceView = self.view;
        share.popoverPresentationController.sourceRect = self.view.bounds;
        [self presentViewController:share animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.downloadButton.enabled = YES;
            self.progressView.hidden = YES;
            [self setStatus:[NSString stringWithFormat:localize(@"update.error", nil), error.localizedDescription]];
        });
    }
}

- (NSString *)imageName {
    return @"square.and.arrow.down";
}

@end

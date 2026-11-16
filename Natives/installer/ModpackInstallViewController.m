#import "AFNetworking.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "MinecraftResourceDownloadTask.h"
#import "ModpackInstallViewController.h"
#import "PLProfiles.h"
#import "UIKit+AFNetworking.h"
#import "UIKit+hook.h"
#import "WFWorkflowProgressView.h"
#import "modpack/ModrinthAPI.h"
#import "config.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#include <dlfcn.h>

#define kCurseForgeGameIDMinecraft 432
#define kCurseForgeClassIDModpack 4471
#define kCurseForgeClassIDMod 6

@interface ModpackInstallViewController()<UIContextMenuInteractionDelegate, UIDocumentPickerDelegate>
@property(nonatomic) UISearchController *searchController;
@property(nonatomic) UIMenu *currentMenu;
@property(nonatomic) NSMutableArray *list;
@property(nonatomic) NSMutableDictionary *filters;
@property ModrinthAPI *modrinth;
@end

@implementation ModpackInstallViewController

- (instancetype)init {
    return [self initWithIndividualMods:NO];
}

- (instancetype)initWithIndividualMods:(BOOL)individualMods {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _individualMods = individualMods;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = localize(self.individualMods ? @"mod.browser.title" : @"modpack.browser.title", nil);
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = localize(self.individualMods
        ? @"mod.browser.search" : @"modpack.browser.search", nil);
    self.navigationItem.searchController = self.searchController;
    self.modrinth = [ModrinthAPI new];
    self.filters = @{
        @"isModpack": @(!self.individualMods),
        @"name": @" "
    }.mutableCopy;
    if (self.individualMods) {
        NSString *mcVersion = [self selectedMinecraftVersion];
        NSString *loader = [self selectedModLoader];
        if (mcVersion.length > 0) {
            self.filters[@"mcVersion"] = mcVersion;
        }
        if (loader.length > 0) {
            self.filters[@"loader"] = loader;
        }
    }
    [self switchToReadyState];
    [self updateSearchResults];
}

- (NSString *)selectedMinecraftVersion {
    NSString *versionID = PLProfiles.current.selectedProfile[@"lastVersionId"];
    if ([versionID isEqualToString:@"latest-release"]) {
        return getPrefObject(@"internal.latest_version.release");
    } else if ([versionID isEqualToString:@"latest-snapshot"]) {
        return getPrefObject(@"internal.latest_version.snapshot");
    }
    NSString *metadataPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("GAME_DIR"), versionID];
    NSDictionary *metadata = parseJSONFromFile(metadataPath);
    if ([metadata[@"inheritsFrom"] isKindOfClass:NSString.class]) {
        return metadata[@"inheritsFrom"];
    }
    if (metadata[@"NSErrorObject"] &&
        ([versionID containsString:@"fabric"] || [versionID containsString:@"quilt"] ||
         [versionID containsString:@"forge"] || [versionID containsString:@"neoforge"])) {
        return nil;
    }
    return versionID;
}

- (NSString *)selectedModLoader {
    NSString *originalVersionID = PLProfiles.current.selectedProfile[@"lastVersionId"];
    NSString *versionID = originalVersionID.lowercaseString;
    NSString *metadataPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("GAME_DIR"), originalVersionID];
    NSDictionary *metadata = parseJSONFromFile(metadataPath);
    NSString *metadataID = [metadata[@"id"] isKindOfClass:NSString.class]
        ? [metadata[@"id"] lowercaseString] : versionID;
    if ([metadataID containsString:@"neoforge"]) return @"neoforge";
    if ([metadataID containsString:@"fabric"]) return @"fabric";
    if ([metadataID containsString:@"quilt"]) return @"quilt";
    if ([metadataID containsString:@"forge"]) return @"forge";
    return nil;
}

- (void)loadSearchResultsWithPrevList:(BOOL)prevList {
    NSString *name = self.searchController.searchBar.text;
    if (!prevList && [self.filters[@"name"] isEqualToString:name]) {
        return;
    }

    [self switchToLoadingState];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        self.filters[@"name"] = name;
        self.list = [self.modrinth searchModWithFilters:self.filters previousPageResult:prevList ? self.list : nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.list) {
                [self switchToReadyState];
                [self.tableView reloadData];
            } else {
                showDialog(localize(@"Error", nil), self.modrinth.lastError.localizedDescription);
                [self actionClose];
            }
        });
    });
}

- (void)updateSearchResults {
    [self loadSearchResultsWithPrevList:NO];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateSearchResults) object:nil];
    [self performSelector:@selector(updateSearchResults) withObject:nil afterDelay:0.5];
}

- (void)actionClose {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)switchToLoadingState {
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.navigationItem.rightBarButtonItems = @[[[UIBarButtonItem alloc] initWithCustomView:indicator]];
    [indicator startAnimating];
    self.navigationController.modalInPresentation = YES;
    self.tableView.allowsSelection = NO;
}

- (void)switchToReadyState {
    UIBarButtonItem *currentItem = self.navigationItem.rightBarButtonItems.firstObject;
    if ([currentItem.customView isKindOfClass:UIActivityIndicatorView.class]) {
        [(UIActivityIndicatorView *)currentItem.customView stopAnimating];
    }
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
        target:self action:@selector(actionClose)];
    if (self.individualMods) {
        UIBarButtonItem *importItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"mod.action.import", nil)
            style:UIBarButtonItemStylePlain target:self action:@selector(actionImportLocalMod)];
        self.navigationItem.rightBarButtonItems = @[closeItem, importItem];
    } else {
        self.navigationItem.rightBarButtonItems = @[closeItem];
    }
    self.navigationController.modalInPresentation = NO;
    self.tableView.allowsSelection = YES;
}

#pragma mark Local mod import

- (void)actionImportLocalMod {
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[[UTType typeWithMIMEType:@"application/java-archive"]] asCopy:YES];
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self importLocalModsAtURLs:urls];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self importLocalModsAtURLs:@[url]];
}

- (void)importLocalModsAtURLs:(NSArray<NSURL *> *)urls {
    NSString *modsPath = [MinecraftResourceDownloadTask modsDirectoryForSelectedProfile];
    NSError *error;
    if (![NSFileManager.defaultManager createDirectoryAtPath:modsPath
        withIntermediateDirectories:YES attributes:nil error:&error]) {
        showDialog(localize(@"Error", nil), error.localizedDescription);
        return;
    }

    NSUInteger imported = 0;
    NSUInteger skipped = 0;
    NSMutableArray<NSString *> *errors = [NSMutableArray new];
    for (NSURL *url in urls) {
        NSString *fileName = url.lastPathComponent;
        if (![fileName.pathExtension.lowercaseString isEqualToString:@"jar"]) {
            skipped++;
            continue;
        }
        NSString *destination = [modsPath stringByAppendingPathComponent:fileName];
        if ([NSFileManager.defaultManager fileExistsAtPath:destination]) {
            skipped++;
            continue;
        }

        BOOL accessing = [url startAccessingSecurityScopedResource];
        BOOL copied = [NSFileManager.defaultManager copyItemAtURL:url
            toURL:[NSURL fileURLWithPath:destination] error:&error];
        if (accessing) {
            [url stopAccessingSecurityScopedResource];
        }
        if (copied) {
            imported++;
        } else {
            [errors addObject:[NSString stringWithFormat:@"%@: %@", fileName, error.localizedDescription]];
        }
    }

    NSMutableArray<NSString *> *messages = [NSMutableArray new];
    if (imported > 0) {
        [messages addObject:[NSString stringWithFormat:localize(@"mod.import.success", nil), imported]];
    }
    if (skipped > 0) {
        [messages addObject:[NSString stringWithFormat:localize(@"mod.import.skipped", nil), skipped]];
    }
    [messages addObjectsFromArray:errors];
    showDialog(localize(@"mod.action.import", nil), [messages componentsJoinedByString:@"\n"]);
}

#pragma mark UIContextMenu

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location
{
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        return self.currentMenu;
    }];
}

- (_UIContextMenuStyle *)_contextMenuInteraction:(UIContextMenuInteraction *)interaction styleForMenuWithConfiguration:(UIContextMenuConfiguration *)configuration
{
    _UIContextMenuStyle *style = [_UIContextMenuStyle defaultStyle];
    style.preferredLayout = 3; // _UIContextMenuLayoutCompactMenu
    return style;
}

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.list.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
        cell.imageView.contentMode = UIViewContentModeScaleToFill;
        cell.imageView.clipsToBounds = YES;
    }

    NSDictionary *item = self.list[indexPath.row];
    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = item[@"description"];
    UIImage *fallbackImage = [UIImage imageNamed:@"DefaultProfile"];
    [cell.imageView setImageWithURL:[NSURL URLWithString:item[@"imageUrl"]] placeholderImage:fallbackImage];

    if (!self.modrinth.reachedLastPage && indexPath.row == self.list.count-1) {
        [self loadSearchResultsWithPrevList:YES];
    }

    return cell;
}

- (NSArray<NSNumber *> *)compatibleVersionIndicesForDetails:(NSDictionary *)details {
    NSMutableArray<NSNumber *> *indices = [NSMutableArray new];
    NSString *mcVersion = self.filters[@"mcVersion"];
    NSString *loader = self.filters[@"loader"];
    for (NSUInteger i = 0; i < [details[@"versionNames"] count]; i++) {
        if (self.individualMods && mcVersion.length > 0) {
            NSArray *gameVersions = details[@"versionGameVersions"][i];
            if (![gameVersions containsObject:mcVersion]) {
                continue;
            }
        }
        if (self.individualMods && loader.length > 0) {
            NSArray *loaders = details[@"versionLoaders"][i];
            if (![loaders containsObject:loader]) {
                continue;
            }
        }
        [indices addObject:@(i)];
    }
    return indices;
}

- (void)showDetails:(NSDictionary *)details atIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    NSArray<NSNumber *> *compatibleIndices = [self compatibleVersionIndicesForDetails:details];
    if (compatibleIndices.count == 0) {
        showDialog(localize(@"Error", nil), localize(@"mod.error.no_compatible_version", nil));
        return;
    }

    NSMutableArray<UIAction *> *menuItems = [[NSMutableArray alloc] init];
    for (NSNumber *indexNumber in compatibleIndices) {
        NSUInteger index = indexNumber.unsignedIntegerValue;
        NSString *name = details[@"versionNames"][index];
        NSString *nameWithVersion = name;
        NSString *mcVersion = details[@"mcVersionNames"][index];
        if (![name hasSuffix:mcVersion]) {
            nameWithVersion = [NSString stringWithFormat:@"%@ - %@", name, mcVersion];
        }
        [menuItems addObject:[UIAction
            actionWithTitle:nameWithVersion
            image:nil identifier:nil
            handler:^(UIAction *action) {
                [self actionClose];
                if (self.individualMods) {
                    [self.modrinth installModFromDetail:self.list[indexPath.row] atIndex:index];
                } else {
                    NSString *tmpIconPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"icon.png"];
                    [UIImagePNGRepresentation([cell.imageView.image _imageWithSize:CGSizeMake(40, 40)])
                        writeToFile:tmpIconPath atomically:YES];
                    [self.modrinth installModpackFromDetail:self.list[indexPath.row] atIndex:index];
                }
            }]];
    }

    self.currentMenu = [UIMenu menuWithTitle:@"" children:menuItems];
    UIContextMenuInteraction *interaction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
    cell.detailTextLabel.interactions = @[interaction];
    [interaction _presentMenuAtLocation:CGPointZero];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.list[indexPath.row];
    if ([item[@"versionDetailsLoaded"] boolValue]) {
        [self showDetails:item atIndexPath:indexPath];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    [self switchToLoadingState];
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.modrinth loadDetailsOfMod:self.list[indexPath.row]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self switchToReadyState];
            if ([item[@"versionDetailsLoaded"] boolValue]) {
                [self showDetails:item atIndexPath:indexPath];
            } else {
                showDialog(localize(@"Error", nil), self.modrinth.lastError.localizedDescription);
            }
        });
    });
}

@end

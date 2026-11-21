#import "AFNetworking.h"
#import "LauncherPreferences.h"
#import "ModBrowserViewController.h"
#import "ModManager.h"
#import "ModSiteAPI.h"
#import "PLProfiles.h"
#import "UIKit+AFNetworking.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface ModBrowserViewController () <UISearchResultsUpdating>

@property(nonatomic) NSMutableArray<NSDictionary *> *list;
@property(nonatomic) ModSiteAPI *api;
@property(nonatomic) UISearchController *searchController;
@property(nonatomic) UISegmentedControl *sourceControl;
@property(nonatomic) UIBarButtonItem *filterItem;
@property(nonatomic) UIActivityIndicatorView *spinner;
@property(nonatomic) BOOL strictMatch;
@property(nonatomic) BOOL loading;
@property(nonatomic) BOOL loadingMore;
@property(nonatomic) NSString *gameVersion;
@property(nonatomic) NSString *loader;

@end

@implementation ModBrowserViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = localize(@"mods.browse.title", nil);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.list = [NSMutableArray new];
    self.api = [ModSiteAPI apiForSourceName:[ModSiteAPI sourceNames].firstObject];
    self.strictMatch = getPrefBool(@"mods.strict_match");
    self.gameVersion = [ModManager minecraftVersionForProfile:self.profile];
    self.loader = [ModManager modLoaderForProfile:self.profile];

    self.sourceControl = [[UISegmentedControl alloc] initWithItems:[ModSiteAPI sourceNames]];
    self.sourceControl.selectedSegmentIndex = 0;
    [self.sourceControl addTarget:self action:@selector(sourceChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.sourceControl;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = localize(@"mods.browse.search", nil);
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    UIBarButtonItem *spinnerItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    self.filterItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
                menu:[self buildFilterMenu]];
    self.navigationItem.rightBarButtonItems = @[self.filterItem, spinnerItem];

    [self reload];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
    [self performSelector:@selector(reload) withObject:nil afterDelay:0.5];
}

- (NSString *)currentQuery {
    return self.searchController.searchBar.text ?: @"";
}

- (NSString *)currentGameVersion {
    return self.strictMatch ? self.gameVersion : nil;
}

- (NSString *)currentLoader {
    return self.strictMatch ? self.loader : nil;
}

- (void)reload {
    if (self.loading) {
        return;
    }
    self.loading = YES;
    [self setLoadingState:YES];

    NSString *query = [self currentQuery];
    NSString *gameVersion = [self currentGameVersion];
    NSString *loader = [self currentLoader];
    ModSiteAPI *api = self.api;

    [self.list removeAllObjects];
    [self.tableView reloadData];

    __weak ModBrowserViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSDictionary *> *result = [api searchQuery:query gameVersion:gameVersion loader:loader offset:0];
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.loading = NO;
            [weakSelf setLoadingState:NO];
            if (result == nil) {
                [weakSelf showLastError];
                return;
            }
            [weakSelf.list setArray:result];
            [weakSelf.tableView reloadData];
        });
    });
}

- (void)loadMore {
    if (self.loading || self.loadingMore || self.api.reachedLastPage) {
        return;
    }
    self.loadingMore = YES;

    NSString *query = [self currentQuery];
    NSString *gameVersion = [self currentGameVersion];
    NSString *loader = [self currentLoader];
    ModSiteAPI *api = self.api;
    NSUInteger offset = self.list.count;

    __weak ModBrowserViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSDictionary *> *result = [api searchQuery:query gameVersion:gameVersion loader:loader offset:offset];
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.loadingMore = NO;
            if (result.count == 0) {
                return;
            }
            [weakSelf.list addObjectsFromArray:result];
            [weakSelf.tableView reloadData];
        });
    });
}

- (void)sourceChanged:(UISegmentedControl *)sender {
    self.api = [ModSiteAPI apiForSourceName:[sender titleForSegmentAtIndex:sender.selectedSegmentIndex]];
    if (!self.api.isAvailable) {
        [self promptForAPIKey];
        return;
    }
    [self reload];
}

- (void)promptForAPIKey {
    ModSiteAPI *api = self.api;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"mods.curseforge.key.title", nil)
        message:api.unavailableReason
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"$2a$10$…";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
        style:UIAlertActionStyleCancel handler:nil]];
    __weak ModBrowserViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [ModSiteAPI setCurseForgeAPIKey:alert.textFields.firstObject.text];
            [weakSelf reload];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Filter menu

- (UIMenu *)buildFilterMenu {
    __weak ModBrowserViewController *weakSelf = self;
    UIAction *strict = [UIAction actionWithTitle:localize(@"mods.browse.strict", nil)
        image:nil identifier:nil handler:^(UIAction *action) {
            weakSelf.strictMatch = YES;
            setPrefBool(@"mods.strict_match", YES);
            [weakSelf rebuildFilterMenu];
            [weakSelf reload];
        }];
    strict.state = self.strictMatch ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *all = [UIAction actionWithTitle:localize(@"mods.browse.all_versions", nil)
        image:nil identifier:nil handler:^(UIAction *action) {
            weakSelf.strictMatch = NO;
            setPrefBool(@"mods.strict_match", NO);
            [weakSelf rebuildFilterMenu];
            [weakSelf reload];
        }];
    all.state = self.strictMatch ? UIMenuElementStateOff : UIMenuElementStateOn;

    return [UIMenu menuWithTitle:localize(@"mods.browse.filter", nil) children:@[strict, all]];
}

- (void)rebuildFilterMenu {
    self.filterItem.menu = [self buildFilterMenu];
}

#pragma mark - UI state

- (void)setLoadingState:(BOOL)loading {
    if (loading) {
        [self.spinner startAnimating];
        self.tableView.userInteractionEnabled = NO;
        self.sourceControl.userInteractionEnabled = NO;
    } else {
        [self.spinner stopAnimating];
        self.tableView.userInteractionEnabled = YES;
        self.sourceControl.userInteractionEnabled = YES;
    }
}

- (void)showLastError {
    NSString *message = self.api.lastError.localizedDescription ?: localize(@"mods.browse.empty", nil);
    showDialog(localize(@"Error", nil), message);
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.list.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *profile = [ModManager profileDescription:self.profile];
    NSString *filter = self.strictMatch ? localize(@"mods.browse.strict", nil) : localize(@"mods.browse.all_versions", nil);
    return [NSString stringWithFormat:@"%@ — %@ (%@)", profile, self.api.sourceName, filter];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.list.count == 0) {
        return self.loading ? nil : localize(@"mods.browse.empty", nil);
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
        cell.detailTextLabel.numberOfLines = 2;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
        cell.imageView.clipsToBounds = YES;
    }

    NSDictionary *project = self.list[indexPath.row];
    cell.textLabel.text = project[@"title"];
    cell.detailTextLabel.text = project[@"summary"];
    [cell.imageView setImageWithURL:[NSURL URLWithString:project[@"iconURL"] ?: @""]
        placeholderImage:[UIImage imageNamed:@"DefaultProfile"]];

    if (!self.loading && !self.api.reachedLastPage && indexPath.row >= (NSInteger)self.list.count - 3) {
        [self loadMore];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    NSDictionary *project = self.list[indexPath.row];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSString *gameVersion = [self currentGameVersion];
    NSString *loader = [self currentLoader];
    ModSiteAPI *api = self.api;

    [self setLoadingState:YES];
    __weak ModBrowserViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSDictionary *> *files = [api versionsForProject:project gameVersion:gameVersion loader:loader];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf setLoadingState:NO];
            if (files.count == 0) {
                [weakSelf showLastError];
                return;
            }
            [weakSelf showVersionPicker:files forCell:cell];
        });
    });
}

- (NSString *)titleForFile:(NSDictionary *)file {
    NSString *name = file[@"name"] ?: file[@"filename"] ?: @"";
    if (name.length > 64) {
        name = [[name substringToIndex:61] stringByAppendingString:@"…"];
    }
    NSArray *versions = [file[@"gameVersions"] isKindOfClass:NSArray.class] ? file[@"gameVersions"] : @[];
    NSString *versionText = @"";
    if (versions.count > 0) {
        NSArray *firstTwo = versions.count > 2 ? [versions subarrayWithRange:NSMakeRange(0, 2)] : versions;
        versionText = [firstTwo componentsJoinedByString:@" "];
    }
    NSString *size = [ModManager formatSize:[file[@"size"] unsignedLongLongValue]];
    return [NSString stringWithFormat:@"%@ · %@ · %@", name, versionText, size];
}

- (void)showVersionPicker:(NSArray<NSDictionary *> *)files forCell:(UITableViewCell *)cell {
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:localize(@"mods.browse.versions", nil)
        message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];

    __weak ModBrowserViewController *weakSelf = self;
    NSUInteger limit = MIN(files.count, (NSUInteger)30);
    for (NSUInteger i = 0; i < limit; i++) {
        NSDictionary *file = files[i];
        [sheet addAction:[UIAlertAction actionWithTitle:[self titleForFile:file]
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [weakSelf installFile:file];
            }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
        style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.sourceView = cell ?: self.view;
    sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Install

- (UIAlertController *)presentProgressAlert:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:@"0%" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];
    return alert;
}

- (void)installFile:(NSDictionary *)file {
    NSString *fileName = file[@"filename"];
    if (![fileName isKindOfClass:NSString.class] || fileName.length == 0) {
        fileName = @"mod.jar";
    }
    fileName = fileName.lastPathComponent;

    NSString *directory = [ModManager modsDirectoryForProfile:self.profile createIfNeeded:YES];
    NSString *path = [directory stringByAppendingPathComponent:fileName];

    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:localize(@"mods.download.progress", nil)
        message:@"0%" preferredStyle:UIAlertControllerStyleAlert];
    __weak ModBrowserViewController *weakSelf = self;
    [self presentViewController:progressAlert animated:YES completion:^{
        [ModSiteAPI downloadURL:file[@"url"] toPath:path sha1:file[@"sha1"]
        progress:^(double fraction) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progressAlert.message = [NSString stringWithFormat:@"%ld%%", (long)(fraction * 100)];
            });
        }
        completion:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [progressAlert dismissViewControllerAnimated:YES completion:^{
                    if (error != nil) {
                        showDialog(localize(@"Error", nil), error.localizedDescription);
                        return;
                    }
                    showDialog(localize(@"mods.install.success", nil), fileName);
                    if (weakSelf.whenInstalled != nil) {
                        weakSelf.whenInstalled();
                    }
                }];
            });
        }];
    }];
}

@end

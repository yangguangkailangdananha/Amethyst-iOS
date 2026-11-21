#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "AFNetworking.h"
#import "LauncherPreferences.h"
#import "ModBrowserViewController.h"
#import "ModManager.h"
#import "ModSiteAPI.h"
#import "ModsViewController.h"
#import "PLProfiles.h"
#import "UIKit+hook.h"
#import "UIKit+AFNetworking.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

typedef NS_ENUM(NSInteger, ModsSection) {
    kModsSectionActions,
    kModsSectionInstalled
};

@interface ModsViewController () <UIDocumentPickerDelegate>

@property(nonatomic) NSDictionary *profile;
@property(nonatomic) NSString *modsDirectory;
@property(nonatomic) NSMutableArray<NSDictionary *> *mods;

@end

@implementation ModsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = localize(@"mods.title", nil);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.mods = [NSMutableArray new];

    UIBarButtonItem *addItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"plus"]
                menu:[self buildAddMenu]];
    self.navigationItem.rightBarButtonItem = addItem;

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reloadMods) forControlEvents:UIControlEventValueChanged];

    [self reloadMods];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadMods];
}

#pragma mark - Data

- (void)reloadMods {
    self.profile = [ModManager currentProfile];
    self.modsDirectory = [ModManager modsDirectoryForProfile:self.profile createIfNeeded:YES];
    NSArray<NSDictionary *> *mods = [ModManager listModsInDirectory:self.modsDirectory];
    [self.mods setArray:mods];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
        [self.refreshControl endRefreshing];
    });
}

- (NSArray<NSDictionary *> *)actionItems {
    return @[
        @{@"title": localize(@"mods.action.import", nil), @"icon": @"folder.badge.plus"},
        @{@"title": localize(@"mods.action.browse", nil), @"icon": @"globe"},
        @{@"title": localize(@"mods.action.url", nil), @"icon": @"link"},
        @{@"title": localize(@"mods.action.open_folder", nil), @"icon": @"folder"}
    ];
}

#pragma mark - Menus

- (UIMenu *)buildAddMenu {
    __weak ModsViewController *weakSelf = self;
    UIAction *importAction = [UIAction actionWithTitle:localize(@"mods.action.import", nil)
        image:[UIImage systemImageNamed:@"folder.badge.plus"] identifier:@"import"
        handler:^(UIAction *action) { [weakSelf actionImportLocal]; }];
    UIAction *browseAction = [UIAction actionWithTitle:localize(@"mods.action.browse", nil)
        image:[UIImage systemImageNamed:@"globe"] identifier:@"browse"
        handler:^(UIAction *action) { [weakSelf actionBrowse]; }];
    UIAction *urlAction = [UIAction actionWithTitle:localize(@"mods.action.url", nil)
        image:[UIImage systemImageNamed:@"link"] identifier:@"url"
        handler:^(UIAction *action) { [weakSelf actionInstallFromURL]; }];
    return [UIMenu menuWithTitle:localize(@"mods.section.actions", nil)
        children:@[importAction, browseAction, urlAction]];
}

#pragma mark - Actions

- (void)actionImportLocal {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)actionBrowse {
    ModBrowserViewController *vc = [ModBrowserViewController new];
    vc.profile = self.profile;
    __weak ModsViewController *weakSelf = self;
    vc.whenInstalled = ^{
        [weakSelf reloadMods];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)actionInstallFromURL {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"mods.action.url", nil)
        message:localize(@"mods.action.url.message", nil)
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"https://example.com/mod.jar";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
        style:UIAlertActionStyleCancel handler:nil]];
    __weak ModsViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [weakSelf installFromURLString:alert.textFields.firstObject.text];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)installFromURLString:(NSString *)urlString {
    NSString *trimmed = [urlString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *url = [NSURL URLWithString:trimmed];
    if (url.scheme.length == 0) {
        showDialog(localize(@"Error", nil), localize(@"mods.error.invalid_url", nil));
        return;
    }

    NSString *fileName = url.lastPathComponent;
    if (fileName.length == 0 || ![fileName.pathExtension.lowercaseString isEqualToString:@"jar"]) {
        fileName = @"downloaded-mod.jar";
    }
    NSString *path = [self.modsDirectory stringByAppendingPathComponent:fileName];

    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:localize(@"mods.download.progress", nil)
        message:@"0%" preferredStyle:UIAlertControllerStyleAlert];
    __weak ModsViewController *weakSelf = self;
    // Start the download only once the alert is on screen, otherwise a fast
    // download could try to dismiss a controller that was never presented.
    [self presentViewController:progressAlert animated:YES completion:^{
        [ModSiteAPI downloadURL:trimmed toPath:path sha1:nil
        progress:^(double fraction) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progressAlert.message = [NSString stringWithFormat:@"%ld%%", (long)(fraction * 100)];
            });
        }
        completion:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [progressAlert dismissViewControllerAnimated:YES completion:^{
                    [weakSelf reloadMods];
                    if (error != nil) {
                        showDialog(localize(@"Error", nil), error.localizedDescription);
                    } else {
                        showDialog(localize(@"mods.install.success", nil), fileName);
                    }
                }];
            });
        }];
    }];
}

- (void)actionOpenFolder {
    NSURL *folderURL = [NSURL fileURLWithPath:self.modsDirectory isDirectory:YES];
    UIActivityViewController *activityVC =
        [[UIActivityViewController alloc] initWithActivityItems:@[folderURL] applicationActivities:nil];
    activityVC.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (UIAlertController *)presentProgressAlert:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:@"0%" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];
    return alert;
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSMutableArray<NSString *> *imported = [NSMutableArray new];
    NSMutableArray<NSString *> *failures = [NSMutableArray new];

    for (NSURL *url in urls) {
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSError *error = nil;
        NSArray<NSString *> *files = [ModManager importFileAtPath:url.path
                                                     intoDirectory:self.modsDirectory
                                                             error:&error];
        if (scoped) {
            [url stopAccessingSecurityScopedResource];
        }
        if (files != nil) {
            [imported addObjectsFromArray:files];
        } else {
            [failures addObject:error.localizedDescription ?: url.lastPathComponent];
        }
    }

    [self reloadMods];

    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    if (imported.count > 0) {
        [lines addObject:[NSString stringWithFormat:localize(@"mods.import.success", nil), (long)imported.count]];
        [lines addObject:[imported componentsJoinedByString:@"\n"]];
    }
    if (failures.count > 0) {
        [lines addObject:[failures componentsJoinedByString:@"\n"]];
    }
    showDialog(localize(@"mods.action.import", nil), [lines componentsJoinedByString:@"\n"]);
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == kModsSectionActions ? self.actionItems.count : self.mods.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == kModsSectionActions) {
        return localize(@"mods.section.actions", nil);
    }
    return [NSString stringWithFormat:localize(@"mods.section.installed", nil), (long)self.mods.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == kModsSectionActions) {
        if ([[ModManager modLoaderForProfile:self.profile] isEqualToString:@"vanilla"]) {
            return localize(@"mods.warning.vanilla", nil);
        }
        return nil;
    }
    if (self.mods.count == 0) {
        return localize(@"mods.empty", nil);
    }
    return [NSString stringWithFormat:@"%@\n%@",
        [ModManager profileDescription:self.profile], self.modsDirectory];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
        cell.detailTextLabel.numberOfLines = 2;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.imageView.contentMode = UIViewContentModeCenter;
    }

    if (indexPath.section == kModsSectionActions) {
        NSDictionary *item = self.actionItems[indexPath.row];
        cell.textLabel.text = item[@"title"];
        cell.textLabel.enabled = YES;
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [UIImage systemImageNamed:item[@"icon"]];
        cell.imageView.tintColor = self.view.tintColor;
        return cell;
    }

    NSDictionary *mod = self.mods[indexPath.row];
    BOOL enabled = [mod[@"enabled"] boolValue];

    cell.textLabel.text = mod[@"displayName"] ?: mod[@"fileName"];
    cell.textLabel.enabled = enabled;

    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    NSString *identifier = mod[@"identifier"];
    if (identifier.length > 0 && ![identifier isEqualToString:mod[@"fileName"]]) {
        [parts addObject:identifier];
    }
    NSString *version = mod[@"version"];
    if (version.length > 0 && ![version isEqualToString:@"${file.jarVersion}"]) {
        [parts addObject:[NSString stringWithFormat:@"v%@", version]];
    }
    [parts addObject:[ModManager formatSize:[mod[@"size"] unsignedLongLongValue]]];
    if (!enabled) {
        [parts addObject:localize(@"mods.status.disabled", nil)];
    }
    cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
    cell.imageView.image = [UIImage systemImageNamed:enabled ? @"puzzlepiece.extension" : @"puzzlepiece.extension.fill"];
    cell.imageView.tintColor = enabled ? self.view.tintColor : UIColor.tertiaryLabelColor;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    if (indexPath.section == kModsSectionActions) {
        switch (indexPath.row) {
            case 0: [self actionImportLocal]; return;
            case 1: [self actionBrowse]; return;
            case 2: [self actionInstallFromURL]; return;
            default: [self actionOpenFolder]; return;
        }
    }

    [self showDetailsForMod:self.mods[indexPath.row]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != kModsSectionInstalled) {
        return nil;
    }

    NSDictionary *mod = self.mods[indexPath.row];
    BOOL enabled = [mod[@"enabled"] boolValue];

    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:localize(@"mods.action.delete", nil)
        handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            NSError *error = nil;
            if ([ModManager deleteMod:mod error:&error]) {
                [self reloadMods];
                completionHandler(YES);
            } else {
                showDialog(localize(@"Error", nil), error.localizedDescription);
                completionHandler(NO);
            }
        }];

    UIContextualAction *toggle = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:localize(enabled ? @"mods.action.disable" : @"mods.action.enable", nil)
        handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            [ModManager setMod:mod enabled:!enabled];
            [self reloadMods];
            completionHandler(YES);
        }];
    toggle.backgroundColor = UIColor.systemBlueColor;

    return [UISwipeActionsConfiguration configurationWithActions:@[delete, toggle]];
}

- (void)showDetailsForMod:(NSDictionary *)mod {
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    if ([mod[@"fileName"] length] > 0) [lines addObject:mod[@"fileName"]];
    if ([mod[@"identifier"] length] > 0) [lines addObject:[NSString stringWithFormat:@"ID: %@", mod[@"identifier"]]];
    if ([mod[@"version"] length] > 0) [lines addObject:[NSString stringWithFormat:@"Version: %@", mod[@"version"]]];
    [lines addObject:[ModManager formatSize:[mod[@"size"] unsignedLongLongValue]]];
    if ([mod[@"path"] length] > 0) [lines addObject:mod[@"path"]];

    BOOL enabled = [mod[@"enabled"] boolValue];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:mod[@"displayName"]
        message:[lines componentsJoinedByString:@"\n"]
        preferredStyle:UIAlertControllerStyleAlert];

    __weak ModsViewController *weakSelf = self;
    [alert addAction:[UIAlertAction
        actionWithTitle:localize(enabled ? @"mods.action.disable" : @"mods.action.enable", nil)
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            [ModManager setMod:mod enabled:!enabled];
            [weakSelf reloadMods];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"mods.action.delete", nil)
        style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action) {
            NSError *error = nil;
            if (![ModManager deleteMod:mod error:&error]) {
                showDialog(localize(@"Error", nil), error.localizedDescription);
            }
            [weakSelf reloadMods];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
        style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

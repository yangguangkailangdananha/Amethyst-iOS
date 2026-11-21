#import <UIKit/UIKit.h>

@class ModSiteAPI;

// Search and install mods from the supported mod hosting sites.
// `profile` is used to filter results by game version and mod loader.
@interface ModBrowserViewController : UITableViewController

@property(nonatomic) NSDictionary *profile;
@property(nonatomic, copy) void (^whenInstalled)(void);

@end

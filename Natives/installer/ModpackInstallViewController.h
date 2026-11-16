#import <UIKit/UIKit.h>

@interface ModpackInstallViewController : UITableViewController<UISearchResultsUpdating>
@property(nonatomic, assign, readonly) BOOL individualMods;

- (instancetype)initWithIndividualMods:(BOOL)individualMods;
@end

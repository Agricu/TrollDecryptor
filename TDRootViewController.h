#import <UIKit/UIKit.h>

@interface TDRootViewController : UITableViewController

@property (nonatomic, strong) NSArray<NSDictionary *> *apps;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredApps;
@property (nonatomic, strong) UISearchController *searchController;

@end

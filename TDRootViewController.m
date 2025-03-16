#import "TDRootViewController.h"
#import "TDFileManagerViewController.h"
#import "TDUtils.h"
#import "NetCustomTableViewCell.h"

@interface TDRootViewController () <UISearchResultsUpdating>
@end

@implementation TDRootViewController

#pragma mark - 生命周期方法
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 表格样式配置
    self.tableView.rowHeight = 80.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    // iOS15+兼容性处理
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0f;
    }
    
    // 初始化搜索控制器
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = NSLocalizedString(@"SEARCH_PLACEHOLDER", @"Search Apps");
    
    // 导航栏集成
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    } else {
        self.tableView.tableHeaderView = self.searchController.searchBar;
    }
    
    // 消除空白单元格分隔线
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), 1)];
    footerView.backgroundColor = [UIColor clearColor];
    self.tableView.tableFooterView = footerView;
}

- (void)loadView {
    [super loadView];
    
    // 初始化数据源
    self.apps = [self validatedAppList];
    self.filteredApps = @[];
    
    // 导航栏配置
    //self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.title = NSLocalizedString(@"APP_LIST_TITLE", @"Applications");
    
    // 右侧信息按钮
    UIImage *infoImage = [UIImage systemImageNamed:@"info.circle"];
    if (@available(iOS 13.0, *)) {
        infoImage = [UIImage systemImageNamed:@"info.circle"];
    } else {
        infoImage = [UIImage imageNamed:@"info"];
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:infoImage
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(handleAboutAction:)];
    
    // 左侧文档按钮
    UIImage *folderImage = [UIImage systemImageNamed:@"folder"];
    if (@available(iOS 13.0, *)) {
        folderImage = [UIImage systemImageNamed:@"folder"];
    } else {
        folderImage = [UIImage imageNamed:@"folder"];
    }
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:folderImage
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(handleOpenDocuments:)];
    
    // 下拉刷新控件
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self
                       action:@selector(handleRefreshAction:)
             forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;
}

// 显示关于信息
- (void)about:(id)sender {
    /** 创建带本地化文本的弹窗 */
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"ABOUT_TITLE", @"TrollDecrypt") message:NSLocalizedString(@"ABOUT_MESSAGE", @"by fiore\nIcon by @super.user\nbfdecrypt by @bishopfox\ndumpdecrypted by @i0n1c\nUpdated for TrollStore by @wh1te4ever") preferredStyle:UIAlertControllerStyleAlert];
    // 添加关闭按钮
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"DISMISS_BUTTON", @"Dismiss")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}


#pragma mark - 数据验证
- (NSArray *)validatedAppList {
    NSArray *rawList = appList();
    NSMutableArray *validatedList = [NSMutableArray arrayWithCapacity:rawList.count];
    
    for (NSDictionary *app in rawList) {
        if ([app isKindOfClass:[NSDictionary class]] &&
            [app[@"name"] isKindOfClass:[NSString class]] &&
            [app[@"bundleID"] isKindOfClass:[NSString class]] &&
            [app[@"version"] isKindOfClass:[NSString class]]) {
            [validatedList addObject:app];
        } else {
            NSLog(@"⚠️ 过滤无效应用数据: %@", app);
        }
    }
    
    return [validatedList copy];
}

#pragma mark - 表格数据源
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self adjustedCountForDataSource:self.searchController.isActive ? self.filteredApps : self.apps
                               isSearchMode:self.searchController.isActive];
}

- (NSInteger)adjustedCountForDataSource:(NSArray *)dataSource isSearchMode:(BOOL)isSearchMode {
    NSInteger count = dataSource.count;
    if (!isSearchMode) {
        count = MAX(0, count - 1); // 非搜索模式减1
    }
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"ApplicationCell";
    NetCustomTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    if (!cell) {
        cell = [[NetCustomTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                            reuseIdentifier:cellIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }
    
    // 获取数据源
    NSArray *dataSource = self.searchController.isActive ? self.filteredApps : self.apps;
    
    // 数据边界检查
    if (indexPath.row >= dataSource.count) {
        cell.textLabel.text = NSLocalizedString(@"DATA_LOADING", @"Loading...");
        return cell;
    }
    
    NSDictionary *app = dataSource[indexPath.row];
    
    // 数据完整性检查
    if (![app isKindOfClass:[NSDictionary class]]) {
        cell.textLabel.text = NSLocalizedString(@"DATA_CORRUPTED", @"Invalid Data");
        return cell;
    }
    
    /** 配置单元格内容 */
       cell.textLabel.text = app[@"name"]; // 应用名称
       cell.versionLabel.text = [NSString stringWithFormat:NSLocalizedString(@"VERSION_FORMAT", @"version: %@"), app[@"version"]]; // 本地化版本号
       cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"BUNDLE_ID_FORMAT", @"bundleID: %@"), app[@"bundleID"]]; // 本地化BundleID
    
    // 异步加载图标
    __weak typeof(cell) weakCell = cell;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        UIImage *icon = nil;
        @try {
            NSString *bundleID = app[@"bundleID"];
            if ([bundleID isKindOfClass:[NSString class]]) {
                icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:iconFormat() scale:[UIScreen mainScreen].scale];
            }
        } @catch (NSException *exception) {
            NSLog(@"🚨 图标加载异常: %@", exception);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (@available(iOS 13.0, *)) {
                weakCell.imageView.image = icon ?: [UIImage systemImageNamed:@"questionmark.app"];
            } else {
                weakCell.imageView.image = icon ?: [UIImage imageNamed:@"questionmark"];
            }
            [weakCell setNeedsLayout];
        });
    });
    
    return cell;
}

#pragma mark - 表格代理
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // 清理旧样式
    cell.imageView.layer.cornerRadius = 0;
    cell.imageView.layer.borderWidth = 0;
    
    // 动态分割线
    if (indexPath.row < [self tableView:tableView numberOfRowsInSection:indexPath.section] - 1) {
        CGFloat lineHeight = 1.0 / [UIScreen mainScreen].scale;
        UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(16, CGRectGetHeight(cell.bounds)-lineHeight, CGRectGetWidth(cell.bounds)-32, lineHeight)];
        if (@available(iOS 13.0, *)) {
            separator.backgroundColor = [UIColor.separatorColor colorWithAlphaComponent:0.3];
        } else {
            separator.backgroundColor = [UIColor lightGrayColor];
        }
        separator.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        [cell.contentView addSubview:separator];
    }
}

#pragma mark - 用户交互
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSArray *dataSource = self.searchController.isActive ? self.filteredApps : self.apps;
    if (indexPath.row >= dataSource.count) return;
    
    NSDictionary *app = dataSource[indexPath.row];
    if (![app isKindOfClass:[NSDictionary class]]) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"DECRYPT_TITLE", @"Decrypt") message:[NSString stringWithFormat:NSLocalizedString(@"DECRYPT_PROMPT", @"Confirm decrypt %@?"), app[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CANCEL", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CONFIRM", @"Confirm") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self handleDecryptActionForApp:app];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 搜索功能
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchTerm = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].lowercaseString;
    
    if (searchTerm.length == 0) {
        self.filteredApps = self.apps;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *app, NSDictionary *bindings) {
            NSString *name = [app[@"name"] lowercaseString] ?: @"";
            NSString *bundleID = [app[@"bundleID"] lowercaseString] ?: @"";
            return [name containsString:searchTerm] || [bundleID containsString:searchTerm];
        }];
        self.filteredApps = [self.apps filteredArrayUsingPredicate:predicate];
    }
    
    [self.tableView reloadData];
}

#pragma mark - 私有方法
- (void)handleDecryptActionForApp:(NSDictionary *)app {
    if (![app isKindOfClass:[NSDictionary class]]) return;
    
    NSLog(@"🔐 开始解密操作: %@", app[@"bundleID"]);
    decryptApp(app);
}

- (void)handleRefreshAction:(UIRefreshControl *)sender {
    self.apps = [self validatedAppList];
    [self.tableView reloadData];
    [sender endRefreshing];
}

- (void)handleAboutAction:(id)sender {
        /** 创建带本地化文本的弹窗 */
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"ABOUT_TITLE", @"TrollDecrypt") message:NSLocalizedString(@"ABOUT_MESSAGE", @"by fiore\nIcon by @super.user\nbfdecrypt by @bishopfox\ndumpdecrypted by @i0n1c\nUpdated for TrollStore by @wh1te4ever") preferredStyle:UIAlertControllerStyleAlert];
        // 添加关闭按钮
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"DISMISS_BUTTON", @"Dismiss") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    
}

- (void)handleOpenDocuments:(id)sender {
    TDFileManagerViewController *fileVC = [[TDFileManagerViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:fileVC];
    navController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navController animated:YES completion:nil];
}

@end

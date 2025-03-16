#import "TDFileManagerViewController.h"
#import "TDUtils.h"

@implementation TDFileManagerViewController

- (void)loadView {
    [super loadView];
    
    // 标题本地化
    self.title = NSLocalizedString(@"DECRYPTED_IPAS", @"Decrypted ipa");
    
    self.fileList = decryptedFileList();
    
    // 导航栏按钮本地化
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                                              initWithTitle:NSLocalizedString(@"REFRESH_BUTTON", @"Refresh list button title")
                                              style:UIBarButtonItemStyleDone
                                              target:self
                                              action:@selector(refresh)];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
                                             initWithTitle:NSLocalizedString(@"BACK_BUTTON", @"back")
                                             style:UIBarButtonItemStyleDone
                                             target:self
                                             action:@selector(done)];
}

- (void)refresh {
    self.fileList = decryptedFileList();
    [self.tableView reloadData];
}

- (void)done {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.fileList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"FileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }
    
    NSString *fileName = self.fileList[indexPath.row];
    NSString *filePath = [docPath() stringByAppendingPathComponent:fileName];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
    
    NSDate *date = attributes[NSFileModificationDate];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];

    // 设置日期格式
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    // 确保格式不受系统本地化设置影响
    dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

    NSString *formattedDate = [dateFormatter stringFromDate:date];
    
    // 文件大小本地化
    NSNumber *fileSize = attributes[NSFileSize];
    NSString *sizeString = [NSString stringWithFormat:NSLocalizedString(@"FILE_SIZE_FORMAT", @"%.2f MB"),
                           [fileSize doubleValue] / 1000000.0f];
    
    cell.textLabel.text = fileName;
    cell.detailTextLabel.text = [dateFormatter stringFromDate:attributes[NSFileModificationDate]];
    cell.detailTextLabel.textColor = [UIColor systemGrayColor];
    cell.imageView.image = [UIImage systemImageNamed:@"doc.fill"];
    
    // 文件大小标签
    UILabel *sizeLabel = [[UILabel alloc] init];
    sizeLabel.text = sizeString;
    sizeLabel.textColor = [UIColor systemGrayColor];
    sizeLabel.font = [UIFont systemFontOfSize:12.0];
    [sizeLabel sizeToFit];
    cell.accessoryView = sizeLabel;
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 65.0;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:NSLocalizedString(@"DELETE_ACTION", @"Delete") handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSString *file = self.fileList[indexPath.row];
        NSString *path = [docPath() stringByAppendingPathComponent:file];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [self refresh];
    }];

    UISwipeActionsConfiguration *swipeActions = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    return swipeActions;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *fileName = self.fileList[indexPath.row];
    NSString *filePath = [docPath() stringByAppendingPathComponent:fileName];
    
    // 操作菜单本地化
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"FILE_ACTIONS_TITLE", @"File Operations")
                                                                         message:fileName
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 分享操作
    UIAlertAction *shareAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"SHARE_ACTION", @"Share")
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *action) {
        [self shareFileAtPath:filePath indexPath:indexPath];
    }];
    
    // 格式转换操作
    NSString *extension = [fileName pathExtension];
    NSString *convertTitle = [extension isEqualToString:@"ipa"] ?
        NSLocalizedString(@"CONVERT_TO_TIPA", @"Convert to TIPA") :
        NSLocalizedString(@"CONVERT_TO_IPA", @"Convert to IPA");
    
    UIAlertAction *convertAction = [UIAlertAction actionWithTitle:convertTitle
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
        [self toggleFileExtensionAtIndexPath:indexPath];
    }];
    
    // 取消操作
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"CANCEL_ACTION", @"Cancel")
                                                         style:UIAlertActionStyleCancel
                                                       handler:nil];
    
    [actionSheet addAction:shareAction];
    [actionSheet addAction:convertAction];
    [actionSheet addAction:cancelAction];
    
    // iPad 布局适配
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
        actionSheet.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    }
    
    [self presentViewController:actionSheet animated:YES completion:nil];
}

#pragma mark - 文件操作
- (void)toggleFileExtensionAtIndexPath:(NSIndexPath *)indexPath {
    NSString *originalName = self.fileList[indexPath.row];
    NSString *originalPath = [docPath() stringByAppendingPathComponent:originalName];
    
    // 新文件名生成
    NSString *newExtension = [[originalName pathExtension] isEqualToString:@"ipa"] ? @"tipa" : @"ipa";
    NSString *newFileName = [[originalName stringByDeletingPathExtension] stringByAppendingPathExtension:newExtension];
    NSString *newPath = [docPath() stringByAppendingPathComponent:newFileName];
    
    NSError *error;
    if ([[NSFileManager defaultManager] moveItemAtPath:originalPath toPath:newPath error:&error]) {
        [self shareFileAtPath:originalPath indexPath:indexPath];
    } else {
        NSString *errorMessage = [NSString stringWithFormat:NSLocalizedString(@"RENAME_ERROR_FORMAT", @"Rename failed: %@"), error.localizedDescription];
        [self showAlertWithTitle:NSLocalizedString(@"ERROR_TITLE", @"Error") message:errorMessage];
    }
}

- (void)shareFileAtPath:(NSString *)path indexPath:(NSIndexPath *)indexPath {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                             applicationActivities:nil];
    
    // iPad 布局适配
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = [self.tableView cellForRowAtIndexPath:indexPath];
        activityVC.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    }
    
    [self presentViewController:activityVC animated:YES completion:nil];
}

#pragma mark - 通用提示
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK_BUTTON", @"OK")
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end

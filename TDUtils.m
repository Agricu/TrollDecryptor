#import "TDUtils.h"
#import "TDDumpDecrypted.h"
#import "LSApplicationProxy+AltList.h"

UIWindow *alertWindow = NULL;
UIWindow *kw = NULL;
UIViewController *root = NULL;
UIAlertController *alertController = NULL;
UIAlertController *doneController = NULL;
UIAlertController *errorController = NULL;

NSArray *appList(void) {
    NSMutableArray *apps = [NSMutableArray array];

    NSArray <LSApplicationProxy *> *installedApplications = [[LSApplicationWorkspace defaultWorkspace] atl_allInstalledApplications];
    [installedApplications enumerateObjectsUsingBlock:^(LSApplicationProxy *proxy, NSUInteger idx, BOOL *stop) {
        if (![proxy atl_isUserApplication]) return;

        NSString *bundleID = [proxy atl_bundleIdentifier];
        NSString *name = [proxy atl_nameToDisplay];
        NSString *version = [proxy atl_shortVersionString];
        NSString *executable = proxy.canonicalExecutablePath;

        if (!bundleID || !name || !version || !executable) return;

        NSDictionary *item = @{
            @"bundleID":bundleID,
            @"name":name,
            @"version":version,
            @"executable":executable
        };

        [apps addObject:item];
    }];

    NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    [apps sortUsingDescriptors:@[descriptor]];

    [apps addObject:@{@"bundleID":@"", @"name":@"", @"version":@"", @"executable":@""}];

    return [apps copy];
}

NSUInteger iconFormat(void) {
    return (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) ? 8 : 10;
}

NSArray *sysctl_ps(void) {
    NSMutableArray *array = [[NSMutableArray alloc] init];

    int numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t pids[numberOfProcesses];
    bzero(pids, sizeof(pids));
    proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    for (int i = 0; i < numberOfProcesses; ++i) {
        if (pids[i] == 0) { continue; }
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
        bzero(pathBuffer, PROC_PIDPATHINFO_MAXSIZE);
        proc_pidpath(pids[i], pathBuffer, sizeof(pathBuffer));

        if (strlen(pathBuffer) > 0) {
            NSString *processID = [[NSString alloc] initWithFormat:@"%d", pids[i]];
            NSString *processName = [[NSString stringWithUTF8String:pathBuffer] lastPathComponent];
            NSDictionary *dict = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:processID, processName, nil] forKeys:[NSArray arrayWithObjects:@"pid", @"proc_name", nil]];
            
            [array addObject:dict];
        }
    }

    return [array copy];
}

void decryptApp(NSDictionary *app) {
    dispatch_async(dispatch_get_main_queue(), ^{
        alertWindow = [[UIWindow alloc] initWithFrame: [UIScreen mainScreen].bounds];
        alertWindow.rootViewController = [UIViewController new];
        alertWindow.windowLevel = UIWindowLevelAlert + 1;
        [alertWindow makeKeyAndVisible];
            
        kw = alertWindow;
        if([kw respondsToSelector:@selector(topmostPresentedViewController)])
            root = [kw performSelector:@selector(topmostPresentedViewController)];
        else
            root = [kw rootViewController];
        root.modalPresentationStyle = UIModalPresentationFullScreen;
    });

    NSLog(@"[trolldecrypt] spawning thread to do decryption in background...");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"[trolldecrypt] inside decryption thread.");

        NSString *bundleID = app[@"bundleID"];
        NSString *name = app[@"name"];
        NSString *version = app[@"version"];
        NSString *executable = app[@"executable"];
        NSString *binaryName = [executable lastPathComponent];

        [[UIApplication sharedApplication] launchApplicationWithIdentifier:bundleID suspended:YES];
        sleep(1);

        pid_t pid = -1;
        NSArray *processes = sysctl_ps();
        for (NSDictionary *process in processes) {
            NSString *proc_name = process[@"proc_name"];
            if ([proc_name isEqualToString:binaryName]) {
                pid = [process[@"pid"] intValue];
                break;
            }
        }

        if (pid == -1) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [alertController dismissViewControllerAnimated:NO completion:nil];
                NSLog(@"[trolldecrypt] %@", [NSString stringWithFormat:NSLocalizedString(@"ERROR_PID_FAILED", @"Failed to get PID for binary name: %@"), binaryName]);

                errorController = [UIAlertController
                    alertControllerWithTitle:NSLocalizedString(@"ERROR_TITLE", @"Error: -1")
                    message:[NSString stringWithFormat:NSLocalizedString(@"ERROR_PID_MESSAGE", @"Failed to get PID for binary name: %@"), binaryName]
                    preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction
                    actionWithTitle:NSLocalizedString(@"OK_BUTTON", @"OK")
                    style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [errorController dismissViewControllerAnimated:NO completion:nil];
                        [kw removeFromSuperview];
                        kw.hidden = YES;
                    }];

                [errorController addAction:okAction];
                [root presentViewController:errorController animated:YES completion:nil];
            });
            return;
        }

        bfinject_rocknroll(pid, name, version);
    });
}

void bfinject_rocknroll(pid_t pid, NSString *appName, NSString *version) {
    NSLog(@"[trolldecrypt] Spawning thread to do decryption in the background...");
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
        proc_pidpath(pid, pathbuf, sizeof(pathbuf));
        const char *fullPathStr = pathbuf;

        DumpDecrypted *dd = [[DumpDecrypted alloc] initWithPathToBinary:[NSString stringWithUTF8String:fullPathStr] appName:appName appVersion:version];
        if(!dd) {
            NSLog(@"[trolldecrypt] %@", NSLocalizedString(@"ERROR_DUMP_INSTANCE", @"Failed to get DumpDecrypted instance"));
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            alertWindow = [[UIWindow alloc] initWithFrame: [UIScreen mainScreen].bounds];
            alertWindow.rootViewController = [UIViewController new];
            alertWindow.windowLevel = UIWindowLevelAlert + 1;
            [alertWindow makeKeyAndVisible];
                
            alertController = [UIAlertController
                alertControllerWithTitle:NSLocalizedString(@"DECRYPTING_TITLE", @"Decrypting")
                message:NSLocalizedString(@"DECRYPTING_MESSAGE", @"Please wait, this will take a few seconds...")
                preferredStyle:UIAlertControllerStyleAlert];
                
            kw = alertWindow;
            if([kw respondsToSelector:@selector(topmostPresentedViewController)])
                root = [kw performSelector:@selector(topmostPresentedViewController)];
            else
                root = [kw rootViewController];
            root.modalPresentationStyle = UIModalPresentationFullScreen;
            [root presentViewController:alertController animated:YES completion:nil];
        });
        
        [dd createIPAFile:pid];

        dispatch_async(dispatch_get_main_queue(), ^{
            [alertController dismissViewControllerAnimated:NO completion:nil];

            doneController = [UIAlertController
                alertControllerWithTitle:NSLocalizedString(@"DECRYPT_COMPLETE_TITLE", @"Decryption Complete!")
                message:[NSString stringWithFormat:NSLocalizedString(@"DECRYPT_COMPLETE_MESSAGE", @"IPA file saved to:\n%@"), [dd IPAPath]]
                preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *okAction = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"OK_BUTTON", @"OK")
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [kw removeFromSuperview];
                    kw.hidden = YES;
                }];
            [doneController addAction:okAction];

            if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"filza://"]]) {
                UIAlertAction *openAction = [UIAlertAction
                    actionWithTitle:NSLocalizedString(@"SHOW_IN_FILZA", @"Show in Filza")
                    style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [kw removeFromSuperview];
                        kw.hidden = YES;
                        NSString *urlString = [NSString stringWithFormat:@"filza://view%@", [dd IPAPath]];
                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString] options:@{} completionHandler:nil];
                    }];
                [doneController addAction:openAction];
            }

            [root presentViewController:doneController animated:YES completion:nil];
        });
    });
}

NSArray *decryptedFileList(void) {
    NSMutableArray *files = [NSMutableArray array];
    NSMutableArray *fileNames = [NSMutableArray array];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtPath:docPath()];

    NSString *file;
    while (file = [directoryEnumerator nextObject]) {
        NSString *extension = [[file pathExtension] lowercaseString];
        if ([extension isEqualToString:@"ipa"] || [extension isEqualToString:@"tipa"]) {
            NSString *filePath = [[docPath() stringByAppendingPathComponent:file] stringByStandardizingPath];
            NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:filePath error:nil];
            NSDate *modificationDate = fileAttributes[NSFileModificationDate];
            NSDictionary *fileInfo = @{@"fileName": file, @"modificationDate": modificationDate};
            [files addObject:fileInfo];
        }
    }

    NSArray *sortedFiles = [files sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSDate *date1 = [obj1 objectForKey:@"modificationDate"];
        NSDate *date2 = [obj2 objectForKey:@"modificationDate"];
        return [date2 compare:date1];
    }];

    for (NSDictionary *fileInfo in sortedFiles) {
        [fileNames addObject:[fileInfo objectForKey:@"fileName"]];
    }

    return [fileNames copy];
}

NSString *docPath(void) {
    NSError * error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/TrollDecrypt/decrypted"
        withIntermediateDirectories:YES
        attributes:nil
        error:&error];
    if (error != nil) {
        NSLog(@"[trolldecrypt] %@", [NSString stringWithFormat:NSLocalizedString(@"ERROR_DIR_CREATE", @"Error creating directory: %@"), error]);
    }
    return @"/var/mobile/Library/TrollDecrypt/decrypted";
}

void decryptAppWithPID(pid_t pid) {
    dispatch_async(dispatch_get_main_queue(), ^{
        alertWindow = [[UIWindow alloc] initWithFrame: [UIScreen mainScreen].bounds];
        alertWindow.rootViewController = [UIViewController new];
        alertWindow.windowLevel = UIWindowLevelAlert + 1;
        [alertWindow makeKeyAndVisible];
            
        kw = alertWindow;
        if([kw respondsToSelector:@selector(topmostPresentedViewController)])
            root = [kw performSelector:@selector(topmostPresentedViewController)];
        else
            root = [kw rootViewController];
        root.modalPresentationStyle = UIModalPresentationFullScreen;
    });

    char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
    proc_pidpath(pid, pathbuf, sizeof(pathbuf));
    NSString *executable = [NSString stringWithUTF8String:pathbuf];
    NSString *path = [executable stringByDeletingLastPathComponent];
    NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bundleID = infoPlist[@"CFBundleIdentifier"];

    if (!bundleID) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [alertController dismissViewControllerAnimated:NO completion:nil];
            errorController = [UIAlertController
                alertControllerWithTitle:NSLocalizedString(@"ERROR_TITLE", @"Error: -2")
                message:[NSString stringWithFormat:NSLocalizedString(@"ERROR_BUNDLEID_MESSAGE", @"Failed to get bundle id for pid: %d"), pid]
                preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"OK_BUTTON", @"OK")
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [errorController dismissViewControllerAnimated:NO completion:nil];
                    [kw removeFromSuperview];
                    kw.hidden = YES;
                }];
            [errorController addAction:okAction];
            [root presentViewController:errorController animated:YES completion:nil];
        });
    }

    LSApplicationProxy *app = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
    if (!app) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [alertController dismissViewControllerAnimated:NO completion:nil];
            errorController = [UIAlertController
                alertControllerWithTitle:NSLocalizedString(@"ERROR_TITLE", @"Error: -3")
                message:[NSString stringWithFormat:NSLocalizedString(@"ERROR_PROXY_MESSAGE", @"Failed to get LSApplicationProxy for bundle id: %@"), bundleID]
                preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"OK_BUTTON", @"OK")
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [errorController dismissViewControllerAnimated:NO completion:nil];
                    [kw removeFromSuperview];
                    kw.hidden = YES;
                }];
            [errorController addAction:okAction];
            [root presentViewController:errorController animated:YES completion:nil];
        });
    }

    NSDictionary *appInfo = @{
        @"bundleID":bundleID,
        @"name":[app atl_nameToDisplay],
        @"version":[app atl_shortVersionString],
        @"executable":executable
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        [alertController dismissViewControllerAnimated:NO completion:nil];
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"DECRYPT_TITLE", @"Decrypt")
            message:[NSString stringWithFormat:NSLocalizedString(@"DECRYPT_CONFIRM", @"Decrypt %@?"), appInfo[@"name"]]
            preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancel = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"CANCEL_BUTTON", @"Cancel")
            style:UIAlertActionStyleCancel
            handler:nil];
        UIAlertAction *decrypt = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"CONFIRM_BUTTON", @"Yes")
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *action) {
                decryptApp(appInfo);
            }];

        [alert addAction:decrypt];
        [alert addAction:cancel];
        [root presentViewController:alert animated:YES completion:nil];
    });
}

// 其他函数保持原有逻辑不变...

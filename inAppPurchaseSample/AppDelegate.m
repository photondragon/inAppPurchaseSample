//
//  AppDelegate.m
//  inAppPurchaseSample
//
//  Created by photondragon on 16/5/1.
//  Copyright © 2016年 iosdev.net. All rights reserved.
//

#import "AppDelegate.h"
#import "IDNIaper.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	// Override point for customization after application launch.
	[IDNIaper setReceiptUploader:^(NSString *base64ReceiptData, void (^callback)(BOOL isUploadSuccess)) {

		if(0){
			// 非单机应用情况下，将收据上传至你的服务器
			NSLog(@"正在上传收据。。。");
			// 这里是模拟网络上传。。。
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				if(rand()%2==0) //随机成功或失败
				{
					NSLog(@"收据上传成功");
					callback(TRUE); // 报告上传成功
				}
				else
				{
					NSLog(@"收据上传失败");
					callback(NO); // 报告上传失败
				}
			});
		}
		else{
			// 如果是单机应用，直接从Apple服务器处获取解码的收据信息，本地处理
			[IDNIaper decryptReceiptData:base64ReceiptData callback:^(NSDictionary *receiptInfo, NSError *error) {
				if(error)
				{
					NSLog(@"解码收据失败：%@", error.localizedDescription);
					callback(NO); // 报告收据处理失败
				}
				else{
					if([receiptInfo[@"status"] integerValue]!=0) //解码失败
					{
						NSLog(@"解码收据失败(status=%@)", receiptInfo[@"status"]);
						callback(NO); // 报告收据处理失败
					}
					else{
						NSLog(@"%@", receiptInfo);
						// 购买成功， @todo +钱 +物 解锁功能
						NSLog(@"购买完成");
						callback(YES); // 报告收据处理成功
					}
				}
			}];
		}
	}];
	return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
	// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
	// Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
	// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
	// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
	// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
	// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end

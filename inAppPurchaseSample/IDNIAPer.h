//
//  IDNIAPHelper.h
//  IDNFramework
//
//  Created by photondragon on 16/5/1.
//  Copyright © 2016年 iosdev.net. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

@interface IDNIAPHelper : NSObject

/**
 *  手机是否支持IAP
 */
+ (BOOL)isSupportIAP;

/**
 *  由于某些原因，导致有些收据没有成功上传到服务器
 *  uploader方法会在适当的时机被调用，当返回TRUE时，表示上传成功
 *  如果上传失败，uploader 还会被重复调用（调用时机是不确定的）。
 *
 *  @return <#return value description#>
 */
// uploader
+ (void)setReceiptUploader:(BOOL (^)())uploader;

/**
 *  获取产品信息
 *
 *  @param productId 产品ID（在iTunes Connect网站上设置的）
 *  @param callback  返回产品信息的回调block；如果出错，错误原因通过参数error返回。
 */
+ (void)getProductWithId:(NSString*)productId callback:(void (^)(SKProduct*product, NSError*error))callback;

/**
 *  购买产品
 *
 *  callback 返回的 transaction 对象只可能是购买成功或恢复购买成功这两种状态；
 *
 *  @param product  包含产品信息的对象，通过 + (void)getProductWithId:callback: 函数获取
 *  @param callback 购买成功与否的回调block；如果出错，错误原因通过参数error返回
 */
+ (void)purchaseProduct:(SKProduct*)product callback:(void (^)(SKPaymentTransaction *transaction, NSError* error))callback;

+ (void)puchaseProductWithId:(NSString*)productId callback:(BOOL (^)(NSData*receipt, NSError*error))callback;

+ (void)restorePurchased;
+ (void)printReceipt;

@end

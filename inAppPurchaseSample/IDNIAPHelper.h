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

@end

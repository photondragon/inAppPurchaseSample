//
//  IDNIaper.h
//  IDNFramework
//
//  Created by photondragon on 16/5/1.
//  Copyright © 2016年 iosdev.net. All rights reserved.
//

#import <Foundation/Foundation.h>

/*
 IAP自身设计的问题: 
 1. IAP是为单机应用程序设计的
 假设这样一种情况：
 你正在购买一个商品(ProductID=Emotion1)，当你已经完成付款，正准备调用finishTransaction:
 结束当前交易这个时候，程序崩溃了，然后你重启程序，再次购买同一个商品，
 在调用[[SKPaymentQueue defaultQueue] addPayment:payment]之后，程序会收到前一个商品
 付款成功的通知，然后你按屏幕提示又付了款（你总共买了两次），这时你又会收到新的付款成功的通知。
 请注意，现在的问题不是你付了两次款的问题，因为有可能用户就是要买两次（比如连买两次一个月会员，
 也就是买两个月的会员），而是你发起了一次购买(addPayment:)，却收到了两次付款成功的通知，而
 且这两次通知，你无法区分哪一个通知是前一次购买的，哪一个通知属于后一次购买的。
 每收到一次付款成功的通知，你必须立即采集ReceiptData上传到你自己的服务器上，因为下一次通知来
 的时候，ReceiptData会被覆盖（除非你没有finishTransaction前一次购买）。
 两次通知对应两个ReceiptData，上传到服务器后，服务器是无法区分哪个对应前一个订单，哪个对应后
 一个订单，所以就没办法完成订单。
 （ReceiptData是加密数据，必须要到Apple的服务器上去解密，然后才能处理，完成订单。）
 所以针对同一个ProductID，同一时间只能创建一个未完成的订单。即使这样也还是有问题，比如说用户
 已经付了款，服务正在处理订单的ReceiptData；这个时候用户又要再次买这个商品，由于前一次订单还
 没完成，这时有两个选择：1. 立即取消前一个订单，生成一个新订单；2. 不创建新订单，让用户等前一
 个订单处理完。
 如果是第1种情况，前一个订单的被取消，前一个订单的ReceiptData只能用于完成新的订单，而属于第2
 次购买的ReceiptData就没有订单可完成。
 如果是第2种情况，不允许生成新的订单，但是可能用户前一个订单就没有付款，也就是第一个订单根本就
 不会完成，你不让生成新订单，那还让不让用户买东西了？
 （以上的ProductID是指苹果IAP的ProductID，不是你自己应用里的商品ID）
 
 客户端要保证不漏掉任何一个ReceiptData。
 客户端：在当前payment没有完成或取消前，或者本地还有ReceiptData没有上传至服务器前，不得发起
 新的payment，保证向服务器申请新订单之前，采集到的ReceiptData已经上传
 
 服务端允许针对同一商品同时有两个未完成订单，这样客户端就可以发起新的payment，这样就可以采集到
 已付款但未finish的payment（一次payment收到两次付款通知这种情况），然后客户端在有未上传的
 ReceiptData时不得向自己的服务器发起创建新订单的请求。
 服务器处理ReceiptData时优先完成较早的订单。在已经有两个未完成的订单的情况下，如果同时当前用户
 有ReceiptData待处理，则不生成订单，让用户稍后再试；如果没有ReceiptData待处理，则取消最早的
 订单，生成一个新订单。
 */

@interface IDNIaper : NSObject

#pragma mark - 核心方法

/**
 *  设置收据上传block
 *
 *  上传block会在后台线程中被调用，所以如果是单机程序，在向用户提供其购买的虚拟物品或附加功能
 *  时，要注意多线程问题
 *  如果你的程序没有用户系统，应该在程序启动时设置好这个block；反之应该在用户登录后设置好。
 *  所有从 Apple 收集到的收据都必须上传至服务器
 *  服务器用这些收据向Apple服务器提取付款信息，以完成订单
 *  收据中可能包含多条付款信息
 *  由于 Apple 的原因，收据中可能会重复包含以前的付款信息，也就是说有一些付款信息会被反复上传
 *  服务器必须能够正确处理这些重复上传的付款信息
 *  上传的收据中可能会包含已上传过的交易信息，有些交易信息会被反复上传，服务器必须能够正确处理
 *
 *  如何实现上传block？
 *  1. 没有用户系统的程序一般都属于单机程序，由于没有服务器，这种单机程序的上传block中需要
 *  用收据向 Apple 提取付款信息，然后向用户提供其购买的虚拟物品或附加功能，
 *  然后调用block的callback参数，传递TRUE；否则应该调用 callback(FALSE);
 *  2. 对于有用户系统的程序，上传block中应该将收据上传至服务器，成功上传后block返回TRUE。
 *  至于向 Apple 提取付款信息以及订单如何处理就是服务器的事了。
 *  @param uploader 收据上传block。会在必要的时候被调用（但调用时机不确定），如果上传成功，
 *  应该调用block的callback参数，传递TRUE；否则应该调用 callback(FALSE);
 *
 *  @param uploader 收据上传block，总是在后台线程调用。当在uploader中调用callback(YES)
 *    时，表示上传成功；调用callback(NO)时，表示上传失败；uploader方法会在适当的时机被再次
 *    被调用，直到上传成功为止。
 */
+ (void)setReceiptUploader:(void (^)(NSString*base64ReceiptData, void (^callback)(BOOL isUploadSuccess)))uploader;

/**
 *  购买产品
 *  可以简单的认为这个函数的调用与receiptUploader的调用没有固定的联系
 *
 *  @param productId 产品ID（在iTunes Connect网站上设置的）
 *  @param callback  回调block，总是在主线程调用；如果“付款”成功则error==nil；如果出错，
 *  error中包含错误原因。注意：是“付款”成功与否，不是交易成功与否
 */
+ (void)buyProductWithId:(NSString*)productId callback:(void (^)(NSError* error))callback;

#pragma mark - 辅助方法

/**
 *  从Apple服务器获取解密的ReceiptData
 *  如果是单机应用，可以在receiptUploader中调用这个方法，解密并处理ReceiptData
 *
 *  @param base64ReceiptData 待解密的ReceiptData，base64编码
 *  @param callback          回调，在主线程调用
 */
+ (void)decryptReceiptData:(NSString*)base64ReceiptData callback:(void (^)(NSDictionary *receiptInfo, NSError* error))callback;

/**
 *  当自动上传收据失败后，再次发起上传的时间间隔。最大值60秒，最小值0，默认值2
 *  如果是单机程序，应该不会失败，用不到这个间隔；
 */
+ (void)setReceiptReuploadDelayAfterFailure:(NSTimeInterval)delay;

/**
 *  手机是否支持IAP
 */
+ (BOOL)isSupportIAP;

/**
 *  设置是否是沙盒环境。默认值由宏 DEBUG 来决定。
 *  有些项目可能会删除 DEBUG 宏，所以提供这个方法来显式设置沙盒环境。
 *  但这个方法*只影响ReceiptData解密所要访问的Apple服务器*，不会改变IAP的运行环境。
 *  IAP的运行环境是由项目的provision配置文件决定的。
 */
+ (void)setIsSandboxEnv:(BOOL)yesOrNo;

@end

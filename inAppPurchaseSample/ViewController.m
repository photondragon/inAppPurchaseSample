//
//  ViewController.m
//  inAppPurchaseSample
//
//  Created by photondragon on 16/5/1.
//  Copyright © 2016年 mahu. All rights reserved.
//

#import "ViewController.h"
#import <StoreKit/StoreKit.h>
#import "IDNIAPHelper.h"

@interface ViewController ()
<SKProductsRequestDelegate,
SKPaymentTransactionObserver>

@end

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	// 监听购买结果
//	[[SKPaymentQueue defaultQueue] addTransactionObserver:self];
}

- (void)dealloc
{
//	[[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

- (IBAction)btnClick:(id)sender {

	[IDNIAPHelper getProductWithId:@"MotionMuoMuo" callback:^(SKProduct *product, NSError *error) {
		if(error){
			NSLog(@"%@", error.description);
			return;
		}

		NSLog(@"产品：%@", product.localizedTitle);
		
		[IDNIAPHelper purchaseProduct:product callback:^(SKPaymentTransaction *transaction, NSError *error) {
			if(error){
				NSLog(@"%@", error.description);
				return;
			}
			if(transaction.transactionState==SKPaymentTransactionStateRestored)
				NSLog(@"这是恢复购买");

			NSLog(@"交易ID=%@，应该将其传送给你的服务进行验证", transaction.transactionIdentifier);

			//必须结束 transaction
			[[SKPaymentQueue defaultQueue] finishTransaction: transaction];
		}];
	}];

//	if ([SKPaymentQueue canMakePayments]) {
//		// 执行下面提到的第5步：
//		[self getProductInfo];
//	} else {
//		NSLog(@"失败，用户禁止应用内付费购买.");
//	}
}

// 下面的ProductId应该是事先在itunesConnect中添加好的，已存在的付费项目。否则查询会失败。
- (void)getProductInfo {
	NSSet * set = [NSSet setWithArray:@[@"MotionMuoMuo", @"1MonthVIP"]];
	SKProductsRequest * request = [[SKProductsRequest alloc] initWithProductIdentifiers:set];
	request.delegate = self;
	[request start];
	NSLog(@"开始获取商品信息");
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction {
	// Your application should implement these two methods.
	NSString * productIdentifier = transaction.payment.productIdentifier;
//	NSString * receipt = [transaction.transactionReceipt base64EncodedString];
//	if ([productIdentifier length] > 0) {
//		// 向自己的服务器验证购买凭证
//	}

	// Remove the transaction from the payment queue.
	[[SKPaymentQueue defaultQueue] finishTransaction: transaction];

}

- (void)failedTransaction:(SKPaymentTransaction *)transaction {
	if(transaction.error.code != SKErrorPaymentCancelled) {
		NSLog(@"购买失败");
	} else {
		NSLog(@"用户取消交易");
	}
	[[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}

- (void)restoreTransaction:(SKPaymentTransaction *)transaction {
	// 对于已购商品，处理恢复购买的逻辑
	[[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}

#pragma mark - SKProductsRequestDelegate

// 以上查询的回调函数
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
//	NSArray *myProducts = response.products;
//	if (myProducts.count == 0) {
//		NSLog(@"无法获取产品信息，购买失败。");
//		return;
//	}
//	NSLog(@"商品列表：%@", myProducts);
//	SKPayment * payment = [SKPayment paymentWithProduct:myProducts[1]];
//	[[SKPaymentQueue defaultQueue] addPayment:payment];
}

#pragma mark - SKPaymentTransactionObserver

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions
{
//	for (SKPaymentTransaction *transaction in transactions)
//	{
//		switch (transaction.transactionState)
//		{
//			case SKPaymentTransactionStatePurchased://交易完成
//				NSLog(@"transactionIdentifier = %@", transaction.transactionIdentifier);
//				[self completeTransaction:transaction];
//				break;
//			case SKPaymentTransactionStateFailed://交易失败
//				[self failedTransaction:transaction];
//				break;
//			case SKPaymentTransactionStateRestored://已经购买过该商品
//				[self restoreTransaction:transaction];
//				break;
//			case SKPaymentTransactionStatePurchasing:      //商品添加进列表
//				NSLog(@"商品添加进列表");
//				break;
//			default:
//				break;
//		}
//	}
}

@end

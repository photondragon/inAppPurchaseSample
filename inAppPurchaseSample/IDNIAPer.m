//
//  IDNIAPer.m
//  IDNFramework
//
//  Created by photondragon on 16/5/1.
//  Copyright © 2016年 iosdev.net. All rights reserved.
//

#import "IDNIAPer.h"

#pragma mark - IDNIAPerReceipt

typedef BOOL (^IDNIAPerCallback)(SKPaymentTransaction *transaction, NSError* error);

@interface IDNIAPerReceipt : NSObject

@end
@implementation IDNIAPerReceipt

@end

#pragma mark - IDNIAPerPurchase

@interface IDNIAPerPurchase : NSObject
@property(nonatomic,strong) NSString* productId; //苹果的产品ID

@end
@implementation IDNIAPerPurchase

@end

#pragma mark - IDNIAPer

@interface IDNIAPer()
<SKProductsRequestDelegate,
SKPaymentTransactionObserver>

@property(nonatomic,strong) NSMutableDictionary* dicRequests;

@property(nonatomic,strong) SKPayment* currentPayment;
@property(nonatomic,strong) void (^currentPaymentCallback)(SKPaymentTransaction *transaction, NSError* error);

@property(nonatomic,strong) NSMutableDictionary* dicPurchases; //key=productId, value=IDNIAPerPurchase对象
@property(nonatomic,strong) NSMutableArray* receipts; //未上传的收据

@end

@implementation IDNIAPer

+ (instancetype)sharedInstance
{
	static id sharedInstance;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{sharedInstance = [[self alloc] initPrivate];});
	return sharedInstance;
}

+ (BOOL)isSupportIAP
{
	return [SKPaymentQueue canMakePayments];
}

+ (void)purchaseProduct:(SKProduct*)product
			   callback:(void (^)(SKPaymentTransaction *transaction, NSError* error))callback
{
	[[self sharedInstance] purchaseProduct:product callback:callback];
}

+ (void)getProductWithId:(NSString*)productId callback:(void (^)(SKProduct*product, NSError*error))callback
{
	[[self sharedInstance] getProductWithId:productId callback:callback];
}

+ (void)restorePurchased{
	[[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (instancetype)init
{
	return nil;
}

- (instancetype)initPrivate
{
	self = [super init];
	if (self) {
		_dicRequests = [NSMutableDictionary new];

		if([SKPaymentQueue canMakePayments])
			[[SKPaymentQueue defaultQueue] addTransactionObserver:self];
	}
	return self;
}

// 本地收据文件的修改日期
- (NSDate*)modificationDateOfReceipt
{
	NSURL* receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
	NSDictionary* fileAttr = [[NSFileManager defaultManager] attributesOfItemAtPath:receiptUrl.absoluteString error:nil];
	if(fileAttr==nil)
		return nil;
	return fileAttr[NSFileModificationDate];
}

- (void)dealloc
{
	if([SKPaymentQueue canMakePayments])
		[[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

// 下面的ProductId应该是事先在itunesConnect中配置好的，已存在的付费项目。否则查询会失败。
- (void)getProductWithId:(NSString*)productId callback:(void (^)(SKProduct*product, NSError*error))callback
{
	if(callback==nil)
		return;

	if(productId.length==0) //没提供productId
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"获取产品信息失败"}];
			callback(nil, error);
		});
		return;
	}

	if([SKPaymentQueue canMakePayments]==FALSE)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"应用内购买已禁用"}];
			callback(nil, error);
		});
		return;
	}

	NSSet * set = [NSSet setWithObject:productId];
	SKProductsRequest * request = [[SKProductsRequest alloc] initWithProductIdentifiers:set];
	request.delegate = self;
	[request start];

	@synchronized (self) {
		self.dicRequests[[request description]] = callback;
	}
}

- (void)didReceiveResponse:(SKProductsResponse *)response forRequest:(SKProductsRequest *)request
{
	void (^callback)(SKProduct*product, NSError*error);

	@synchronized (self) {
		callback = self.dicRequests[[request description]];
		[self.dicRequests removeObjectForKey:[request description]];
	}

	if(callback==nil) //无效的响应（实际中应该不会出现）
		return;

	NSError* error;
	SKProduct* product;

	NSArray *myProducts = response.products;
	if (myProducts.count == 0) {
		product = nil;
		error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"产品不存在"}];
	}
	else{
		product = myProducts[0];
		error = nil;
	}
	callback(product, error);
}

//- (void)puchaseProductWithId:(NSString*)productId callback:(BOOL (^)(NSData*receipt, NSError*error))callback
//{
//	__weak __typeof(self) wself = self;
//	[self getProductWithId:productId callback:^(SKProduct *product, NSError *error) {
//		__typeof(self) sself = wself;
//		[sself purchaseProduct:product callback:^(SKPaymentTransaction *transaction, NSError *error) {
//			<#code#>
//		}];
//	}];
//}

- (void)purchaseProduct:(SKProduct*)product
				callback:(void (^)(SKPaymentTransaction *transaction, NSError* error))callback
{
	NSAssert(callback, @"callback参数不可为nil");

	if(product==nil){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"参数product==nil"}];
			callback(nil, error);
		});
		return;
	}

	if([SKPaymentQueue canMakePayments]==FALSE)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"应用内购买已禁用"}];
			callback(nil, error);
		});
		return;
	}

	SKMutablePayment * payment = [SKMutablePayment paymentWithProduct:product];
//	payment.applicationUsername = @"HelloWorld";

	IDNIAPerPurchase* purchase = [IDNIAPerPurchase new];
	purchase.productId = product.productIdentifier;

	@synchronized (self) {
		if(self.currentPayment) //正在购买
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"请等待之前的购买结束"}];
				callback(nil, error);
			});
			return;
		}
		self.currentPayment = payment;
		self.currentPaymentCallback = callback;
	}

	[[SKPaymentQueue defaultQueue] addPayment:payment];
}

- (void)purchaseEndedWithTransactions:(NSArray*)transactions
{
	for (SKPaymentTransaction *transaction in transactions)
	{
		switch (transaction.transactionState)
		{
			case SKPaymentTransactionStatePurchased://交易完成
				NSLog(@"state=%@", @"Purchased");
				[self completeTransaction:transaction];
				break;
			case SKPaymentTransactionStateRestored://恢复购买（没有调用finishTransaction:的）
				NSLog(@"state=%@", @"Restored");
				[self completeTransaction:transaction];
				break;
			case SKPaymentTransactionStateFailed://交易失败
				NSLog(@"state=%@", @"Failed");
				[self failedTransaction:transaction];
				break;
			case SKPaymentTransactionStatePurchasing: //商品加入服务器队列
				NSLog(@"state=%@", @"Purchasing");
				break;
			case SKPaymentTransactionStateDeferred:
				NSLog(@"state=%@", @"Deferred");
				break;
			default:
				break;
		}
	}
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction {

	void (^callback)(SKPaymentTransaction *transaction, NSError* error);

	@synchronized (self) {
		callback = self.currentPaymentCallback;
		self.currentPayment = nil;
		self.currentPaymentCallback = nil;
	}

	if(transaction.transactionState==SKPaymentTransactionStateRestored)
		NSLog(@"       transId=%@, originTransId=%@", transaction.transactionIdentifier, transaction.originalTransaction.transactionIdentifier);
	else
		NSLog(@"       transId=%@", transaction.transactionIdentifier);

	if(callback)
		callback(transaction, nil);
	else{
		[[SKPaymentQueue defaultQueue] finishTransaction: transaction];
		NSLog(@"finish transId=%@", transaction.transactionIdentifier);
		NSData* receiptData = [NSData dataWithContentsOfURL:[[NSBundle mainBundle] appStoreReceiptURL]];
		NSLog(@"receiptDataLenght=%d", (int)receiptData.length);
		[IDNIAPer printReceipt];
	}
}

- (void)failedTransaction:(SKPaymentTransaction *)transaction {

	void (^callback)(SKPaymentTransaction *transaction, NSError* error);

	@synchronized (self) {
		callback = self.currentPaymentCallback;
		self.currentPayment = nil;
		self.currentPaymentCallback = nil;
	}

	//无需把transaction对象返回到外部，直接关闭失败的交易
	[[SKPaymentQueue defaultQueue] finishTransaction: transaction];
	NSLog(@"finish transId=%@", transaction.transactionIdentifier);
	NSData* receiptData = [NSData dataWithContentsOfURL:[[NSBundle mainBundle] appStoreReceiptURL]];
	NSLog(@"receiptDataLenght=%d", (int)receiptData.length);
	[IDNIAPer printReceipt];

	NSString* reason;
	if(transaction.error.code != SKErrorPaymentCancelled)
		reason = @"购买失败";
	else
		reason = @"用户取消了交易";

	NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:reason}];

	if(callback)
		callback(nil, error);
}

+ (void)printReceipt
{
	NSURL* receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
	NSData* receiptData = [NSData dataWithContentsOfURL:receiptUrl];
	if(receiptData==nil)
		return;

	NSError* error = nil;
//	[[NSFileManager defaultManager] removeItemAtURL:receiptUrl error:&error];
//	if(error)
//		NSLog(@"删除失败%@", error.localizedDescription);

	NSDictionary *requestContents = @{
									  @"receipt-data": [receiptData base64EncodedStringWithOptions:0]
									  };
	NSData *requestData = [NSJSONSerialization dataWithJSONObject:requestContents
														  options:0
															error:&error];

	if (!requestData) { /* ... Handle error ... */ }

	// Create a POST request with the receipt data.
	//	NSURL *storeURL = [NSURL URLWithString:@"https://buy.itunes.apple.com/verifyReceipt"];
	NSURL *storeURL = [NSURL URLWithString:@"https://sandbox.itunes.apple.com/verifyReceipt"];

	NSMutableURLRequest *storeRequest = [NSMutableURLRequest requestWithURL:storeURL];
	[storeRequest setHTTPMethod:@"POST"];
	[storeRequest setHTTPBody:requestData];

	// Make a connection to the iTunes Store on a background queue.
	NSOperationQueue *queue = [[NSOperationQueue alloc] init];
	[NSURLConnection sendAsynchronousRequest:storeRequest queue:queue
						   completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
							   if (connectionError) {
								   /* ... Handle error ... */
							   } else {
								   NSError *error;
								   NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
								   if (!jsonResponse) { /* ... Handle error ...*/ }
								   /* ... Send a response back to the device ... */
								   NSLog(@"receipt=%@", jsonResponse);
							   }
						   }];
	// ********test end*******
}

#pragma mark - SKProductsRequestDelegate

// 以上查询的回调函数
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
	[self didReceiveResponse:response forRequest:request];
}

#pragma mark - SKPaymentTransactionObserver

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions
{
	NSLog(@"updatedTransactions");
	[self purchaseEndedWithTransactions:transactions];
}

- (void)paymentQueue:(SKPaymentQueue *)queue removedTransactions:(NSArray<SKPaymentTransaction *> *)transactions
{
	NSLog(@"removedTransactions");
	NSLog(@"-------------------");
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
	NSLog(@"restoreCompletedTransactionsFailedWithError");
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
	NSLog(@"restoreCompletedTransactionsFinished");
}
- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray<SKDownload *> *)downloads
{
	NSLog(@"updatedDownloads");
}

@end

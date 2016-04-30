//
//  IDNIAPHelper.m
//  IDNFramework
//
//  Created by photondragon on 16/5/1.
//  Copyright © 2016年 iosdev.net. All rights reserved.
//

#import "IDNIAPHelper.h"

@interface IDNIAPHelper()
<SKProductsRequestDelegate,
SKPaymentTransactionObserver>

@property(nonatomic,strong) NSMutableDictionary* dicRequests;
@property(nonatomic,strong) NSMutableDictionary* dicPayments;

@end

@implementation IDNIAPHelper

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

- (instancetype)init
{
	return nil;
}

- (instancetype)initPrivate
{
	self = [super init];
	if (self) {
		_dicRequests = [NSMutableDictionary new];
		_dicPayments = [NSMutableDictionary new];

		if([SKPaymentQueue canMakePayments])
			[[SKPaymentQueue defaultQueue] addTransactionObserver:self];
	}
	return self;
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

	if([IDNIAPHelper isSupportIAP]==FALSE)
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

	if([IDNIAPHelper isSupportIAP]==FALSE)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"应用内购买已禁用"}];
			callback(nil, error);
		});
		return;
	}

	SKMutablePayment * payment = [SKMutablePayment paymentWithProduct:product];
	payment.requestData = [NSData new]; //用作payment对象的唯一标识。因为transaction中的payment是拷贝过的，不是原始的payment，但它们的requestData是同一个对象
	[[SKPaymentQueue defaultQueue] addPayment:payment];

	NSString* key = [NSString stringWithFormat:@"%p", payment.requestData];
	@synchronized (self) {
		self.dicPayments[key] = callback;
	}
}

- (void)purchaseEndedWithTransactions:(NSArray*)transactions
{
	for (SKPaymentTransaction *transaction in transactions)
	{
		switch (transaction.transactionState)
		{
			case SKPaymentTransactionStatePurchased://交易完成
			case SKPaymentTransactionStateRestored://已经购买过该商品
				[self completeTransaction:transaction];
				break;
			case SKPaymentTransactionStateFailed://交易失败
				[self failedTransaction:transaction];
				break;
			case SKPaymentTransactionStatePurchasing: //商品加入服务器队列
				break;
			default:
				break;
		}
	}
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction {

	void (^callback)(SKPaymentTransaction *transaction, NSError* error);

	NSString* key = [NSString stringWithFormat:@"%p", transaction.payment.requestData];

	@synchronized (self) {
		callback = self.dicPayments[key];
		[self.dicPayments removeObjectForKey:key];
	}

	if(callback)
		callback(transaction, nil);
}

- (void)failedTransaction:(SKPaymentTransaction *)transaction {

	void (^callback)(SKPaymentTransaction *transaction, NSError* error);

	NSString* key = [NSString stringWithFormat:@"%p", transaction.payment.requestData];

	@synchronized (self) {
		callback = self.dicPayments[key];
		[self.dicPayments removeObjectForKey:key];
	}

	//无需把transaction对象返回到外部，直接关闭失败的交易
	[[SKPaymentQueue defaultQueue] finishTransaction: transaction];

	NSString* reason;
	if(transaction.error.code != SKErrorPaymentCancelled)
		reason = @"购买失败";
	else
		reason = @"用户取消了交易";

	NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:reason}];

	if(callback)
		callback(nil, error);
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
	[self purchaseEndedWithTransactions:transactions];
}

@end

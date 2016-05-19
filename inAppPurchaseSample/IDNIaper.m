//
//  IDNIaper.m
//  IDNFramework
//
//  Created by photondragon on 16/5/1.
//  Copyright © 2016年 iosdev.net. All rights reserved.
//

#import "IDNIaper.h"
#import <StoreKit/StoreKit.h>

#ifdef DDLogDebug
#define InnerLogError	DDLogError
#define InnerLogWarn	DDLogWarn
#define InnerLogInfo	DDLogInfo
#define InnerLogDebug	DDLogDebug
#define InnerLogVerbose	DDLogVerbose
#else
#define InnerLogError	NSLog
#define InnerLogWarn	NSLog
#define InnerLogInfo	NSLog
#define InnerLogDebug	NSLog
#define InnerLogVerbose	NSLog
#endif
#define InnerLog InnerLogDebug

#pragma mark - IDNIaperReceipt

typedef BOOL (^IDNIaperCallback)(SKPaymentTransaction *transaction, NSError* error);

/*
 收据来自收据文件[[NSBundle mainBundle] appStoreReceiptURL]
 这个里面包含了多个购买信息
 包括最近一个商品的购买信息（可能是消耗品，也可能是永久商品）
 和所有永久商品的购买信息
 */
@interface IDNIaperReceipt : NSObject
<NSCoding>
@property(nonatomic) int receiptId; //自动生成的id，内部使用
@property(nonatomic,strong) NSData* receiptData; //数据数据
@property(nonatomic,strong) NSDate* modicationDate; //修改时间
//@property(nonatomic,strong) NSDictionary* receiptInfo; //用receiptData从apple服务器获取
@end
@implementation IDNIaperReceipt

// 本地收据文件的修改日期
+ (NSDate*)modificationDateOfReceipt
{
	NSURL* receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
	NSDictionary* fileAttr = [[NSFileManager defaultManager] attributesOfItemAtPath:receiptUrl.absoluteString error:nil];
	if(fileAttr==nil)
		return nil;
	return fileAttr[NSFileModificationDate];
}

// 采集本地的收据文件
+ (instancetype)gatherReceipt
{
	@synchronized (self) {
		NSURL* receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
		NSData* receiptData = [NSData dataWithContentsOfURL:receiptUrl];
		if(receiptData.length==0)
			return nil;
		IDNIaperReceipt* receipt = [[self alloc] init];
		receipt.receiptData = receiptData;
		receipt.modicationDate = [self modificationDateOfReceipt];
		return receipt;
	}
}

+ (NSOperationQueue*)queue
{
	static NSOperationQueue *queue;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		queue = [[NSOperationQueue alloc] init];
		queue.name = @"IDNIaperQueue";
	});
	return queue;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		static int nextId = 1;
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			nextId = (int)[NSDate timeIntervalSinceReferenceDate];
		});
		_receiptId = nextId++;
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self) {
		_receiptId = [coder decodeIntForKey:@"receiptId"];
		_receiptData = [coder decodeObjectForKey:@"receiptData"];
		_modicationDate = [coder decodeObjectForKey:@"modicationDate"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeInt:_receiptId forKey:@"receiptId"];
	[aCoder encodeObject:_receiptData forKey:@"receiptData"];
	[aCoder encodeObject:_modicationDate forKey:@"modicationDate"];
}

@end

#pragma mark - IDNIaper

static BOOL isSandboxEnv; //是否是沙盒环境

@interface IDNIaper()
<SKProductsRequestDelegate,
SKPaymentTransactionObserver>

@property(nonatomic,strong) NSMutableDictionary* dicRequests;

@property(nonatomic,strong) void (^receiptUploader)(NSString*base64ReceiptData, void (^callback)(BOOL isUploadSuccess));
@property(nonatomic) NSTimeInterval reuploadDelayAfterFailure;

@property(nonatomic,strong) SKPayment* currentPayment;
@property(nonatomic,strong) void (^currentPaymentCallback)(SKPaymentTransaction *transaction, NSError* error);
@property(nonatomic,strong) SKPaymentTransaction* currentPaymentTransaction;
@property(nonatomic,strong) IDNIaperReceipt* currentPaymentReceipt;

@property(nonatomic,strong) NSMutableArray* receipts; //未上传的收据
@property(nonatomic) BOOL uploading; //是否正在上传receipt

@property(nonatomic,strong) NSData* lastReceiptData; //最近一次采集的收据

@end

@implementation IDNIaper

#pragma mark - 类方法、外壳方法、辅助方法

+ (IDNIaper*)sharedInstance
{
	static IDNIaper* sharedInstance;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[self alloc] initPrivate];
		[sharedInstance gatherReceipt];
	});
	return sharedInstance;
}

+ (void)setIsSandboxEnv:(BOOL)yesOrNo
{
	isSandboxEnv = yesOrNo;
}

+ (BOOL)isSupportIAP
{
	return [SKPaymentQueue canMakePayments];
}

+ (void)setReceiptReuploadDelayAfterFailure:(NSTimeInterval)delay
{
	if(delay<0)
		delay = 2.0;
	else if(delay>60)
		delay = 60;
	[self sharedInstance].reuploadDelayAfterFailure = delay;
}

+ (void)restorePurchased{
	[[SKPaymentQueue defaultQueue] restoreCompletedTransactions]; // 这方法调用了也不一定有用，直接发起payment更有效一点
}

+ (NSString*)getReceiptsFilePath
{
	static NSString* file = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		file = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"iapReceipts.dat"];
	});
	return file;
}

// 从Apple服务器获取解密的收据
+ (void)decryptReceiptData:(NSString*)base64ReceiptData callback:(void (^)(NSDictionary *receiptInfo, NSError* error))callback
{
	if(callback==nil)
		return;

	if(base64ReceiptData.length==0){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"无效的参数base64ReceiptData"}];
			callback(nil, error);
		});
		return;
	}

	NSDictionary *content = @{@"receipt-data": base64ReceiptData};
	NSError* error = nil;
	NSData *requestData = [NSJSONSerialization dataWithJSONObject:content
														  options:0
															error:&error];

	if (!requestData) {
		dispatch_async(dispatch_get_main_queue(), ^{
			NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"编码请求数据失败"}];
			callback(nil, error);
		});
		return;
	}

	NSURL *storeURL = nil;
	if(isSandboxEnv)
		storeURL = [NSURL URLWithString:@"https://sandbox.itunes.apple.com/verifyReceipt"];
	else
		storeURL = [NSURL URLWithString:@"https://buy.itunes.apple.com/verifyReceipt"];

	NSMutableURLRequest *storeRequest = [NSMutableURLRequest requestWithURL:storeURL];
	[storeRequest setHTTPMethod:@"POST"];
	[storeRequest setHTTPBody:requestData];

	[NSURLConnection sendAsynchronousRequest:storeRequest queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
		NSError *error = nil;
		NSDictionary *info = nil;
		if (connectionError) {
			error = connectionError;
		} else {
			NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
			if (!jsonResponse) {
				if(error==nil)
					error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"返回数据无法解析"}];
			}
			else
			{
				info = jsonResponse;
				error = nil;
			}
		}
		callback(info, error);
	}];
}

#pragma mark - 核心接口方法

+ (void)setReceiptUploader:(void (^)(NSString*base64ReceiptData, void (^callback)(BOOL isUploadSuccess)))uploader
{
	[self sharedInstance].receiptUploader = uploader;
}

/**
 *  获取产品信息
 *
 *  @param productId 产品ID（在iTunes Connect网站上设置的）
 *  @param callback  返回产品信息的回调block；如果出错，错误原因通过参数error返回。
 */
+ (void)getProductWithId:(NSString*)productId callback:(void (^)(SKProduct*product, NSError*error))callback
{
	[[self sharedInstance] getProductWithId:productId callback:callback];
}

/**
 *  购买产品
 *
 *  callback 返回的 transaction 对象只可能是购买成功或恢复购买成功这两种状态；
 *
 *  @param product  包含产品信息的对象，通过 + (void)getProductWithId:callback: 函数获取
 *  @param callback 购买成功与否的回调block；如果出错，错误原因通过参数error返回
 */
+ (void)buyProduct:(SKProduct*)product
			   callback:(void (^)(SKPaymentTransaction *transaction, NSError* error))callback
{
	[[self sharedInstance] buyProduct:product callback:callback];
}

// 这个方法内部是合并调用了上面两个方法
+ (void)buyProductWithId:(NSString*)productId callback:(void (^)(NSError* error))callback
{
	[[self sharedInstance] buyProductWithId:productId callback:callback];
}

#pragma mark - 实例方法

- (instancetype)init
{
	return nil;
}

- (instancetype)initPrivate
{
	self = [super init];
	if (self) {
#ifdef DEBUG
		isSandboxEnv = YES;
#else
		isSandboxEnv = NO;
#endif

		_reuploadDelayAfterFailure = 2.0;
		_dicRequests = [NSMutableDictionary new];

		NSDictionary* saves = nil;
		NSData* data = [NSData dataWithContentsOfFile:[IDNIaper getReceiptsFilePath]];
		if(data)
			saves = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		_receipts = [saves objectForKey:@"receipts"];
		if(_receipts==nil)
			_receipts = [NSMutableArray new];
		_lastReceiptData = [saves objectForKey:@"lastReceiptData"];
		_currentPaymentReceipt = [saves objectForKey:@"currentPaymentReceipt"];
		if(_currentPaymentReceipt){
			[_receipts addObject:_currentPaymentReceipt];
			_currentPaymentReceipt = nil;
			[self saveReceipts];
			[self processReceipts];
		}

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

- (void)buyProductWithId:(NSString*)productId callback:(void (^)(NSError* error))callback
{
	[self getProductWithId:productId callback:^(SKProduct *product, NSError *error) {
		if(error){
			if(callback)
				callback(error);
			return;
		}

		NSLog(@"产品：%@", product.localizedTitle);

		[self buyProduct:product callback:^(SKPaymentTransaction *transaction, NSError *error) {
			if(callback)
				callback(error);
		}];
	}];
}

- (void)buyProduct:(SKProduct*)product
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

	@synchronized (self) {
		if(self.currentPayment) //正在购买
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"请等待之前的购买结束"}];
				callback(nil, error);
			});
			return;
		}
		if(_receipts.count) //还有收据没有成功上传，不能发起新的购买
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:@"正在处理收据，请稍后再试"}];
				callback(nil, error);
			});
			return;
		}
		self.currentPayment = payment;
		self.currentPaymentCallback = callback;
	}

	[[SKPaymentQueue defaultQueue] addPayment:payment];
}

- (void)currentPaymentStartWithTransaction:(SKPaymentTransaction*)transaction
{
	@synchronized (self) {
		if(self.currentPayment==nil) //当前没有payment
			return;
		if(self.currentPaymentTransaction) //当前payment已经有了transaction
		{
			// 以下代码在实际中永远不应该运行，否则就是bug
			if(self.currentPaymentTransaction.transactionIdentifier == transaction.transactionIdentifier)
			{
				InnerLogError(@"系统重复提交transaction(%@) Purchasing状态", transaction.transactionIdentifier);
			}
			else
			{
				InnerLogError(@"当前payment(productId=%@)已经有了transaction(%@)，又产生一个新的transaction(%@)，这种情况不应该出现", self.currentPayment.productIdentifier, self.currentPaymentTransaction.transactionIdentifier, transaction.transactionIdentifier);
				return;
			}
		}
		else
		{
			self.currentPaymentTransaction = transaction;
		}
	}
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction {

	@synchronized (self) {
		if(self.currentPayment==nil || transaction != self.currentPaymentTransaction)// 不属于当前的payment
		{
			if(transaction.transactionState==SKPaymentTransactionStateRestored)//永久商品
			{
				InnerLogInfo(@"恢复永久商品: productId=%@, transId=%@",transaction.originalTransaction.payment.productIdentifier, transaction.originalTransaction.transactionIdentifier);
				//永久商品的不用采集收据，因为其会包含在当前购买商品的收据中
			}
			else
			{
				InnerLogInfo(@"恢复消耗商品: productId=%@, transId=%@",transaction.payment.productIdentifier, transaction.transactionIdentifier);
				[self gatherReceipt]; //采集收据。这个函数有点"慢"
			}
			[[SKPaymentQueue defaultQueue] finishTransaction: transaction];
		}
		else //属于当前payment
		{
			if(transaction.transactionState==SKPaymentTransactionStateRestored)
				NSLog(@"restored  transId=%@, originTransId=%@", transaction.transactionIdentifier, transaction.originalTransaction.transactionIdentifier);//实际中应该不会运行到这里
			else
				NSLog(@"purchased transId=%@", transaction.transactionIdentifier);
			
			[self gatherAndUploadCurrentPaymentReceipt]; //采集并上传当前payment收据

			[[SKPaymentQueue defaultQueue] finishTransaction: transaction];
			NSLog(@"finished  transId=%@", transaction.transactionIdentifier);
		}
	}
}

- (void)failedTransaction:(SKPaymentTransaction *)transaction {

	void (^callback)(SKPaymentTransaction *transaction, NSError* error);

	@synchronized (self) {
		callback = self.currentPaymentCallback;
		self.currentPayment = nil;
		self.currentPaymentCallback = nil;
		self.currentPaymentTransaction = nil;
		self.currentPaymentReceipt = nil;
	}

	//无需把transaction对象返回到外部，直接关闭失败的交易
	[[SKPaymentQueue defaultQueue] finishTransaction: transaction];
	NSLog(@"finished  transId=%@", transaction.transactionIdentifier);

	NSString* reason;
	if(transaction.error.code != SKErrorPaymentCancelled)
		reason = @"付款失败";
	else
		reason = @"付款取消";

	NSError* error = [NSError errorWithDomain:NSStringFromClass(self.class) code:0 userInfo:@{NSLocalizedDescriptionKey:reason}];

	if(callback)
		callback(nil, error);
}

- (void)gatherReceipt
{
	IDNIaperReceipt* receipt = [IDNIaperReceipt gatherReceipt];
	if(receipt==nil) //没有收据文件
		return;

	if([receipt.receiptData isEqualToData:self.lastReceiptData]) //收据文件没有被修改过
		return;
	else{
		for (IDNIaperReceipt* r in _receipts) {
			if([receipt.receiptData isEqualToData:r.receiptData]) //收据文件已经采集过了
				return;
		}
	}

	InnerLogDebug(@"采集到收据 dataLength=%d", (int)receipt.receiptData.length);

	self.lastReceiptData = receipt.receiptData;

	[self.receipts addObject:receipt]; //加入收据采集数组
	[self saveReceipts];

	[self processReceipts];
}

//采集并上传当前payment收据。如果上传失败，则将receipt放入后台队列继续上传；不管上传成功还是失败，都会结束当前payment，并调用callback通知付款成功
- (void)gatherAndUploadCurrentPaymentReceipt
{
	IDNIaperReceipt* receipt = [IDNIaperReceipt gatherReceipt];

	NSAssert(receipt, @"没有找到收据文件, 不应该出现这种情况");

	if([receipt.receiptData isEqualToData:self.lastReceiptData]) //没有收据文件或收据文件没有被修改过
	{
		InnerLogError(@"不应该出现这种情况6aer3666");
	}

	NSLog(@"receiptDataLength=%d", (int)receipt.receiptData.length);

	self.lastReceiptData = receipt.receiptData;
	self.currentPaymentReceipt = receipt;

	[self saveReceipts];

	__weak __typeof(self) wself = self;
	if(_receiptUploader==nil)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			__typeof(self) sself = wself;
			[sself currentReceiptUploadEnded:NO];
		});
	}
	else
	{
		NSString* receiptString = [receipt.receiptData base64EncodedStringWithOptions:0];
		void (^uploader)(NSString*base64ReceiptData, void (^callback)(BOOL isUploadSuccess)) = _receiptUploader;

		__weak __typeof(self) wself = self;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			uploader(receiptString, ^(BOOL isUploadSuccess){
				__typeof(self) sself = wself;
				[sself currentReceiptUploadEnded:isUploadSuccess];
			});
		});
	}
}

- (void)processReceipts
{
	@synchronized (self) {
		if(self.uploading || _receiptUploader==nil)
			return;

		while (1) {
			IDNIaperReceipt* receipt = [self.receipts firstObject];
			if(receipt==nil)
				break;

			int receiptId = receipt.receiptId;
			NSString* receiptString = [receipt.receiptData base64EncodedStringWithOptions:0];
			void (^uploader)(NSString*base64ReceiptData, void (^callback)(BOOL isUploadSuccess)) = _receiptUploader;

			self.uploading = YES;

			__weak __typeof(self) wself = self;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				uploader(receiptString, ^(BOOL isUploadSuccess){
					__typeof(self) sself = wself;
					if(isUploadSuccess)
						[sself uploadEndedWithReceiptId:receiptId];
					else
						[sself uploadEndedWithReceiptId:0];
				});
			});

			break;
		}
	}
}

// 如果receiptId==0，表示上传失败
- (void)uploadEndedWithReceiptId:(int)receiptId
{
	@synchronized (self) {
		NSTimeInterval delay = 0;
		if(receiptId)
		{
			for (NSInteger i=0; i<_receipts.count; i++) {
				IDNIaperReceipt* r = _receipts[i];
				if(r.receiptId == receiptId)
				{
					[_receipts removeObjectAtIndex:i];
					[self saveReceipts];
					break;
				}
			}
		}
		else //失败
			delay = _reuploadDelayAfterFailure;

		self.uploading = NO;
		if(_receipts.count>0)
		{
			if(delay>0)
			{
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
					[self processReceipts];
				});
			}
			else{
				dispatch_async(dispatch_get_main_queue(), ^{
					[self processReceipts];
				});
			}
		}
	}
}

- (void)currentReceiptUploadEnded:(BOOL)isUploadSuccess
{
	SKPaymentTransaction *transaction;
	void (^callback)(SKPaymentTransaction *transaction, NSError* error);

	@synchronized (self) {

		callback = self.currentPaymentCallback;
		transaction = self.currentPaymentTransaction;

		IDNIaperReceipt* receipt = self.currentPaymentReceipt;

		self.currentPayment = nil;
		self.currentPaymentCallback = nil;
		self.currentPaymentTransaction = nil;
		self.currentPaymentReceipt = nil;

		if(isUploadSuccess==NO) // 收据上传成功
		{
			InnerLogError(@"收据上传失败，一般是由于网络原因导致收据无法上传至服务器");
			[_receipts insertObject:receipt atIndex:0]; //插入收据上传队列
			[self saveReceipts]; //这是为了保存 self.receipts
		}
		else
			[self saveReceipts]; //这里为了保存 self.currentPaymentReceipt = nil
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		callback(transaction, nil);
	});

	[self processReceipts];
}

- (void)saveReceipts{
	@synchronized (self) {
		NSMutableDictionary* saves = [NSMutableDictionary new];
		if(_lastReceiptData)
			saves[@"lastReceiptData"] = _lastReceiptData;
		if(_receipts)
			saves[@"receipts"] = _receipts;
		if(_currentPaymentReceipt)
			saves[@"currentPaymentReceipt"] = _currentPaymentReceipt;

		NSData* data = [NSKeyedArchiver archivedDataWithRootObject:saves];
		if([data writeToFile:[IDNIaper getReceiptsFilePath] atomically:YES])
			;//InnerLogDebug(@"保存收据成功");
		else
			;//InnerLogError(@"保存收据失败");
	}
}

- (void)setReceiptUploader:(void (^)(NSString *, void (^)(BOOL)))receiptUploader
{
	_receiptUploader = receiptUploader;
	if(receiptUploader)
		[self processReceipts]; // 尝试上传或处理收据
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
	NSLog(@"*updatedTransactions");

	for (SKPaymentTransaction *transaction in transactions)
	{
		switch (transaction.transactionState)
		{
			case SKPaymentTransactionStatePurchased://交易完成
				NSLog(@"state = %@", @"Purchased");
				[self completeTransaction:transaction];
				break;
			case SKPaymentTransactionStateRestored://恢复购买（没有调用finishTransaction:的）
				NSLog(@"state = %@", @"Restored");
				[self completeTransaction:transaction];
				break;
			case SKPaymentTransactionStateFailed://交易失败
				NSLog(@"state = %@", @"Failed");
				[self failedTransaction:transaction];
				break;
			case SKPaymentTransactionStatePurchasing: //商品加入服务器队列。只有这个transaction才是当前payment对应的transaction
				NSLog(@"state = %@", @"Purchasing");
				[self currentPaymentStartWithTransaction:transaction];
				break;
			case SKPaymentTransactionStateDeferred:
				NSLog(@"state = %@", @"Deferred");
				break;
			default:
				break;
		}
	}
}

- (void)paymentQueue:(SKPaymentQueue *)queue removedTransactions:(NSArray<SKPaymentTransaction *> *)transactions
{
	NSLog(@"*removedTransactions");
	NSLog(@"-------------------");
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
	NSLog(@"*restoreCompletedTransactionsFailedWithError");
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
	NSLog(@"*restoreCompletedTransactionsFinished");
}
- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray<SKDownload *> *)downloads
{
	NSLog(@"*updatedDownloads");
}

@end

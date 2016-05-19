//
//  ViewController.m
//  inAppPurchaseSample
//
//  Created by photondragon on 16/5/1.
//  Copyright © 2016年 iosdev.net. All rights reserved.
//

#import "ViewController.h"

#import "IDNIaper.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIView *loadingView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *indicator;
@property(nonatomic) BOOL loading;

@end

@implementation ViewController

- (void)setLoading:(BOOL)loading
{
	_loading = loading;
	if(_loading)
	{
		self.loadingView.hidden = NO;
		[self.indicator startAnimating];
	}
	else{
		[self.indicator stopAnimating];
		self.loadingView.hidden = YES;
	}
}

- (IBAction)onVip1Month:(id)sender {
	[self buy:@"1MonthVIP"];
}

- (IBAction)onVip3Month:(id)sender {
	[self buy:@"3MonthVIP"];
}

- (IBAction)onMotionMuoMuo:(id)sender {
	[self buy:@"MotionMuoMuo"];
}

- (IBAction)onMotionLeLe:(id)sender {
	[self buy:@"MotionLeLe"];
}

- (void)buy:(NSString*)productId {

	if(self.loading)
		return;

	self.loading = YES;
	__weak __typeof(self) wself = self;
	[IDNIaper buyProductWithId:productId callback:^(NSError *error) {

		__typeof(self) sself = wself;
		sself.loading = NO;

		if(error)
			NSLog(@"付款失败：%@", error.localizedDescription);
		else
			NSLog(@"付款成功");
	}];
}

@end

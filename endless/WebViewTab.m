#import "AppDelegate.h"
#import "URLInterceptor.h"
#import "WebViewTab.h"

#import "NSString+JavascriptEscape.h"

@implementation WebViewTab

static NSString *_javascriptToInject;

AppDelegate *appDelegate;
float progress;

+ (NSString *)javascriptToInject
{
	if (!_javascriptToInject) {
		NSString *path = [[NSBundle mainBundle] pathForResource:@"injected" ofType:@"js"];
		_javascriptToInject = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	}
	
	return _javascriptToInject;
}

+ (WebViewTab *)openedWebViewTabByRandID:(NSString *)randID
{
	for (WebViewTab *wvt in [[appDelegate webViewController] webViewTabs]) {
		if ([wvt randID] != nil && [[wvt randID] isEqualToString:randID]) {
			return wvt;
		}
	}
	
	return nil;
}

- (id)initWithFrame:(CGRect)frame
{
	appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];

	_viewHolder = [[UIView alloc] initWithFrame:frame];
	
	_webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
	[_webView setDelegate:self];
	[_webView setScalesPageToFit:YES];
	[_webView setAutoresizesSubviews:YES];
	
	/* swiping goes back and forward in current webview */
	UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRightAction:)];
	[swipeRight setDirection:UISwipeGestureRecognizerDirectionRight];
	[swipeRight setDelegate:self];
	[self.webView addGestureRecognizer:swipeRight];
 
	UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeftAction:)];
	[swipeLeft setDirection:UISwipeGestureRecognizerDirectionLeft];
	[swipeLeft setDelegate:self];
	[self.webView addGestureRecognizer:swipeLeft];

	_titleHolder = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
	[_titleHolder setBackgroundColor:[UIColor colorWithRed:0 green:0 blue:0 alpha:0.75]];

	_title = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
	[_title setTextColor:[UIColor whiteColor]];
	[_title setFont:[UIFont boldSystemFontOfSize:12.0]];
	[_title setLineBreakMode:NSLineBreakByTruncatingTail];
	[_title setTextAlignment:NSTextAlignmentCenter];
	
	_closer = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
	[_closer setTextColor:[UIColor whiteColor]];
	[_closer setFont:[UIFont systemFontOfSize:19.0]];
	[_closer setText:[NSString stringWithFormat:@"%C", 0x2715]];

	[_viewHolder addSubview:_titleHolder];
	[_viewHolder addSubview:_title];
	[_viewHolder addSubview:_closer];
	[_viewHolder addSubview:_webView];
	
	[self updateFrame:frame];

	[self zoomNormal];
	
	[self setSecureMode:WebViewTabSecureModeInsecure];

	return self;
}

- (void)updateFrame:(CGRect)frame
{
	[self.viewHolder setFrame:frame];
	[self.webView setFrame:CGRectMake(0, frame.origin.y, frame.size.width, frame.size.height)];
	[self.titleHolder setFrame:CGRectMake(0, frame.origin.y - 20, frame.size.width, 22)];
	[self.title setFrame:CGRectMake(24, frame.origin.y - 16, frame.size.width - 8 - 24, 12)];
	[self.closer setFrame:CGRectMake(2, frame.origin.y - 18, 18, 18)];
}

- (void)loadURL:(NSURL *)u
{
	[self setUrl:u];
	[self.webView stopLoading];
	
	NSMutableURLRequest *ur = [NSMutableURLRequest requestWithURL:u];
	[NSURLProtocol setProperty:[NSString stringWithFormat:@"%lu", (unsigned long)[self hash]] forKey:@"WebViewTab" inRequest:ur];
	
	/* remember that this was the directly entered URL */
	[NSURLProtocol setProperty:@YES forKey:ORIGIN_KEY inRequest:ur];
	
	[self setSecureMode:WebViewTabSecureModeInsecure];
	
	[self.webView loadRequest:ur];
}

- (void)webViewDidStartLoad:(UIWebView *)__webView
{
	[self setProgress:0.1];
	
	if (self.url == nil)
		self.url = [[__webView request] URL];
}

- (void)webViewDidFinishLoad:(UIWebView *)__webView
{
#ifdef TRACE
	NSLog(@"[Tab %@] finished loading page/iframe %@", self.tabNumber, [[[__webView request] URL] absoluteString]);
#endif
	[self setProgress:1.0];
	
	[__webView stringByEvaluatingJavaScriptFromString:[[self class] javascriptToInject]];
	
	[self.title setText:[[self webView] stringByEvaluatingJavaScriptFromString:@"document.title"]];
	self.url = [[__webView request] URL];
}

- (void)webView:(UIWebView *)__webView didFailLoadWithError:(NSError *)error
{
	if (error.code != NSURLErrorCancelled) {
		UIAlertView *m = [[UIAlertView alloc] initWithTitle:@"Error" message:[error localizedDescription] delegate:self cancelButtonTitle: @"Ok" otherButtonTitles:nil];
		[m show];
	}
	
	[self webViewDidFinishLoad:__webView];
}

- (BOOL)webView:(UIWebView *)__webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
	if (![[[request URL] scheme] isEqualToString:@"endlessipc"]) {
		return YES;
	}
	
	/* endlessipc://window.open/somerandomid?http... */
	
	NSString *action = [[request URL] host];
	
	NSString *param, *param2;
	if ([[[request URL] pathComponents] count] >= 2)
		param = [[request URL] pathComponents][1];
	if ([[[request URL] pathComponents] count] >= 3)
		param2 = [[request URL] pathComponents][2];
	
	NSString *value = [[[[request URL] query] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	
#ifdef TRACE
	NSLog(@"[Javascript IPC]: [%@] [%@] [%@] [%@]", action, param, param2, value);
#endif
	
	if ([action isEqualToString:@"window.open"]) {
		WebViewTab *newtab = [[appDelegate webViewController] addNewTabForURL:nil];
		newtab.randID = param;
		newtab.openedByTabHash = [NSNumber numberWithLong:self.hash];
		
		[self webView:__webView callbackWith:[NSString stringWithFormat:@"__endless.openedTabs[\"%@\"].opened = true;", param]];
	}
	else if ([action isEqualToString:@"window.close"]) {
		UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Confirm" message:@"Allow this page to close its tab?" preferredStyle:UIAlertControllerStyleAlert];
		
		UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK action") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[[appDelegate webViewController] removeTab:[self tabNumber]];
		}];
		
		UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel action") style:UIAlertActionStyleCancel handler:nil];
		[alertController addAction:cancelAction];
		[alertController addAction:okAction];
		
		[[appDelegate webViewController] presentViewController:alertController animated:YES completion:nil];
	}
	else if ([action isEqualToString:@"console.log"]) {
		NSString *json = [[[[request URL] query] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		NSLog(@"[Tab %@] [console.%@] %@", [self tabNumber], param, json);
	}
	else {
		WebViewTab *wvt = [[self class] openedWebViewTabByRandID:param];
		
		if (wvt == nil) {
			[self webView:__webView callbackWith:[NSString stringWithFormat:@"delete __endless.openedTabs[\"%@\"];", [param stringEscapedForJavasacript]]];
		}
		/* setters, just write into target webview */
		else if ([action isEqualToString:@"window.setName"]) {
			[[wvt webView] stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"window.name = \"%@\";", [value stringEscapedForJavasacript]]];
			[self webView:__webView callbackWith:@""];
		}
		else if ([action isEqualToString:@"window.setLocation"]) {
			[[wvt webView] stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"window.location = \"%@\";", [value stringEscapedForJavasacript]]];
			[self webView:__webView callbackWith:@""];
		}
		else if ([action isEqualToString:@"window.setLocationParam"]) {
			/* TODO: whitelist param since we're sending it raw */
			[[wvt webView] stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"window.location.%@ = \"%@\";", param2, [value stringEscapedForJavasacript]]];
			[self webView:__webView callbackWith:@""];
		}

		/* getters, pull from target webview and write back to caller internal parameters (not setters) */
		else if ([action isEqualToString:@"window.getName"]) {
			NSString *name = [[wvt webView] stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"window.name;"]];
			[self webView:__webView callbackWith:[NSString stringWithFormat:@"__endless.openedTabs[\"%@\"]._name = \"%@\";", [param stringEscapedForJavasacript], [name stringEscapedForJavasacript]]];
		}
		else if ([action isEqualToString:@"window.getLocation"]) {
			NSString *loc = [[wvt webView] stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"JSON.stringify(window.location);"]];
			/* don't encode loc, it's (hopefully a safe) hash */
			[self webView:__webView callbackWith:[NSString stringWithFormat:@"__endless.openedTabs[\"%@\"]._location = new __endless.FakeLocation(%@)", [param stringEscapedForJavasacript], loc]];
		}
	}

	return NO;
}

- (void)webView:(UIWebView *)__webView callbackWith:(NSString *)callback
{
	NSString *finalcb = [NSString stringWithFormat:@"(function() { %@; __endless.ipcDone = (new Date()).getTime(); })();", callback];

#ifdef TRACE_IPC
	NSLog(@"[Javascript IPC]: calling back with: %@", finalcb);
#endif
	
	[__webView stringByEvaluatingJavaScriptFromString:finalcb];
}

- (void)setProgress:(float)pr
{
	progress = pr;
	[[appDelegate webViewController] updateProgress];
}

- (float)progress
{
	return progress;
}

- (void)swipeRightAction:(id)_id
{
	[self goBack];
}

- (void)swipeLeftAction:(id)_id
{
	[self goForward];
}

- (BOOL)canGoBack
{
	return ((self.webView && [self.webView canGoBack]) || self.openedByTabHash != nil);
}

- (BOOL)canGoForward
{
	return !!(self.webView && [self.webView canGoForward]);
}

- (void)goBack
{
	if ([self.webView canGoBack]) {
		[self.webView goBack];
	}
	else if (self.openedByTabHash) {
		for (WebViewTab *wvt in [[appDelegate webViewController] webViewTabs]) {
			if ([wvt hash] == [self.openedByTabHash longValue]) {
				[[appDelegate webViewController] removeTab:self.tabNumber andFocusTab:[wvt tabNumber]];
				return;
			}
		}
		
		[[appDelegate webViewController] removeTab:self.tabNumber];
	}
}

- (void)goForward
{
	if ([self.webView canGoForward])
		[self.webView goForward];
}

- (void)zoomOut
{
	self.webView.userInteractionEnabled = NO;
	[[self.webView layer] setBorderColor:[[UIColor grayColor] CGColor]];
	[[self.webView layer] setBorderWidth:0.5];

	[_titleHolder setHidden:false];
	[_title setHidden:false];
	[_closer setHidden:false];
	[[self viewHolder] setTransform:CGAffineTransformMakeScale(ZOOM_OUT_SCALE, ZOOM_OUT_SCALE)];
}

- (void)zoomNormal
{
	self.webView.userInteractionEnabled = YES;
	[[self.webView layer] setBorderWidth:0];

	[_titleHolder setHidden:true];
	[_title setHidden:true];
	[_closer setHidden:true];
	[[self viewHolder] setTransform:CGAffineTransformMakeScale(1.0, 1.0)];
}

@end

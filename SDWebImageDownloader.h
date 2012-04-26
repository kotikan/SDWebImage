/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageDownloaderDelegate.h"
#import "SDWebImageCompat.h"

typedef enum {
    /**
     Disable the use of authentication
     */
    SDRequestAuthenticationTypeNone = 0,
    /**
     Use NSURLConnection's HTTP AUTH auto-negotiation
     */
    SDRequestAuthenticationTypeHTTP, 
    /**
     Force the use of HTTP Basic authentication.
     
     This will supress AUTH challenges as RestKit will add an Authorization
     header establishing login via HTTP basic.  This is an optimization that
     skips the challenge portion of the request.
     */
    SDRequestAuthenticationTypeHTTPBasic,
    /**
     Enable the use of OAuth 1.0 authentication.
     
     OAuth1ConsumerKey, OAuth1ConsumerSecret, OAuth1AccessToken, and
     OAuth1AccessTokenSecret must be set when using this type.
     */
    SDRequestAuthenticationTypeOAuth1,
    /**
     Enable the use of OAuth 2.0 authentication.
     
     OAuth2AccessToken must be set when using this type.
     */
    SDRequestAuthenticationTypeOAuth2
} SDRequestAuthenticationType;

extern NSString *const SDWebImageDownloadStartNotification;
extern NSString *const SDWebImageDownloadStopNotification;

@interface SDWebImageDownloader : NSObject
{
    @private
    NSURL *url;
    SDWIWeak id<SDWebImageDownloaderDelegate> delegate;
    NSURLConnection *connection;
    NSMutableData *imageData;
    id userInfo;
    BOOL lowPriority;
}

@property (nonatomic, retain) NSURL *url;
@property (nonatomic, retain) NSDictionary *userHeaders;
@property (nonatomic, assign) id<SDWebImageDownloaderDelegate> delegate;
@property (nonatomic, retain) NSMutableData *imageData;
@property (nonatomic, retain) id userInfo;
@property (nonatomic, readwrite) BOOL lowPriority;

+ (id)downloaderWithURL:(NSURL *)url userHeaders:(NSDictionary*)userHeaders delegate:(id<SDWebImageDownloaderDelegate>)delegate userInfo:(id)userInfo lowPriority:(BOOL)lowPriority;
+ (id)downloaderWithURL:(NSURL *)url delegate:(id<SDWebImageDownloaderDelegate>)delegate userInfo:(id)userInfo lowPriority:(BOOL)lowPriority;
+ (id)downloaderWithURL:(NSURL *)url delegate:(id<SDWebImageDownloaderDelegate>)delegate userInfo:(id)userInfo;
+ (id)downloaderWithURL:(NSURL *)url delegate:(id<SDWebImageDownloaderDelegate>)delegate;
- (void)start;
- (void)cancel;

// This method is now no-op and is deprecated
+ (void)setMaxConcurrentDownloads:(NSUInteger)max __attribute__((deprecated));

@end

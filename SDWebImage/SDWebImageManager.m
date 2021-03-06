/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageManager.h"
#import "SDImageCache.h"
#import "SDWebImageDownloader.h"
#import "UIImage+FocusCrop.h"
#import <objc/message.h>

#pragma mark - SDWebImageManagerDomainSettings

@interface SDWebImageManagerDomainSettings : NSObject

@property(nonatomic, assign) SDRequestAuthenticationType authenticationType;
@property(nonatomic, retain) NSString* username;
@property(nonatomic, retain) NSString* password;
@property(nonatomic, retain) NSString* authString;

- (NSDictionary*)headers;

@end

@implementation SDWebImageManagerDomainSettings

@synthesize authenticationType;
@synthesize username;
@synthesize password;
@synthesize authString;

- (void)setAuthenticationType:(SDRequestAuthenticationType)newAuthenticationType
{
    if (authenticationType != newAuthenticationType) {
        authenticationType = newAuthenticationType;
        NSAssert((authenticationType == SDRequestAuthenticationTypeNone || SDRequestAuthenticationTypeHTTPBasic), 
                 @"authenticationType not supported: %d", 
                 authenticationType);
    }
}

- (NSString*)authString {
    NSLog(@"authString getter %@", @"");
    if (authString == nil) {
        NSLog(@"making auth string %@", @"");
        if (self.authenticationType == SDRequestAuthenticationTypeHTTPBasic && username && password) {
            CFHTTPMessageRef dummyRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, 
                                                                       (CFStringRef)@"GET",
#if __has_feature(objc_arc)
                                                                       (__bridge CFURLRef)[NSURL URLWithString:@"www.example.org"],
#else
                                                                       (CFURLRef)[NSURL URLWithString:@"www.example.org"],
#endif
                                                                       kCFHTTPVersion1_1);
            NSLog(@"dummyRequest: %@", dummyRequest);
            if (dummyRequest) {
#if __has_feature(objc_arc)
                CFHTTPMessageAddAuthentication(dummyRequest, nil, (__bridge CFStringRef)username, (__bridge CFStringRef)password, kCFHTTPAuthenticationSchemeBasic, FALSE);
#else
                CFHTTPMessageAddAuthentication(dummyRequest, nil, (CFStringRef)username, (CFStringRef)password, kCFHTTPAuthenticationSchemeBasic, FALSE);
#endif
                CFStringRef authorizationString = CFHTTPMessageCopyHeaderFieldValue(dummyRequest, CFSTR("Authorization"));
                if (authorizationString) {
#if __has_feature(objc_arc)
                    self.authString = (__bridge NSString*) authorizationString;
#else
                    self.authString = (NSString*) authorizationString;
#endif
                    CFRelease(authorizationString);
                }
                CFRelease(dummyRequest);
            }
        }
    }
    return authString;
}

- (NSDictionary*)headers {
    if (authenticationType == SDRequestAuthenticationTypeHTTPBasic) {
        return [NSDictionary dictionaryWithObject:self.authString 
                                           forKey:@"Authorization"];
    }
    return nil;
}

- (void)dealloc {
    SDWISafeRelease(username);
    SDWISafeRelease(password);
    SDWISafeRelease(authString);
    SDWISuperDealoc;
}

@end

#pragma mark - SDWebImageManager

static SDWebImageManager *instance;

@implementation SDWebImageManager

#if NS_BLOCKS_AVAILABLE
@synthesize cacheKeyFilter;
#endif

- (void)setBasicAuthUsername:(NSString*)username password:(NSString*)password forDomain:(NSString*)domain {
    SDWebImageManagerDomainSettings* settings = [[SDWebImageManagerDomainSettings alloc] init];
    settings.authenticationType = SDRequestAuthenticationTypeHTTPBasic;
    settings.username = username;
    settings.password = password;
    [settingsPerDomain setObject:settings forKey:domain];
#if !__has_feature(objc_arc)
    [settings release];
#endif
}

- (id)init
{
    if ((self = [super init]))
    {
        downloadInfo = [[NSMutableArray alloc] init];
        downloadDelegates = [[NSMutableArray alloc] init];
        downloaders = [[NSMutableArray alloc] init];
        cacheDelegates = [[NSMutableArray alloc] init];
        cacheURLs = [[NSMutableArray alloc] init];
        downloaderForURL = [[NSMutableDictionary alloc] init];
        failedURLs = [[NSMutableArray alloc] init];
        settingsPerDomain = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    SDWISafeRelease(downloadInfo);
    SDWISafeRelease(downloadDelegates);
    SDWISafeRelease(downloaders);
    SDWISafeRelease(cacheDelegates);
    SDWISafeRelease(cacheURLs);
    SDWISafeRelease(downloaderForURL);
    SDWISafeRelease(failedURLs);
    SDWISafeRelease(settingsPerDomain);
    SDWISuperDealoc;
}


+ (id)sharedManager
{
    if (instance == nil)
    {
        instance = [[SDWebImageManager alloc] init];
    }
    
    return instance;
}

- (NSString *)cacheKeyForURL:(NSURL *)url
{
#if NS_BLOCKS_AVAILABLE
    if (self.cacheKeyFilter)
    {
        return self.cacheKeyFilter(url);
    }
    else
    {
        return [url absoluteString];
    }
#else
    return [url absoluteString];
#endif
}

/*
 * @deprecated
 */
- (UIImage *)imageWithURL:(NSURL *)url
{
    return [[SDImageCache sharedImageCache] imageFromKey:[self cacheKeyForURL:url]];
}

/*
 * @deprecated
 */
- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate retryFailed:(BOOL)retryFailed
{
    [self downloadWithURL:url delegate:delegate options:(retryFailed ? SDWebImageRetryFailed : 0)];
}

/*
 * @deprecated
 */
- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate retryFailed:(BOOL)retryFailed lowPriority:(BOOL)lowPriority
{
    SDWebImageOptions options = 0;
    if (retryFailed) options |= SDWebImageRetryFailed;
    if (lowPriority) options |= SDWebImageLowPriority;
    [self downloadWithURL:url delegate:delegate options:options];
}

- (NSDictionary*)userHeadersForUrl:(NSURL*)url {
    return [((SDWebImageManagerDomainSettings*)[settingsPerDomain objectForKey:[url host]]) headers];
}

- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate
{
    [self downloadWithURL:url delegate:delegate options:0];
}

- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate options:(SDWebImageOptions)options
{
    [self downloadWithURL:url delegate:delegate options:options userInfo:nil];
}

- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate newSize:(CGSize)newSize focusPercentPoint:(CGPoint)focusPoint
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithFloat:newSize.width],@"newWidth",
                              [NSNumber numberWithFloat:newSize.height],@"newHeight",
                              [NSNumber numberWithFloat:focusPoint.x],@"focusX",
                              [NSNumber numberWithFloat:focusPoint.y],@"focusY",
                              nil];
    [self downloadWithURL:url delegate:delegate options:0 userInfo:userInfo];
}

- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate options:(SDWebImageOptions)options userInfo:(NSDictionary *)userInfo
{
    // Very common mistake is to send the URL using NSString object instead of NSURL. For some strange reason, XCode won't
    // throw any warning for this type mismatch. Here we failsafe this error by allowing URLs to be passed as NSString.
    if ([url isKindOfClass:NSString.class])
    {
        url = [NSURL URLWithString:(NSString *)url];
    }
    else if (![url isKindOfClass:NSURL.class])
    {
        url = nil; // Prevent some common crashes due to common wrong values passed like NSNull.null for instance
    }
    
    if (!url || !delegate || (!(options & SDWebImageRetryFailed) && [failedURLs containsObject:url]))
    {
        return;
    }
    
    // Check the on-disk cache async so we don't block the main thread
    [cacheDelegates addObject:delegate];
    [cacheURLs addObject:url];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                          delegate, @"delegate",
                          url, @"url",
                          [NSNumber numberWithInt:options], @"options",
                          userInfo ? userInfo : [NSNull null], @"userInfo",
                          nil];
    [[SDImageCache sharedImageCache] queryDiskCacheForKey:[self cacheKeyForURL:url] delegate:self userInfo:info];
}

#if NS_BLOCKS_AVAILABLE
- (void)downloadWithURL:(NSURL *)url delegate:(id)delegate options:(SDWebImageOptions)options success:(SDWebImageSuccessBlock)success failure:(SDWebImageFailureBlock)failure
{
    [self downloadWithURL:url delegate:delegate options:options userInfo:nil success:success failure:failure];
}

- (void)downloadWithURL:(NSURL *)url delegate:(id)delegate options:(SDWebImageOptions)options newSize:(CGSize)newSize focusPercentPoint:(CGPoint)focusPoint success:(SDWebImageSuccessBlock)success failure:(SDWebImageFailureBlock)failure
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithFloat:newSize.width],@"newWidth",
                              [NSNumber numberWithFloat:newSize.height],@"newHeight",
                              [NSNumber numberWithFloat:focusPoint.x],@"focusX",
                              [NSNumber numberWithFloat:focusPoint.y],@"focusY",
                              nil];
    [self downloadWithURL:url delegate:delegate options:options userInfo:userInfo success:success failure:failure];
}

- (void)downloadWithURL:(NSURL *)url delegate:(id)delegate options:(SDWebImageOptions)options userInfo:(NSDictionary *)userInfo success:(SDWebImageSuccessBlock)success failure:(SDWebImageFailureBlock)failure
{
    // repeated logic from above due to requirement for backwards compatability for iOS versions without blocks
    
    // Very common mistake is to send the URL using NSString object instead of NSURL. For some strange reason, XCode won't
    // throw any warning for this type mismatch. Here we failsafe this error by allowing URLs to be passed as NSString.
    if ([url isKindOfClass:NSString.class])
    {
        url = [NSURL URLWithString:(NSString *)url];
    }
    
    if (!url || !delegate || (!(options & SDWebImageRetryFailed) && [failedURLs containsObject:url]))
    {
        return;
    }
    
    // Check the on-disk cache async so we don't block the main thread
    [cacheDelegates addObject:delegate];
    [cacheURLs addObject:url];
    SDWebImageSuccessBlock successCopy = [success copy];
    SDWebImageFailureBlock failureCopy = [failure copy];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                          delegate, @"delegate",
                          url, @"url",
                          [NSNumber numberWithInt:options], @"options",
                          userInfo ? userInfo : [NSNull null], @"userInfo",
                          successCopy, @"success",
                          failureCopy, @"failure",
                          nil];
    SDWIRelease(successCopy);
    SDWIRelease(failureCopy);
    [[SDImageCache sharedImageCache] queryDiskCacheForKey:[self cacheKeyForURL:url] delegate:self userInfo:info];
}
#endif

- (void)removeObjectsForDelegate:(id<SDWebImageManagerDelegate>)delegate
{
    // Delegates notified, remove downloader and delegate
    // The delegate callbacks above may have modified the arrays, hence we search for the correct index
    int idx = [downloadDelegates indexOfObjectIdenticalTo:delegate];
    if (idx != NSNotFound)
    {
        [downloaders removeObjectAtIndex:idx];
        [downloadInfo removeObjectAtIndex:idx];
        [downloadDelegates removeObjectAtIndex:idx];
    }
}

- (void)cancelForDelegate:(id<SDWebImageManagerDelegate>)delegate
{
    NSUInteger idx;
    while ((idx = [cacheDelegates indexOfObjectIdenticalTo:delegate]) != NSNotFound)
    {
        [cacheDelegates removeObjectAtIndex:idx];
        [cacheURLs removeObjectAtIndex:idx];
    }
    
    while ((idx = [downloadDelegates indexOfObjectIdenticalTo:delegate]) != NSNotFound)
    {
        SDWebImageDownloader *downloader = SDWIReturnRetained([downloaders objectAtIndex:idx]);
        
        [downloadInfo removeObjectAtIndex:idx];
        [downloadDelegates removeObjectAtIndex:idx];
        [downloaders removeObjectAtIndex:idx];
        
        if (![downloaders containsObject:downloader])
        {
            // No more delegate are waiting for this download, cancel it
            [downloader cancel];
            [downloaderForURL removeObjectForKey:downloader.url];
        }
        
        SDWIRelease(downloader);
    }
}

- (void)cancelAll
{
    for (SDWebImageDownloader *downloader in downloaders)
    {
        [downloader cancel];
    }
    [cacheDelegates removeAllObjects];
    [cacheURLs removeAllObjects];
    
    [downloadInfo removeAllObjects];
    [downloadDelegates removeAllObjects];
    [downloaders removeAllObjects];
    [downloaderForURL removeAllObjects];
}

#pragma mark SDImageCacheDelegate

- (NSUInteger)indexOfDelegate:(id<SDWebImageManagerDelegate>)delegate waitingForURL:(NSURL *)url
{
    // Do a linear search, simple (even if inefficient)
    NSUInteger idx;
    for (idx = 0; idx < [cacheDelegates count]; idx++)
    {
        if ([cacheDelegates objectAtIndex:idx] == delegate && [[cacheURLs objectAtIndex:idx] isEqual:url])
        {
            return idx;
        }
    }
    return NSNotFound;
}

- (UIImage *)resize:(UIImage *)image withFocusFromUserInfo:(NSDictionary *)userInfo
{
    UIImage *newImage=image;
    if (userInfo != nil && [userInfo isKindOfClass:[NSDictionary class]] && [userInfo objectForKey:@"focusX"] != nil) {
        CGSize newSize;
        newSize.width = [[userInfo objectForKey:@"newWidth"] floatValue];
        newSize.height = [[userInfo objectForKey:@"newHeight"] floatValue];
        CGPoint focusPoint;
        focusPoint.x = [[userInfo objectForKey:@"focusX"] floatValue];
        focusPoint.y = [[userInfo objectForKey:@"focusY"] floatValue];
        newImage = [image resizeToSize:newSize withFocusPercentPoint:focusPoint];
    }
    return newImage;
}

- (void)imageCache:(SDImageCache *)imageCache didFindImage:(UIImage *)image forKey:(NSString *)key userInfo:(NSDictionary *)info
{
    NSURL *url = [info objectForKey:@"url"];
    id<SDWebImageManagerDelegate> delegate = [info objectForKey:@"delegate"];
    
    UIImage *newImage = image;
    NSDictionary *userInfo = [info objectForKey:@"userInfo"];
    newImage = [self resize:image withFocusFromUserInfo:userInfo];
    
    NSUInteger idx = [self indexOfDelegate:delegate waitingForURL:url];
    if (idx == NSNotFound)
    {
        // Request has since been canceled
        return;
    }
    
    if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:)])
    {
        [delegate performSelector:@selector(webImageManager:didFinishWithImage:) withObject:self withObject:newImage];
    }
    if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:forURL:)])
    {
        objc_msgSend(delegate, @selector(webImageManager:didFinishWithImage:forURL:), self, newImage, url);
    }
    if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:forURL:userInfo:)])
    {
        if ([userInfo isKindOfClass:NSNull.class])
        {
            userInfo = nil;
        }
        objc_msgSend(delegate, @selector(webImageManager:didFinishWithImage:forURL:userInfo:), self, newImage, url, userInfo);
    }
#if NS_BLOCKS_AVAILABLE
    if ([info objectForKey:@"success"])
    {
        SDWebImageSuccessBlock success = [info objectForKey:@"success"];
        success(image, YES);
    }
#endif
    
    // Delegates notified, remove url and delegate
    // The delegate callbacks above may have modified the arrays, hence we search for the correct index
    int removeIdx = [self indexOfDelegate:delegate waitingForURL:url];
    if (removeIdx != NSNotFound)
    {
        [cacheDelegates removeObjectAtIndex:removeIdx];
        [cacheURLs removeObjectAtIndex:removeIdx];
    }
}

- (void)imageCache:(SDImageCache *)imageCache didNotFindImageForKey:(NSString *)key userInfo:(NSDictionary *)info
{
    NSURL *url = [info objectForKey:@"url"];
    id<SDWebImageManagerDelegate> delegate = [info objectForKey:@"delegate"];
    SDWebImageOptions options = [[info objectForKey:@"options"] intValue];
    
    NSUInteger idx = [self indexOfDelegate:delegate waitingForURL:url];
    if (idx == NSNotFound)
    {
        // Request has since been canceled
        return;
    }
    
    [cacheDelegates removeObjectAtIndex:idx];
    [cacheURLs removeObjectAtIndex:idx];
    
    // Share the same downloader for identical URLs so we don't download the same URL several times
    SDWebImageDownloader *downloader = [downloaderForURL objectForKey:url];
    
    if (!downloader)
    {
        downloader = [SDWebImageDownloader downloaderWithURL:url 
                                                 userHeaders:[self userHeadersForUrl:url]
                                                    delegate:self 
                                                    userInfo:info 
                                                 lowPriority:(options & SDWebImageLowPriority)];
        [downloaderForURL setObject:downloader forKey:url];
    }
    else
    {
        // Reuse shared downloader
        downloader.lowPriority = (options & SDWebImageLowPriority);
    }
    
    if ((options & SDWebImageProgressiveDownload) && !downloader.progressive)
    {
        // Turn progressive download support on demand
        downloader.progressive = YES;
    }
    
    [downloadInfo addObject:info];
    [downloadDelegates addObject:delegate];
    [downloaders addObject:downloader];
}

#pragma mark SDWebImageDownloaderDelegate

- (void)imageDownloader:(SDWebImageDownloader *)downloader didUpdatePartialImage:(UIImage *)image
{
    NSMutableArray *notifiedDelegates = [NSMutableArray arrayWithCapacity:downloaders.count];
    
    BOOL found = YES;
    while (found)
    {
        found = NO;
        assert(downloaders.count == downloadDelegates.count);
        assert(downloaders.count == downloadInfo.count);
        NSInteger count = downloaders.count;
        for (NSInteger i=count-1; i>=0; --i)
        {
            SDWebImageDownloader *aDownloader = [downloaders objectAtIndex:i];
            if (aDownloader != downloader)
            {
                continue;
            }
            
            id<SDWebImageManagerDelegate> delegate = [downloadDelegates objectAtIndex:i];
            SDWIRetain(delegate);
            SDWIAutorelease(delegate);
            
            if ([notifiedDelegates containsObject:delegate])
            {
                continue;
            }
            // Keep track of delegates notified
            [notifiedDelegates addObject:delegate];
            
            NSDictionary *info = [downloadInfo objectAtIndex:i];
            SDWIRetain(info);
            SDWIAutorelease(info);
            
            if ([delegate respondsToSelector:@selector(webImageManager:didProgressWithPartialImage:forURL:)])
            {
                objc_msgSend(delegate, @selector(webImageManager:didProgressWithPartialImage:forURL:), self, image, downloader.url);
            }
            if ([delegate respondsToSelector:@selector(webImageManager:didProgressWithPartialImage:forURL:userInfo:)])
            {
                NSDictionary *userInfo = [info objectForKey:@"userInfo"];
                if ([userInfo isKindOfClass:NSNull.class])
                {
                    userInfo = nil;
                }
                objc_msgSend(delegate, @selector(webImageManager:didProgressWithPartialImage:forURL:userInfo:), self, image, downloader.url, userInfo);
            }
            // Delegate notified. Break out and restart loop
            found = YES;
            break;
        }
    }
}

- (void)imageDownloader:(SDWebImageDownloader *)downloader didFinishWithImage:(UIImage *)image
{
    SDWIRetain(downloader);
    SDWebImageOptions options = [[downloader.userInfo objectForKey:@"options"] intValue];
    
    BOOL found = YES;
    while (found)
    {
        found = NO;
        assert(downloaders.count == downloadDelegates.count);
        assert(downloaders.count == downloadInfo.count);
        NSInteger count = downloaders.count;
        for (NSInteger i=count-1; i>=0; --i)
        {
            SDWebImageDownloader *aDownloader = [downloaders objectAtIndex:i];
            if (aDownloader != downloader)
            {
                continue;
            }
            id<SDWebImageManagerDelegate> delegate = [downloadDelegates objectAtIndex:i];
            SDWIRetain(delegate);
            SDWIAutorelease(delegate);
            NSDictionary *info = [downloadInfo objectAtIndex:i];
            SDWIRetain(info);
            SDWIAutorelease(info);
            
            UIImage *newImage = image;
            NSDictionary *userInfo = [info objectForKey:@"userInfo"];
            newImage = [self resize:image withFocusFromUserInfo:userInfo];
            
            if (newImage)
            {
                if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:)])
                {
                    [delegate performSelector:@selector(webImageManager:didFinishWithImage:) withObject:self withObject:newImage];
                }
                if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:forURL:)])
                {
                    objc_msgSend(delegate, @selector(webImageManager:didFinishWithImage:forURL:), self, newImage, downloader.url);
                }
                if ([delegate respondsToSelector:@selector(webImageManager:didFinishWithImage:forURL:userInfo:)])
                {
                    if ([userInfo isKindOfClass:NSNull.class])
                    {
                        userInfo = nil;
                    }
                    objc_msgSend(delegate, @selector(webImageManager:didFinishWithImage:forURL:userInfo:), self, newImage, downloader.url, userInfo);
                }
#if NS_BLOCKS_AVAILABLE
                if ([info objectForKey:@"success"])
                {
                    SDWebImageSuccessBlock success = [info objectForKey:@"success"];
                    success(image, NO);
                }
#endif
            }
            else
            {
                if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:)])
                {
                    [delegate performSelector:@selector(webImageManager:didFailWithError:) withObject:self withObject:nil];
                }
                if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:forURL:)])
                {
                    objc_msgSend(delegate, @selector(webImageManager:didFailWithError:forURL:), self, nil, downloader.url);
                }
                if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:forURL:userInfo:)])
                {
                    if ([userInfo isKindOfClass:NSNull.class])
                    {
                        userInfo = nil;
                    }
                    objc_msgSend(delegate, @selector(webImageManager:didFailWithError:forURL:userInfo:), self, nil, downloader.url, userInfo);
                }
#if NS_BLOCKS_AVAILABLE
                if ([info objectForKey:@"failure"])
                {
                    SDWebImageFailureBlock failure = [info objectForKey:@"failure"];
                    failure(nil);
                }
#endif
            }
            // Downloader found. Break out and restart for loop
            [self removeObjectsForDelegate:delegate];
            found = YES;
            break;
        }
    }
    
    if (image)
    {
        // Store the image in the cache
        [[SDImageCache sharedImageCache] storeImage:image
                                          imageData:downloader.imageData
                                             forKey:[self cacheKeyForURL:downloader.url]
                                             toDisk:!(options & SDWebImageCacheMemoryOnly)];
    }
    else if (!(options & SDWebImageRetryFailed))
    {
        // The image can't be downloaded from this URL, mark the URL as failed so we won't try and fail again and again
        // (do this only if SDWebImageRetryFailed isn't activated)
        [failedURLs addObject:downloader.url];
    }
    
    
    // Release the downloader
    [downloaderForURL removeObjectForKey:downloader.url];
    SDWIRelease(downloader);
}

- (void)imageDownloader:(SDWebImageDownloader *)downloader didFailWithError:(NSError *)error;
{
    SDWIRetain(downloader);
    
    // Notify all the downloadDelegates with this downloader
    BOOL found = YES;
    while (found)
    {
        found = NO;
        assert(downloaders.count == downloadDelegates.count);
        assert(downloaders.count == downloadInfo.count);
        NSInteger count = downloaders.count;
        for (NSInteger i=count-1 ; i>=0; --i)
        {
            SDWebImageDownloader *aDownloader = [downloaders objectAtIndex:i];
            if (aDownloader != downloader)
            {
                continue;
            }
            id<SDWebImageManagerDelegate> delegate = [downloadDelegates objectAtIndex:i];
            SDWIRetain(delegate);
            SDWIAutorelease(delegate);
            NSDictionary *info = [downloadInfo objectAtIndex:i];
            SDWIRetain(info);
            SDWIAutorelease(info);
            
            if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:)])
            {
                [delegate performSelector:@selector(webImageManager:didFailWithError:) withObject:self withObject:error];
            }
            if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:forURL:)])
            {
                objc_msgSend(delegate, @selector(webImageManager:didFailWithError:forURL:), self, error, downloader.url);
            }
            if ([delegate respondsToSelector:@selector(webImageManager:didFailWithError:forURL:userInfo:)])
            {
                NSDictionary *userInfo = [info objectForKey:@"userInfo"];
                if ([userInfo isKindOfClass:NSNull.class])
                {
                    userInfo = nil;
                }
                objc_msgSend(delegate, @selector(webImageManager:didFailWithError:forURL:userInfo:), self, error, downloader.url, userInfo);
            }
#if NS_BLOCKS_AVAILABLE
            if ([info objectForKey:@"failure"])
            {
                SDWebImageFailureBlock failure = [info objectForKey:@"failure"];
                failure(error);
            }
#endif
            // Downloader found. Break out and restart for loop
            [self removeObjectsForDelegate:delegate];
            found = YES;
            break;
        }
    }
    
    // Release the downloader
    [downloaderForURL removeObjectForKey:downloader.url];
    SDWIRelease(downloader);
}

@end

//
//  UIImage+FocusCrop.m
//  SDWebImage
//
//  Created by Adam Boardman on 15/07/2013.
//
//  For the full copyright and license information, please view the LICENSE
//  file that was distributed with this source code.
//

#import "UIImage+FocusCrop.h"

@implementation UIImage (FocusCrop)

- (UIImage *) resizeToSize:(CGSize)newSize withFocusPercentPoint:(CGPoint)focusPoint {
    CGContextRef                context;
    CGImageRef                  imageRef;
    CGSize                      inputSize;
    CGSize                      aspectSize;
    UIImage                     *outputImage = nil;
    CGFloat                     scaleFactor, width;
    
    // resize, maintaining aspect ratio:
    
    inputSize = self.size;
    aspectSize = newSize;
    scaleFactor = aspectSize.height / inputSize.height;
    width = roundf(inputSize.width * scaleFactor);
    
    if (width < aspectSize.width) {
        scaleFactor = aspectSize.width / inputSize.width;
        aspectSize.height = roundf(inputSize.height * scaleFactor);
    } else {
        aspectSize.width = width;
    }
    
    UIGraphicsBeginImageContext( aspectSize );
    
    context = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(context, 0, aspectSize.height);
    CGContextScaleCTM(context, 1.0, -1.0);
    CGContextDrawImage(context, CGRectMake( 0, 0, aspectSize.width, aspectSize.height), self.CGImage);
    outputImage = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    // crop rect from focus percentage point
    CGFloat xOffset = roundf((aspectSize.width * (focusPoint.x/100)) - (newSize.width/2));
    if (xOffset < 0) xOffset = 0;
    if (xOffset > aspectSize.width - newSize.width) xOffset = aspectSize.width - newSize.width;
    CGFloat yOffset = roundf((aspectSize.height * (focusPoint.y/100)) - (newSize.height/2));
    if (yOffset < 0) yOffset = 0;
    if (yOffset > aspectSize.height - newSize.height) yOffset = aspectSize.height - newSize.height;
    CGRect cropRect = CGRectMake(xOffset, yOffset, newSize.width, newSize.height);
    
    // crop
    if ( ( imageRef = CGImageCreateWithImageInRect( outputImage.CGImage, cropRect ) ) ) {
        outputImage = [[UIImage alloc] initWithCGImage: imageRef];
        CGImageRelease( imageRef );
    }

    return outputImage;
}

@end

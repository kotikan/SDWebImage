//
//  UIImage+FocusCrop.h
//  SDWebImage
//
//  Created by Adam Boardman on 15/07/2013.
//
//  For the full copyright and license information, please view the LICENSE
//  file that was distributed with this source code.
//

#import <UIKit/UIKit.h>

@interface UIImage (FocusCrop)

- (UIImage *) resizeToSize:(CGSize)newSize withFocusPercentPoint:(CGPoint)focusPoint;

@end

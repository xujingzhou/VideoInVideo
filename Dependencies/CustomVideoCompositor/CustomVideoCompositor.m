//
//  CustomVideoCompositor
//  PictureInPicture
//
//  Created by Johnny Xu(徐景周) on 5/30/15.
//  Copyright (c) 2015 Future Studio. All rights reserved.
//

@import  UIKit;
#import "CustomVideoCompositor.h"

@interface CustomVideoCompositor()

@end

@implementation CustomVideoCompositor

- (instancetype)init
{
    return self;
}

#pragma mark - startVideoCompositionRequest
- (void)startVideoCompositionRequest:(AVAsynchronousVideoCompositionRequest *)request
{
    NSMutableArray *videoArray = [[NSMutableArray alloc] init];
    CVPixelBufferRef destination = [request.renderContext newPixelBuffer];
    if (request.sourceTrackIDs.count > 0)
    {
        for (NSUInteger i = 0; i < [request.sourceTrackIDs count]; ++i)
        {
            CVPixelBufferRef videoBufferRef = [request sourceFrameByTrackID:[[request.sourceTrackIDs objectAtIndex:i] intValue]];
            if (videoBufferRef)
            {
                [videoArray addObject:(__bridge id)(videoBufferRef)];
            }
        }
        
        for (NSUInteger i = 0; i < [videoArray count]; ++i)
        {
            CVPixelBufferRef video = (__bridge CVPixelBufferRef)([videoArray objectAtIndex:i]);
            CVPixelBufferLockBaseAddress(video, kCVPixelBufferLock_ReadOnly);
        }
        CVPixelBufferLockBaseAddress(destination, 0);
        
        [self renderBuffer:videoArray toBuffer:destination];
        
        CVPixelBufferUnlockBaseAddress(destination, 0);
        for (NSUInteger i = 0; i < [videoArray count]; ++i)
        {
            CVPixelBufferRef video = (__bridge CVPixelBufferRef)([videoArray objectAtIndex:i]);
            CVPixelBufferUnlockBaseAddress(video, kCVPixelBufferLock_ReadOnly);
        }
    }
    
    [request finishWithComposedVideoFrame:destination];
    CVBufferRelease(destination);
}

- (void)renderContextChanged:(AVVideoCompositionRenderContext *)newRenderContext
{
}

- (NSDictionary *)requiredPixelBufferAttributesForRenderContext
{
    return @{ (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey : @[ @(kCVPixelFormatType_32BGRA) ] };
}

- (NSDictionary *)sourcePixelBufferAttributes
{
    return @{ (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey : @[ @(kCVPixelFormatType_32BGRA) ] };
}

#pragma mark - renderBuffer
- (void)renderBuffer:(NSMutableArray *)videoBufferRefArray toBuffer:(CVPixelBufferRef)destination
{
    size_t width = CVPixelBufferGetWidth(destination);
    size_t height = CVPixelBufferGetHeight(destination);
    NSMutableArray *imageRefArray = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < [videoBufferRefArray count]; ++i)
    {
        CVPixelBufferRef videoFrame = (__bridge CVPixelBufferRef)([videoBufferRefArray objectAtIndex:i]);
        CGImageRef imageRef = [self createSourceImageFromBuffer:videoFrame];
        if (imageRef)
        {
            if ([self shouldRightRotate90ByTrackID:i+1])
            {
                // Right rotation 90
                imageRef = CGImageRotated(imageRef, degreesToRadians(90));
            }
            
            [imageRefArray addObject:(__bridge id)(imageRef)];
        }
        CGImageRelease(imageRef);
    }
    
    if ([imageRefArray count] < 1)
    {
        NSLog(@"imageRefArray is empty.");
        return;
    }
    
    CGContextRef gc = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(destination), width, height, 8, CVPixelBufferGetBytesPerRow(destination), CGImageGetColorSpace((CGImageRef)imageRefArray[0]), CGImageGetBitmapInfo((CGImageRef)imageRefArray[0]));
    
    NSArray *arrayRect = [self getArrayRects];
    if (!arrayRect || [arrayRect count] < 1)
    {
        NSLog(@"arrayRect is empty!");
    }
    
    // Draw
    BOOL isCircleFrame = NO;
    if ([self shouldCircleFrame])
    {
        isCircleFrame = YES;
    }
    
    BOOL shouldDisplayBorder = NO;
    if ([self shouldDisplayInnerBorder])
    {
        shouldDisplayBorder = YES;
    }
    
    CGFloat cornerRadius = 10;
    for (int i = 0; i < [imageRefArray count]; ++i)
    {
        CGRect frame = [arrayRect[i] CGRectValue];
        if (i > 0)
        {
            // Recalc coordinate Y for embeded video because flip draw
            frame.origin.y = height - frame.origin.y - CGRectGetHeight(frame);
            
            if (isCircleFrame)
            {
                cornerRadius = CGRectGetWidth(frame)/2;
            }
        }
        
        [self drawImage:frame withContextRef:gc withImageRef:(CGImageRef)imageRefArray[i] withCornerRadius:cornerRadius];
        if (shouldDisplayBorder)
        {
            [self drawBorderInFrame:frame withContextRef:gc withCornerRadius:cornerRadius];
        }
    }
    
    CGContextRelease(gc);
}

#pragma mark - createSourceImageFromBuffer
- (CGImageRef)createSourceImageFromBuffer:(CVPixelBufferRef)buffer
{
    size_t width = CVPixelBufferGetWidth(buffer);
    size_t height = CVPixelBufferGetHeight(buffer);
    size_t stride = CVPixelBufferGetBytesPerRow(buffer);
    void *data = CVPixelBufferGetBaseAddress(buffer);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, data, height * stride, NULL);
    CGImageRef image = CGImageCreate(width, height, 8, 32, stride, rgb, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast, provider, NULL, NO, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(rgb);
    
    return image;
}

#pragma mark - CGImageRotated
CGImageRef CGImageRotated(CGImageRef originalCGImage, double radians)
{
    CGSize imageSize = CGSizeMake(CGImageGetWidth(originalCGImage), CGImageGetHeight(originalCGImage));
    CGSize rotatedSize;
    if (radians == M_PI_2 || radians == -M_PI_2)
    {
        rotatedSize = CGSizeMake(imageSize.height, imageSize.width);
    }
    else
    {
        rotatedSize = imageSize;
    }
    
    double rotatedCenterX = rotatedSize.width / 2.f;
    double rotatedCenterY = rotatedSize.height / 2.f;
     
    UIGraphicsBeginImageContextWithOptions(rotatedSize, NO, 1.f);
    CGContextRef rotatedContext = UIGraphicsGetCurrentContext();
    if (radians == 0.f || radians == M_PI)
    {
        // 0 or 180 degrees
        CGContextTranslateCTM(rotatedContext, rotatedCenterX, rotatedCenterY);
        if (radians == 0.0f)
        {
            CGContextScaleCTM(rotatedContext, 1.f, -1.f);
        }
        else
        {
            CGContextScaleCTM(rotatedContext, -1.f, 1.f);
        }
        CGContextTranslateCTM(rotatedContext, -rotatedCenterX, -rotatedCenterY);
    }
    else if (radians == M_PI_2 || radians == -M_PI_2)
    {
        // +/- 90 degrees
        CGContextTranslateCTM(rotatedContext, rotatedCenterX, rotatedCenterY);
        CGContextRotateCTM(rotatedContext, radians);
        CGContextScaleCTM(rotatedContext, 1.f, -1.f);
        CGContextTranslateCTM(rotatedContext, -rotatedCenterY, -rotatedCenterX);
    }
    
    CGRect drawingRect = CGRectMake(0.f, 0.f, imageSize.width, imageSize.height);
    CGContextDrawImage(rotatedContext, drawingRect, originalCGImage);
    CGImageRef rotatedCGImage = CGBitmapContextCreateImage(rotatedContext);
    
    UIGraphicsEndImageContext();
    
    return rotatedCGImage;
}

#pragma mark - drawBorderInFrame
- (void)drawBorderInFrame:(CGRect)frame withContextRef:(CGContextRef)contextRef
{
    CGFloat cornerRadius = 0;
    [self drawBorderInFrame:frame withContextRef:contextRef withCornerRadius:cornerRadius];
}

- (void)drawBorderInFrame:(CGRect)frame withContextRef:(CGContextRef)contextRef withCornerRadius:(CGFloat)cornerRadius
{
    if ([self shouldDisplayInnerBorder])
    {
        // Draw
        CGFloat lineWidth = 5;
        CGRect innerVideoRect = frame;
        if (!CGRectIsEmpty(innerVideoRect))
        {
            CGContextBeginPath(contextRef);
            CGContextSetShouldAntialias(contextRef, YES);
            CGPathRef strokeRect = [UIBezierPath bezierPathWithRoundedRect:innerVideoRect cornerRadius:cornerRadius].CGPath;
            CGContextAddPath(contextRef, strokeRect);
            
            CGFloat whiteColor[4] = {1.0, 1.0, 1.0, 1.0};
            CGContextSetStrokeColor(contextRef, whiteColor);
            CGContextSetLineWidth(contextRef, lineWidth);
            CGContextStrokePath(contextRef);
            
            if (!CGContextIsPathEmpty(contextRef))
            {
                CGContextClip(contextRef);
            }
        }
    }
}

#pragma mark - drawImage
- (void)drawImage:(CGRect)frame withContextRef:(CGContextRef)contextRef withImageRef:(CGImageRef)imageRef
{
    CGFloat cornerRadius = 0;
    [self drawImage:frame withContextRef:contextRef withImageRef:imageRef withCornerRadius:cornerRadius];
}

- (void)drawImage:(CGRect)frame withContextRef:(CGContextRef)contextRef withImageRef:(CGImageRef)imageRef withCornerRadius:(CGFloat)cornerRadius
{
    if (!CGRectIsEmpty(frame))
    {
//        CGContextBeginPath(contextRef);
//        CGPathRef strokeRect = [UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:cornerRadius].CGPath;
//        CGContextAddPath(contextRef, strokeRect);
//        CGContextClip(contextRef);
        
        CGContextDrawImage(contextRef, frame, imageRef);
        
//        if (!CGContextIsPathEmpty(contextRef))
//        {
//            CGContextClosePath(contextRef);
//        }
    }
}

#pragma mark - NSUserDefaults
- (NSArray *)getArrayRects
{
    NSString *rectFlag = @"arrayRect";
    NSUserDefaults *userDefaultes = [NSUserDefaults standardUserDefaults];
    NSData *dataRect = [userDefaultes objectForKey:rectFlag];
    NSArray *arrayResult = nil;
    if (dataRect)
    {
        arrayResult = [NSKeyedUnarchiver unarchiveObjectWithData:dataRect];
        if (arrayResult && [arrayResult count] > 0)
        {
//            CGRect innerVideoRect = [arrayResult[0] CGRectValue];
//            if (!CGRectIsEmpty(innerVideoRect))
//            {
//                NSLog(@"[arrayResult[0] CGRectValue: %@", NSStringFromCGRect(innerVideoRect));
//            }
        }
        else
        {
            NSLog(@"getArrayRects is empty!");
        }
    }
    
    return arrayResult;
}

#pragma mark - shouldDisplayInnerBorder
- (BOOL)shouldDisplayInnerBorder
{
    NSString *shouldDisplayInnerBorder = @"ShouldDisplayInnerBorder";
//    NSLog(@"shouldDisplayInnerBorder: %@", [[[NSUserDefaults standardUserDefaults] objectForKey:shouldDisplayInnerBorder] boolValue]?@"Yes":@"No");
    
    if ([[[NSUserDefaults standardUserDefaults] objectForKey:shouldDisplayInnerBorder] boolValue])
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

#pragma mark - shouldRightRotate90ByTrackID
- (BOOL)shouldRightRotate90ByTrackID:(NSInteger)trackID
{
    NSUserDefaults *userDefaultes = [NSUserDefaults standardUserDefaults];
    NSString *identifier = [NSString stringWithFormat:@"TrackID_%ld", (long)trackID];
    BOOL result = [[userDefaultes objectForKey:identifier] boolValue];
    NSLog(@"shouldRightRotate90ByTrackID %@ : %@", identifier, result?@"Yes":@"No");
    
    if (result)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

#pragma mark - shouldCircleFrame
- (BOOL)shouldCircleFrame
{
    NSString *shouldCircleFrame = @"ShouldCircleFrame";
    if ([[[NSUserDefaults standardUserDefaults] objectForKey:shouldCircleFrame] boolValue])
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

@end

//
//  ViewController.m
//  PictureInPicture
//
//  Created by Johnny Xu(徐景周) on 5/30/15.
//  Copyright (c) 2015 Future Studio. All rights reserved.
//

#import "ViewController.h"
#import <StoreKit/StoreKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "ExportEffects.h"
#import "PBJVideoPlayerController.h"
#import "CaptureViewController.h"
#import "JGActionSheet.h"
#import "DBPrivateHelperController.h"
#import "CMPopTipView.h"
#import "ScrollSelectView.h"
#import "StickerView.h"
#import "VideoView.h"
#import "KGModal.h"
#import "UIAlertView+Blocks.h"
#import "IASKAppSettingsViewController.h"

typedef NS_ENUM(NSInteger, SelectedMediaType)
{
    kNone = -1,
    kBackgroundVideo = 0,
    kEmbededGif,
    kEmbededVideo,
};

#define MaxVideoLength MAX_VIDEO_DUR
#define DemoDestinationVideoName @"IMG_Dst.mp4"

@interface ViewController ()<UIImagePickerControllerDelegate, UINavigationControllerDelegate, PBJVideoPlayerControllerDelegate, SKStoreProductViewControllerDelegate, IASKSettingsDelegate, UIPopoverControllerDelegate>
{
    CMPopTipView *_popTipView;
}

@property (nonatomic, strong) PBJVideoPlayerController *demoVideoPlayerController;
@property (nonatomic, strong) UIView *demoVideoContentView;
@property (nonatomic, strong) UIImageView *demoPlayButton;

@property (nonatomic, strong) UIScrollView *videoContentView;
@property (nonatomic, strong) PBJVideoPlayerController *videoPlayerController1;
@property (nonatomic, strong) UIImageView *playButton1;
@property (nonatomic, strong) UIButton *closeVideoPlayerButton1;

@property (nonatomic, copy) NSURL *videoBackgroundPickURL;
@property (nonatomic, copy) NSURL *videoEmbededPickURL;

@property (nonatomic, assign) SelectedMediaType mediaType;

@property (nonatomic, strong) NSMutableArray *videoArray;

@property (nonatomic, retain) IASKAppSettingsViewController *appSettingsViewController;
@property (nonatomic) UIPopoverController* currentPopoverController;

@end

@implementation ViewController

#pragma mark - FindRightNavBarItemView
// Get view for navigarion right item
- (UIView*)findRightNavBarItemView:(UINavigationBar*)navbar
{
    UIView* rightView = nil;
    for (UIView* view in navbar.subviews)
    {
        if (!rightView)
        {
            rightView = view;
        }
        else if (view.frame.origin.x > rightView.frame.origin.x)
        {
            rightView = view;
        }
    }
    
    return rightView;
}

#pragma mark - Image scale
- (UIImage *)scaleFromImage:(UIImage *)image toSize:(CGSize)size
{
    UIGraphicsBeginImageContext(size);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return newImage;
}

#pragma mark - Splice Image(Up/Down)
- (UIImage *)imageSpliceFromUP:(UIImage *)imageUP fromDownImage:(UIImage *)imageDown
{
    CGFloat width = imageUP.size.width, height = imageUP.size.height;
    
    if (width < height)
    {
        CGSize size = CGSizeMake(width*2, height*2);
        UIGraphicsBeginImageContext(size);
        
        [imageUP drawInRect:CGRectMake(width/2, 0, width, height)];
        [imageDown drawInRect:CGRectMake(width/2, height, width, height)];
    }
    else if (width == height)
    {
        CGSize size = CGSizeMake(width/2, height);
        UIGraphicsBeginImageContext(size);
        
        [imageUP drawInRect:CGRectMake(0, 0, width/2, height/2)];
        [imageDown drawInRect:CGRectMake(0, height/2, width/2, height/2)];
    }
    else
    {
        CGSize size = CGSizeMake(width, height*2);
        UIGraphicsBeginImageContext(size);
        
        [imageUP drawInRect:CGRectMake(0, 0, width, height)];
        [imageDown drawInRect:CGRectMake(0, height, width, height)];
    }
    
    UIImage *resultingImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return resultingImage;
}

#pragma mark - ImageFromCIImage
- (UIImage *)makeUIImageFromCIImage:(CIImage*)ciImage
{
    UIImage * returnImage = nil;
    CGImageRef processedCGImage = [[CIContext contextWithOptions:nil] createCGImage:ciImage
                                                                           fromRect:[ciImage extent]];
    returnImage = [UIImage imageWithCGImage:processedCGImage];
    CGImageRelease(processedCGImage);
    
    return returnImage;
}

#pragma mark - Authorization Helper
- (void)popupAlertView
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:nil message:GBLocalizedString(@"Private_Setting_Audio_Tips") delegate:nil cancelButtonTitle:GBLocalizedString(@"IKnow") otherButtonTitles:nil, nil];
    [alertView show];
}

- (void)popupAuthorizationHelper:(id)type
{
    DBPrivateHelperController *privateHelper = [DBPrivateHelperController helperForType:[type longValue]];
    privateHelper.snapshot = [self snapshot];
    privateHelper.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:privateHelper animated:YES completion:nil];
}

- (UIImage *)snapshot
{
    id <UIApplicationDelegate> appDelegate = [[UIApplication sharedApplication] delegate];
    UIGraphicsBeginImageContextWithOptions(appDelegate.window.bounds.size, NO, appDelegate.window.screen.scale);
    [appDelegate.window drawViewHierarchyInRect:appDelegate.window.bounds afterScreenUpdates:NO];
    UIImage *snapshotImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return snapshotImage;
}

#pragma mark - File Helper
- (AVURLAsset *)getURLAsset:(NSString *)filePath
{
    NSURL *videoURL = getFileURL(filePath);
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
    
    return asset;
}

#pragma mark - Delete Temp Files
- (void)deleteTempDirectory
{
    NSString *dir = NSTemporaryDirectory();
    deleteFilesAt(dir, @"mov");
}

#pragma mark - Progress Callback
- (void)retrievingProgress:(id)progress title:(NSString *)text
{
    if (progress && [progress isKindOfClass:[NSNumber class]])
    {
        NSString *title = text ?text :GBLocalizedString(@"SavingVideo");
        NSString *currentPrecentage = [NSString stringWithFormat:@"%d%%", (int)([progress floatValue] * 100)];
        ProgressBarUpdateLoading(title, currentPrecentage);
    }
}

#pragma mark - Custom ActionSheet
- (void)showCustomActionSheet:(UIBarButtonItem *)barButtonItem withEvent:(UIEvent *)event
{
    UIView *anchor = [event.allTouches.anyObject view];
    
    NSString *videoTitle = [NSString stringWithFormat:@"%@%@", GBLocalizedString(@"Step1"), GBLocalizedString(@"SelectVideo")];
    JGActionSheetSection *sectionVideo = [JGActionSheetSection sectionWithTitle:videoTitle
                                                                        message:nil
                                                                   buttonTitles:@[
                                                                                  GBLocalizedString(@"Camera"),
                                                                                  GBLocalizedString(@"PhotoAlbum")
                                                                                  ]
                                                                    buttonStyle:JGActionSheetButtonStyleDefault];
    [sectionVideo setButtonStyle:JGActionSheetButtonStyleBlue forButtonAtIndex:0];
    [sectionVideo setButtonStyle:JGActionSheetButtonStyleBlue forButtonAtIndex:1];
    
    NSString *embedGifOrVideoTitle = [NSString stringWithFormat:@"%@%@", GBLocalizedString(@"Step2"), GBLocalizedString(@"SelectGifOrVideo")];
    JGActionSheetSection *sectionGifOrVideo = [JGActionSheetSection sectionWithTitle:embedGifOrVideoTitle message:nil buttonTitles:
                                          @[
                                            GBLocalizedString(@"Camera")
                                            ]
                                                                    buttonStyle:JGActionSheetButtonStyleDefault];
    [sectionGifOrVideo setButtonStyle:JGActionSheetButtonStyleBlue forButtonAtIndex:0];
    
    NSString *resultTitle = [NSString stringWithFormat:@"%@%@", GBLocalizedString(@"Step3"), GBLocalizedString(@"Export")];
    JGActionSheetSection *sectionResult = [JGActionSheetSection sectionWithTitle:resultTitle message:nil buttonTitles:
                                           @[
                                             GBLocalizedString(@"StartToCreate")
                                             
                                             ]
                                                                     buttonStyle:JGActionSheetButtonStyleDefault];
    [sectionResult setButtonStyle:JGActionSheetButtonStyleBlue forButtonAtIndex:0];
    
    
    NSArray *sections = (iPad ? @[sectionVideo, sectionGifOrVideo, sectionResult] : @[sectionVideo, sectionGifOrVideo, sectionResult, [JGActionSheetSection sectionWithTitle:nil message:nil buttonTitles:@[GBLocalizedString(@"Cancel")] buttonStyle:JGActionSheetButtonStyleCancel]]);
    JGActionSheet *sheet = [[JGActionSheet alloc] initWithSections:sections];
    
    [sheet setButtonPressedBlock:^(JGActionSheet *sheet, NSIndexPath *indexPath)
     {
         NSLog(@"indexPath: %ld; section: %ld", (long)indexPath.row, (long)indexPath.section);
         
         if (indexPath.section == 0)
         {
             if (indexPath.row == 0)
             {
                 // Check permission for Video & Audio
                 [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted)
                  {
                      if (!granted)
                      {
                          [self performSelectorOnMainThread:@selector(popupAlertView) withObject:nil waitUntilDone:YES];
                          return;
                      }
                      else
                      {
                          [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted)
                           {
                               if (!granted)
                               {
                                   [self performSelectorOnMainThread:@selector(popupAuthorizationHelper:) withObject:[NSNumber numberWithLong:DBPrivacyTypeCamera] waitUntilDone:YES];
                                   return;
                               }
                               else
                               {
                                   // Has permisstion
                                   [self performSelectorOnMainThread:@selector(pickBackgroundVideoFromCamera) withObject:nil waitUntilDone:NO];
                               }
                           }];
                      }
                  }];
             }
             else if (indexPath.row == 1)
             {
                 // Check permisstion for photo album
                 ALAuthorizationStatus authStatus = [ALAssetsLibrary authorizationStatus];
                 if (authStatus == ALAuthorizationStatusRestricted || authStatus == ALAuthorizationStatusDenied)
                 {
                     [self performSelectorOnMainThread:@selector(popupAuthorizationHelper:) withObject:[NSNumber numberWithLong:DBPrivacyTypePhoto] waitUntilDone:YES];
                     return;
                 }
                 else
                 {
                     // Has permisstion to execute
                     [self performSelector:@selector(pickBackgroundVideoFromPhotosAlbum) withObject:nil afterDelay:0.1];
                 }
             }
         }
         else if (indexPath.section == 1)
         {
             if (!_videoBackgroundPickURL)
             {
                 NSString *message = GBLocalizedString(@"VideoIsEmptyHint");
                 showAlertMessage(message, nil);
                 return;
             }
             
             if (indexPath.row == 0)
             {
                 // Video
                 [self performSelector:@selector(pickEmbededVideoFromCamera) withObject:nil afterDelay:0.1];
             }
         }
         else if (indexPath.section == 2)
         {
             if (indexPath.row == 0)
             {
                 [self performSelector:@selector(handleConvert) withObject:nil afterDelay:0.1];
             }
         }
         
         [sheet dismissAnimated:YES];
     }];
    
    if (iPad)
    {
        [sheet setOutsidePressBlock:^(JGActionSheet *sheet)
         {
             [sheet dismissAnimated:YES];
         }];
        
        CGPoint point = (CGPoint){ CGRectGetMidX(anchor.bounds), CGRectGetMaxY(anchor.bounds) };
        point = [self.navigationController.view convertPoint:point fromView:anchor];
        
        [sheet showFromPoint:point inView:self.navigationController.view arrowDirection:JGActionSheetArrowDirectionTop animated:YES];
    }
    else
    {
        [sheet setOutsidePressBlock:^(JGActionSheet *sheet)
         {
             [sheet dismissAnimated:YES];
         }];
        
        [sheet showInView:self.navigationController.view animated:YES];
    }
}

#pragma mark - appSettingsViewController
- (IASKAppSettingsViewController*)appSettingsViewController
{
    if (!_appSettingsViewController)
    {
        _appSettingsViewController = [[IASKAppSettingsViewController alloc] init];
        _appSettingsViewController.delegate = self;
//        [_appSettingsViewController setShowCreditsFooter:NO];
    }
    
    return _appSettingsViewController;
}

- (void)showSettingsModal:(id)sender
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
    {
        [self showSettingsPopover:sender];
    }
    else
    {
        [self.navigationController pushViewController:self.appSettingsViewController animated:YES];
        
//        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:self.appSettingsViewController];
//        self.appSettingsViewController.showDoneButton = YES;
//        [self presentViewController:navController animated:NO completion:nil];
    }
}

- (void)showSettingsPopover:(id)sender
{
    if(self.currentPopoverController)
    {
        [self dismissCurrentPopover];
        return;
    }
    
    self.appSettingsViewController.showDoneButton = NO;
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:self.appSettingsViewController];
    UIPopoverController *popover = [[UIPopoverController alloc] initWithContentViewController:navController];
    popover.delegate = self;
    [popover presentPopoverFromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionUp animated:NO];
    self.currentPopoverController = popover;
}

- (void) dismissCurrentPopover
{
    [self.currentPopoverController dismissPopoverAnimated:YES];
    self.currentPopoverController = nil;
}

#pragma mark - UIPopoverControllerDelegate
- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
    self.currentPopoverController = nil;
}

#pragma mark IASKAppSettingsViewControllerDelegate
- (void)settingsViewControllerDidEnd:(IASKAppSettingsViewController*)sender
{
//    [self dismissViewControllerAnimated:YES completion:nil];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - PBJVideoPlayerControllerDelegate
- (void)videoPlayerReady:(PBJVideoPlayerController *)videoPlayer
{
    //NSLog(@"Max duration of the video: %f", videoPlayer.maxDuration);
}

- (void)videoPlayerPlaybackStateDidChange:(PBJVideoPlayerController *)videoPlayer
{
}

- (void)videoPlayerPlaybackWillStartFromBeginning:(PBJVideoPlayerController *)videoPlayer
{
    if (videoPlayer == _videoPlayerController1)
    {
        _playButton1.alpha = 1.0f;
        _playButton1.hidden = NO;
        
        [UIView animateWithDuration:0.1f animations:^{
            _playButton1.alpha = 0.0f;
            
        } completion:^(BOOL finished)
         {
             _playButton1.hidden = YES;
         }];
    }
    else if (videoPlayer == _demoVideoPlayerController)
    {
        _demoPlayButton.alpha = 1.0f;
        _demoPlayButton.hidden = NO;
        
        [UIView animateWithDuration:0.1f animations:^{
            _demoPlayButton.alpha = 0.0f;
        } completion:^(BOOL finished)
         {
             _demoPlayButton.hidden = YES;
         }];
    }
}

- (void)videoPlayerPlaybackDidEnd:(PBJVideoPlayerController *)videoPlayer
{
    if (videoPlayer == _videoPlayerController1)
    {
        _playButton1.hidden = NO;
        
        [UIView animateWithDuration:0.1f animations:^{
            _playButton1.alpha = 1.0f;
        } completion:^(BOOL finished)
         {
             
         }];
    }
    else if (videoPlayer == _demoVideoPlayerController)
    {
        _demoPlayButton.hidden = NO;
        
        [UIView animateWithDuration:0.1f animations:^{
            _demoPlayButton.alpha = 1.0f;
        } completion:^(BOOL finished)
         {
             
         }];
    }
}

#pragma mark - UIImagePickerControllerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    // 1.
    [self dismissViewControllerAnimated:NO completion:nil];
    
    NSLog(@"info = %@",info);
    
    // 2.
    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    if([mediaType isEqualToString:@"public.movie"])
    {
        NSURL *url = [info objectForKey:UIImagePickerControllerMediaURL];
        
        if (url && ![url isFileURL])
        {
            NSLog(@"Input file from camera is invalid.");
            return;
        }
        
        if (getVideoDuration(url) > MaxVideoLength)
        {
            NSString *ok = GBLocalizedString(@"OK");
            NSString *error = GBLocalizedString(@"Error");
            NSString *fileLenHint = GBLocalizedString(@"FileLenHint");
            NSString *seconds = GBLocalizedString(@"Seconds");
            NSString *hint = [fileLenHint stringByAppendingFormat:@" %.0f ", MaxVideoLength];
            hint = [hint stringByAppendingString:seconds];
            UIAlertView* alert = [[UIAlertView alloc] initWithTitle:error
                                                            message:hint
                                                           delegate:nil
                                                  cancelButtonTitle:ok
                                                  otherButtonTitles: nil];
            [alert show];
            
            return;
        }
        
        if (_mediaType == kBackgroundVideo)
        {
            // Remove last file
            if (self.videoBackgroundPickURL && [self.videoBackgroundPickURL isFileURL])
            {
                if ([[NSFileManager defaultManager] removeItemAtURL:self.videoBackgroundPickURL error:nil])
                {
                    NSLog(@"Success for delete old pick file: %@", self.videoBackgroundPickURL);
                }
                else
                {
                    NSLog(@"Failed for delete old pick file: %@", self.videoBackgroundPickURL);
                }
            }
            
            [self handleCloseVideo];
            
            self.videoBackgroundPickURL = url;
            NSLog(@"Pick background video is success: %@", url);
            
            [self reCalcVideoSize:[url relativePath]];
            
            // Setting
            [self defaultVideoSetting:url];
        }
        else if (_mediaType == kEmbededVideo)
        {
            self.videoEmbededPickURL = url;
            NSLog(@"Pick embeded video is success: %@", url);
            
            [self initEmbededVideoView];
        }
    }
    else
    {
        NSLog(@"Error media type");
        return;
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:NO completion:nil];
}

#pragma mark - pickEmbededVideoFromPhotosAlbum
- (void)pickEmbededVideoFromPhotosAlbum
{
    _mediaType = kEmbededVideo;
    [self pickVideoFromPhotoAlbum];
}

#pragma mark - pickBackgroundVideoFromPhotosAlbum
- (void)pickBackgroundVideoFromPhotosAlbum
{
     _mediaType = kBackgroundVideo;
    [self pickVideoFromPhotoAlbum];
}

- (void)pickVideoFromPhotoAlbum
{
    [self stopPlayVideo];
    
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.allowsEditing = YES;
    picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
    {
        // Only movie
        NSArray* availableMedia = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
        picker.mediaTypes = [NSArray arrayWithObject:availableMedia[1]];
    }
    
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - pickEmbededVideoFromCamera
- (void)pickEmbededVideoFromCamera
{
    _mediaType = kEmbededVideo;
    [self pickVideoFromCamera];
}

#pragma mark - pickBackgroundVideoFromCamera
- (void)pickBackgroundVideoFromCamera
{
    _mediaType = kBackgroundVideo;
    [self pickVideoFromCamera];
}

- (void)pickVideoFromCamera
{
    [self stopPlayVideo];
    
    CaptureViewController *captureVC = [[CaptureViewController alloc] init];
    [captureVC setCallback:^(BOOL success, id result)
     {
         if (success)
         {
             NSURL *fileURL = result;
             if (fileURL && [fileURL isFileURL])
             {
                 if (_mediaType == kBackgroundVideo)
                 {
                     [self handleCloseVideo];
                     
                     self.videoBackgroundPickURL = fileURL;
                     NSLog(@"Pick background video is success: %@", fileURL);
                     
                     [self reCalcVideoSize:[fileURL relativePath]];
                     
                     // Setting
                     [self defaultVideoSetting:fileURL];
                 }
                 else if (_mediaType == kEmbededVideo)
                 {
                     self.videoEmbededPickURL = fileURL;
                     NSLog(@"Pick embeded video is success: %@", fileURL);
                     
                     [self initEmbededVideoView];
                 }
                 
             }
             else
             {
                 NSLog(@"Video Picker is empty.");
             }
         }
         else
         {
             NSLog(@"Video Picker Failed: %@", result);
         }
     }];
    
    [self presentViewController:captureVC animated:YES completion:^{
        NSLog(@"PickVideo present");
    }];
}

#pragma mark - InitEmbededVideoView
- (void)initEmbededVideoView
{
    if (!self.videoEmbededPickURL)
    {
        NSLog(@"self.videoEmbededPickURL is empty!");
        return;
    }
    
    // Only 1 embeds video is supported
//    [self clearEmbededVideo];
    
    VideoView *view = [[VideoView alloc] initWithFilePath:[_videoEmbededPickURL relativePath] withViewController:self];
    CGFloat ratio = MIN( (0.3 * self.videoContentView.width) / view.width, (0.3 * self.videoContentView.height) / view.height);
    [view setScale:ratio];
    CGFloat gap = 30;
    view.center = CGPointMake(self.videoContentView.width/2 + gap, self.videoContentView.height/2 + gap);
    
    [self.videoContentView addSubview:view];
    [VideoView setActiveVideoView:view];
    
    if (!_videoArray)
    {
        _videoArray = [NSMutableArray arrayWithCapacity:1];
    }
    [_videoArray addObject:view];
    
    [view setDeleteFinishBlock:^(BOOL success, id result) {
        if (success)
        {
            if (_videoArray && [_videoArray count] > 0)
            {
                if ([_videoArray containsObject:result])
                {
                    [_videoArray removeObject:result];
                }
            }
        }
    }];
}

#pragma mark - Default Setting
- (void)defaultVideoSetting:(NSURL *)url
{
    [self playDemoVideo:[url absoluteString] withinVideoPlayerController:_videoPlayerController1];
    
    [self showVideoPlayView:TRUE];
}

- (void)playDemoVideo:(NSString*)inputVideoPath withinVideoPlayerController:(PBJVideoPlayerController*)videoPlayerController
{
    dispatch_async(dispatch_get_main_queue(), ^{
        
        videoPlayerController.videoPath = inputVideoPath;
        [videoPlayerController playFromBeginning];
    });
}

- (void)stopPlayVideo
{
    if (_videoPlayerController1.playbackState == PBJVideoPlayerPlaybackStatePlaying)
    {
        [_videoPlayerController1 stop];
    }
}

#pragma mark - Show/Hide
- (void)showVideoPlayView:(BOOL)show
{
    if (show)
    {
        _videoContentView.hidden = NO;
        _closeVideoPlayerButton1.hidden = NO;
    }
    else
    {
        if (_videoPlayerController1.playbackState == PBJVideoPlayerPlaybackStatePlaying)
        {
            [_videoPlayerController1 stop];
        }
        
        _videoContentView.hidden = YES;
        _closeVideoPlayerButton1.hidden = YES;
    }
}

#pragma mark AppStore Open
- (void)showAppInAppStore:(NSString *)appId
{
    Class isAllow = NSClassFromString(@"SKStoreProductViewController");
    if (isAllow)
    {
        // > iOS6.0
        SKStoreProductViewController *sKStoreProductViewController = [[SKStoreProductViewController alloc] init];
        sKStoreProductViewController.delegate = self;
        [self presentViewController:sKStoreProductViewController
                           animated:YES
                         completion:nil];
        [sKStoreProductViewController loadProductWithParameters:@{SKStoreProductParameterITunesItemIdentifier: appId}completionBlock:^(BOOL result, NSError *error)
         {
             if (error)
             {
                 NSLog(@"%@",error);
             }
             
         }];
    }
    else
    {
        // < iOS6.0
        NSString *appUrl = [NSString stringWithFormat:@"itms-apps://itunes.apple.com/us/app/id%@?mt=8", appId];
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:appUrl]];
        
        //        UIWebView *callWebview = [[UIWebView alloc] init];
        //        NSURL *appURL =[NSURL URLWithString:appStore];
        //        [callWebview loadRequest:[NSURLRequest requestWithURL:appURL]];
        //        [self.view addSubview:callWebview];
    }
}

#pragma mark - SKStoreProductViewControllerDelegate
// Dismiss contorller
- (void)productViewControllerDidFinish:(SKStoreProductViewController *)viewController
{
    [viewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - View Lifecycle
- (void)createRecommendAppView
{
    CGFloat statusBarHeight = iOS7AddStatusHeight;
    CGFloat navHeight = CGRectGetHeight(self.navigationController.navigationBar.bounds);
    CGFloat height = 30;
    UIView *recommendAppView = [[UIView alloc] initWithFrame:CGRectMake(0, CGRectGetHeight(self.view.frame) - height - navHeight - statusBarHeight, CGRectGetWidth(self.view.frame), height)];
    [recommendAppView setBackgroundColor:[UIColor clearColor]];
    [self.view addSubview:recommendAppView];
    
    [self createRecommendAppButtons:recommendAppView];
}

- (void)createRecommendAppButtons:(UIView *)containerView
{
    // Recommend App
    UIButton *beautyTime = [[UIButton alloc] init];
    [beautyTime setTitle:GBLocalizedString(@"BeautyTime")
                forState:UIControlStateNormal];
    
    UIButton *photoBeautify = [[UIButton alloc] init];
    [photoBeautify setTitle:GBLocalizedString(@"PhotoBeautify")
                   forState:UIControlStateNormal];
    
    [photoBeautify setTag:1];
    [beautyTime setTag:2];
    
    CGFloat gap = 0, height = 30, width = 80;
    CGFloat fontSize = 16;
    NSString *fontName = @"迷你简启体"; // GBLocalizedString(@"FontName");
    photoBeautify.frame =  CGRectMake(gap, gap, width, height);
    [photoBeautify.titleLabel setFont:[UIFont fontWithName:fontName size:fontSize]];
    [photoBeautify.titleLabel setTextAlignment:NSTextAlignmentLeft];
    [photoBeautify setTitleColor:kBrightBlue forState:UIControlStateNormal];
    [photoBeautify addTarget:self action:@selector(recommendAppButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    
    beautyTime.frame =  CGRectMake(CGRectGetWidth(containerView.frame) - width - gap, gap, width, height);
    [beautyTime.titleLabel setFont:[UIFont fontWithName:fontName size:fontSize]];
    [beautyTime.titleLabel setTextAlignment:NSTextAlignmentRight];
    [beautyTime setTitleColor:kBrightBlue forState:UIControlStateNormal];
    [beautyTime addTarget:self action:@selector(recommendAppButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    
    [containerView addSubview:photoBeautify];
    [containerView addSubview:beautyTime];
}

- (void)createVideoPlayView
{
    CGFloat statusBarHeight = iOS7AddStatusHeight;
    CGFloat navHeight = CGRectGetHeight(self.navigationController.navigationBar.bounds);
    CGFloat gap = 10, len = MIN(((CGRectGetHeight(self.view.frame) - navHeight - statusBarHeight - 2*gap)/2), (CGRectGetWidth(self.view.frame) - navHeight - statusBarHeight - 2*gap));
    _videoContentView =  [[UIScrollView alloc] initWithFrame:CGRectMake(CGRectGetMidX(self.view.frame) - len/2, CGRectGetMidY(self.view.frame) - len - 2*gap - statusBarHeight, len, 2*len)];
    [_videoContentView setBackgroundColor:[UIColor clearColor]];
    [self.view addSubview:_videoContentView];
    
    // Video player 1
    _videoPlayerController1 = [[PBJVideoPlayerController alloc] init];
    _videoPlayerController1.delegate = self;
    _videoPlayerController1.view.frame = _videoContentView.bounds;
    _videoPlayerController1.view.clipsToBounds = YES;
    
    [self addChildViewController:_videoPlayerController1];
    [_videoContentView addSubview:_videoPlayerController1.view];
    
    _playButton1 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"play_button"]];
    _playButton1.center = _videoPlayerController1.view.center;
    [_videoPlayerController1.view addSubview:_playButton1];
    
    // Close video player
    UIImage *imageClose = [UIImage imageNamed:@"close"];
    CGFloat width = 50;
    _closeVideoPlayerButton1 = [[UIButton alloc] initWithFrame:CGRectMake(CGRectGetMinX(_videoContentView.frame) - width/2, CGRectGetMinY(_videoContentView.frame) - width/2, width, width)];
    [_closeVideoPlayerButton1 setImage:imageClose forState:(UIControlStateNormal)];
    [_closeVideoPlayerButton1 addTarget:self action:@selector(handleCloseVideo) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_closeVideoPlayerButton1];
    _closeVideoPlayerButton1.hidden = YES;
}

- (void)createNavigationBar
{
    [self.navigationController.navigationBar setBackgroundImage:[UIImage imageNamed:@"navbar"] forBarMetrics:UIBarMetricsDefault];
    NSString *fontName = GBLocalizedString(@"FontName");
    CGFloat fontSize = 24;
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [UIColor colorWithRed:0 green:0.7 blue:0.8 alpha:1];
    [self.navigationController.navigationBar setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                     [UIColor colorWithRed:1 green:1 blue:1 alpha:1], NSForegroundColorAttributeName,
                                                                     shadow,
                                                                     NSShadowAttributeName,
                                                                     [UIFont fontWithName:fontName size:fontSize], NSFontAttributeName,
                                                                     nil]];
    
    self.title = GBLocalizedString(@"PicInPic");
}

- (void)createNavigationItem
{
    NSString *fontName = GBLocalizedString(@"FontName");
    CGFloat fontSize = 18;
    UIBarButtonItem *rightItem = [[UIBarButtonItem alloc] initWithTitle:GBLocalizedString(@"Start") style:UIBarButtonItemStylePlain target:self action:@selector(showCustomActionSheet:withEvent:)];
    [rightItem setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor], NSFontAttributeName:[UIFont fontWithName:fontName size:fontSize]} forState:UIControlStateNormal];
    self.navigationItem.rightBarButtonItem = rightItem;
    
    UIBarButtonItem *leftItem = [[UIBarButtonItem alloc] initWithTitle:GBLocalizedString(@"Settings") style:UIBarButtonItemStylePlain target:self action:@selector(showSettingsModal:)];
    [leftItem setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor], NSFontAttributeName:[UIFont fontWithName:fontName size:fontSize]} forState:UIControlStateNormal];
    self.navigationItem.leftBarButtonItem = leftItem;
}

- (void)createPopTipView
{
    NSArray *colorSchemes = [NSArray arrayWithObjects:
                             [NSArray arrayWithObjects:[NSNull null], [NSNull null], nil],
                             [NSArray arrayWithObjects:[UIColor colorWithRed:134.0/255.0 green:74.0/255.0 blue:110.0/255.0 alpha:1.0], [NSNull null], nil],
                             [NSArray arrayWithObjects:[UIColor darkGrayColor], [NSNull null], nil],
                             [NSArray arrayWithObjects:[UIColor lightGrayColor], [UIColor darkTextColor], nil],
                             nil];
    NSArray *colorScheme = [colorSchemes objectAtIndex:foo4random()*[colorSchemes count]];
    UIColor *backgroundColor = [colorScheme objectAtIndex:0];
    UIColor *textColor = [colorScheme objectAtIndex:1];
    
    NSString *hint = GBLocalizedString(@"UsageHint");
    _popTipView = [[CMPopTipView alloc] initWithMessage:hint];
    if (backgroundColor && ![backgroundColor isEqual:[NSNull null]])
    {
        _popTipView.backgroundColor = backgroundColor;
    }
    if (textColor && ![textColor isEqual:[NSNull null]])
    {
        _popTipView.textColor = textColor;
    }
    
    _popTipView.animation = arc4random() % 2;
    _popTipView.has3DStyle = NO;
    _popTipView.dismissTapAnywhere = YES;
    [_popTipView autoDismissAnimated:YES atTimeInterval:6.0];
    
    [_popTipView presentPointingAtView:[self findRightNavBarItemView:self.navigationController.navigationBar] inView:self.navigationController.view animated:YES];
}

- (id)init
{
    self = [super init];
    
    if (self)
    {
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _videoArray = nil;
    
    _mediaType = kNone;
    _videoBackgroundPickURL = nil;
    self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"sharebg3"]];
    
    [self createNavigationBar];
    [self createNavigationItem];
    
    [self createVideoPlayView];
    [self createPopTipView];
    
    [self createRecommendAppView];
    
    // Embeded video frame
    [self setShouldDisplayInnerBorder:YES];
    
    NSString *demoVideoPath = getFilePath(DemoDestinationVideoName);
    [self reCalcVideoSize:demoVideoPath];
    [self playDemoVideo:demoVideoPath withinVideoPlayerController:_videoPlayerController1];
    
    // Delete temp files
    [self deleteTempDirectory];
}

- (void)dealloc
{
    NSLog(@"dealloc be invoked.");
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    
    // Deselect
    [VideoView setActiveVideoView:nil];
}

#pragma mark - reCalcVideoSize
- (void)reCalcVideoSize:(NSString *)videoPath
{
    CGFloat statusBarHeight = iOS7AddStatusHeight;
    CGFloat navHeight = CGRectGetHeight(self.navigationController.navigationBar.bounds);
    CGSize sizeVideo = [self reCalcVideoViewSize:videoPath];
    _videoContentView.frame =  CGRectMake(CGRectGetMidX(self.view.frame) - sizeVideo.width/2, CGRectGetMidY(self.view.frame) - sizeVideo.height/2 - statusBarHeight - navHeight, sizeVideo.width, sizeVideo.height);
    _videoPlayerController1.view.frame = _videoContentView.bounds;
    _playButton1.center = _videoPlayerController1.view.center;
    _closeVideoPlayerButton1.center = _videoContentView.frame.origin;
}

- (CGSize)reCalcVideoViewSize:(NSString *)videoPath
{
    CGSize resultSize = CGSizeZero;
    if (isStringEmpty(videoPath))
    {
        return resultSize;
    }
    
    UIImage *videoFrame = getImageFromVideoFrame(getFileURL(videoPath), kCMTimeZero);
    if (!videoFrame || videoFrame.size.height < 1 || videoFrame.size.width < 1)
    {
        return resultSize;
    }
    
    NSLog(@"reCalcVideoViewSize: %@, width: %f, height: %f", videoPath, videoFrame.size.width, videoFrame.size.height);
    
    CGFloat statusBarHeight = 0; //iOS7AddStatusHeight;
    CGFloat navHeight = 0; //CGRectGetHeight(self.navigationController.navigationBar.bounds);
    CGFloat gap = 15;
    CGFloat height = CGRectGetHeight(self.view.frame) - navHeight - statusBarHeight - 2*gap;
    CGFloat width = CGRectGetWidth(self.view.frame) - 2*gap;
    if (height < width)
    {
        width = height;
    }
    else if (height > width)
    {
        height = width;
    }
    CGFloat videoHeight = videoFrame.size.height, videoWidth = videoFrame.size.width;
    CGFloat scaleRatio = videoHeight/videoWidth;
    CGFloat resultHeight = 0, resultWidth = 0;
    if (videoHeight <= height && videoWidth <= width)
    {
        resultHeight = videoHeight;
        resultWidth = videoWidth;
    }
    else if (videoHeight <= height && videoWidth > width)
    {
        resultWidth = width;
        resultHeight = height*scaleRatio;
    }
    else if (videoHeight > height && videoWidth <= width)
    {
        resultHeight = height;
        resultWidth = width/scaleRatio;
    }
    else
    {
        if (videoHeight < videoWidth)
        {
            resultWidth = width;
            resultHeight = height*scaleRatio;
        }
        else if (videoHeight == videoWidth)
        {
            resultWidth = width;
            resultHeight = height;
        }
        else
        {
            resultHeight = height;
            resultWidth = width/scaleRatio;
        }
    }
    
    resultSize = CGSizeMake(resultWidth, resultHeight);
    return resultSize;
}

#pragma mark - Clear
- (void)clearEmbededVideo
{
    if (_videoArray && [_videoArray count] >= 1)
    {
        for (VideoView *view in _videoArray)
        {
            [view removeFromSuperview];
        }

        [_videoArray removeAllObjects];
        [VideoView setActiveVideoView:nil];
    }
}

#pragma mark - showDemoVideo
- (void)showDemoVideo:(NSString *)videoPath
{
    CGFloat statusBarHeight = iOS7AddStatusHeight;
    CGFloat navHeight = CGRectGetHeight(self.navigationController.navigationBar.bounds);
    CGSize size = [self reCalcVideoViewSize:videoPath];
    _demoVideoContentView =  [[UIView alloc] initWithFrame:CGRectMake(CGRectGetMidX(self.view.frame) - size.width/2, CGRectGetMidY(self.view.frame) - size.height/2 - navHeight - statusBarHeight, size.width, size.height)];
    [self.view addSubview:_demoVideoContentView];
    
    // Video player of destination
    _demoVideoPlayerController = [[PBJVideoPlayerController alloc] init];
    _demoVideoPlayerController.view.frame = _demoVideoContentView.bounds;
    _demoVideoPlayerController.view.clipsToBounds = YES;
    _demoVideoPlayerController.videoView.videoFillMode = AVLayerVideoGravityResizeAspect;
    _demoVideoPlayerController.delegate = self;
    //    _demoVideoPlayerController.playbackLoops = YES;
    [_demoVideoContentView addSubview:_demoVideoPlayerController.view];
    
    _demoPlayButton = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"play_button"]];
    _demoPlayButton.center = _demoVideoPlayerController.view.center;
    [_demoVideoPlayerController.view addSubview:_demoPlayButton];
    
    // Popup modal view
    [[KGModal sharedInstance] setCloseButtonType:KGModalCloseButtonTypeLeft];
    [[KGModal sharedInstance] showWithContentView:_demoVideoContentView andAnimated:YES];
    
    [self playDemoVideo:videoPath withinVideoPlayerController:_demoVideoPlayerController];
}

#pragma mark - Handle Event
- (void)handleCloseVideo
{
    NSLog(@"handleCloseVideo");
    
    [self clearEmbededVideo];
    [_videoPlayerController1 clearView];
    
    [self showVideoPlayView:NO];
    self.videoBackgroundPickURL = nil;
}

- (void)handleConvert
{
    if (!_videoBackgroundPickURL)
    {
        NSString *message = GBLocalizedString(@"VideoIsEmptyHint");
        showAlertMessage(message, nil);
        return;
    }

    [VideoView setActiveVideoView:nil];
    
    NSMutableArray *videoFileArray = [NSMutableArray arrayWithCapacity:1];
    [videoFileArray addObject:[_videoBackgroundPickURL relativePath]];
    
    if (_videoArray && [_videoArray count] > 0)
    {
        for (VideoView *view in _videoArray)
        {
            NSString *videoPath = view.getFilePath;
            [videoFileArray addObject:videoPath];
            
            [view setVideoContentRect:_videoContentView.frame];
        }
        
        [[ExportEffects sharedInstance] initVideoArray:_videoArray];
    }
    
    if (!videoFileArray || [videoFileArray count] < 1)
    {
        NSLog(@"videoFileArray is empty.");
        return;
    }
    
    ProgressBarShowLoading(GBLocalizedString(@"Processing"));
    
    [[ExportEffects sharedInstance] setExportProgressBlock: ^(NSNumber *percentage) {
        
        // Export progress
        [self retrievingProgress:percentage title:GBLocalizedString(@"SavingVideo")];
    }];
    
    [[ExportEffects sharedInstance] setFinishVideoBlock: ^(BOOL success, id result) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if (success)
            {
                ProgressBarDismissLoading(GBLocalizedString(@"Success"));
            }
            else
            {
                ProgressBarDismissLoading(GBLocalizedString(@"Failed"));
            }
            
            // Alert
            NSString *ok = GBLocalizedString(@"OK");
            [UIAlertView showWithTitle:nil
                               message:result
                     cancelButtonTitle:ok
                     otherButtonTitles:nil
                              tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
                                  if (buttonIndex == [alertView cancelButtonIndex])
                                  {
                                      NSLog(@"Alert Cancelled");
                                      
                                      [NSThread sleepForTimeInterval:0.5];
                                      
                                      // Demo result video
                                      if (!isStringEmpty([ExportEffects sharedInstance].filenameBlock()))
                                      {
                                          NSString *outputPath = [ExportEffects sharedInstance].filenameBlock();
                                          [self showDemoVideo:outputPath];
                                      }
                                  }
                              }];
            
            [self showVideoPlayView:TRUE];
        });
    }];
    
    [[ExportEffects sharedInstance] addEffectToVideo:videoFileArray withAudioFilePath:nil];
}

- (void)recommendAppButtonAction:(id)sender
{
    UIButton *button = (UIButton *)sender;
    switch (button.tag)
    {
        case 1:
        {
            // Photo Beautify Bundle
            [self showAppInAppStore:@"945682627"];
            break;
        }
        case 2:
        {
            // BeautyTime
            [self showAppInAppStore:@"964149617"];
            break;
        }
        default:
            break;
    }
    
    [button setSelected:YES];
}

#pragma mark - NSUserDefaults
#pragma mark - needDrawInnerVideoBorder
- (void)setShouldDisplayInnerBorder:(BOOL)shouldDisplay
{
    NSString *shouldDisplayInnerBorder = @"ShouldDisplayInnerBorder";
    NSUserDefaults *userDefaultes = [NSUserDefaults standardUserDefaults];
    if (shouldDisplay)
    {
        [userDefaultes setBool:YES forKey:shouldDisplayInnerBorder];
    }
    else
    {
        [userDefaultes setBool:NO forKey:shouldDisplayInnerBorder];
    }
    
    [userDefaultes synchronize];
}

@end

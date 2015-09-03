//
//  ExportEffects
//  PictureInPicture
//
//  Created by Johnny Xu(徐景周) on 5/30/15.
//  Copyright (c) 2015 Future Studio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

typedef NSString *(^JZOutputFilenameBlock)();
typedef void (^JZFinishVideoBlock)(BOOL success, id result);
typedef void (^JZExportProgressBlock)(NSNumber *percentage);

@interface ExportEffects : NSObject

@property (copy, nonatomic) JZFinishVideoBlock finishVideoBlock;
@property (copy, nonatomic) JZExportProgressBlock exportProgressBlock;
@property (copy, nonatomic) JZOutputFilenameBlock filenameBlock;

+ (ExportEffects *)sharedInstance;

- (void)initVideoArray:(NSMutableArray *)videos;
- (void)writeExportedVideoToAssetsLibrary:(NSString *)outputPath;

- (void)addEffectToVideo:(NSArray *)videoFilePathArray withAudioFilePath:(NSString *)audioFilePath;

@end

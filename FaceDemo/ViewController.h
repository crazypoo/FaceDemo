//
//  ViewController.h
//  FaceDemo
//
//  Created by MYX on 2017/4/10.
//  Copyright © 2017年 邓杰豪. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface ViewController : UIViewController<UIGestureRecognizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) IBOutlet UIView *previewView;


@end


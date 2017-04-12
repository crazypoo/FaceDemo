//
//  ViewController.m
//  FaceDemo
//
//  Created by MYX on 2017/4/10.
//  Copyright © 2017年 邓杰豪. All rights reserved.
//

#import "ViewController.h"
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>

static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};

@interface ViewController ()<CAAnimationDelegate>
{
    BOOL isUsingFrontFacingCamera;
    AVCaptureVideoDataOutput *videoDataOutput;
    dispatch_queue_t videoDataOutputQueue;
    AVCaptureVideoPreviewLayer *previewLayer;
    UIImage *borderImage;
    CIDetector *faceDetector;
    
    UIImage *glassImage;
    UIImage *noseImage;
    
    UIView *ffView;
    UIView *rView;
    UIView *mView;
}

@end

@implementation ViewController

@synthesize previewView = _previewView;

- (void)setupAVCapture
{
    NSError *error = nil;
    
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone){
        [session setSessionPreset:AVCaptureSessionPreset640x480];
    } else {
        [session setSessionPreset:AVCaptureSessionPresetPhoto];
    }
    
    AVCaptureDevice *device;
    
    AVCaptureDevicePosition desiredPosition = AVCaptureDevicePositionFront;
    
    for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if ([d position] == desiredPosition) {
            device = d;
            isUsingFrontFacingCamera = YES;
            break;
        }
    }
    if( nil == device )
    {
        isUsingFrontFacingCamera = NO;
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    
    if( !error ) {
        
        if ( [session canAddInput:deviceInput] ){
            [session addInput:deviceInput];
        }
        
        
        videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        
        NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:
                                           [NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
        [videoDataOutput setVideoSettings:rgbOutputSettings];
        [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES]; 
        
        videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
        [videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
        
        if ( [session canAddOutput:videoDataOutput] ){
            [session addOutput:videoDataOutput];
        }
        
        [[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
        
        previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
        previewLayer.backgroundColor = [[UIColor blackColor] CGColor];
        previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        
        CALayer *rootLayer = [self.previewView layer];
        [rootLayer setMasksToBounds:YES];
        [previewLayer setFrame:[rootLayer bounds]];
        [rootLayer addSublayer:previewLayer];
        [session startRunning];
        
    }
    session = nil;
    if (error) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:
                                  [NSString stringWithFormat:@"Failed with error %d", (int)[error code]] message:[error localizedDescription] delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil];
        [alertView show];
        [self teardownAVCapture];
    }
}

- (void)teardownAVCapture
{
    videoDataOutput = nil;
    if (videoDataOutputQueue) {
        videoDataOutputQueue = nil;
    }
    [previewLayer removeFromSuperlayer];
    previewLayer = nil;
}

- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message
{
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        UIAlertView *alertView = [[UIAlertView alloc]
                                  initWithTitle:[NSString stringWithFormat:@"%@ (%d)", message, (int)[error code]]
                                  message:[error localizedDescription]
                                  delegate:nil
                                  cancelButtonTitle:@"Dismiss"
                                  otherButtonTitles:nil];
        [alertView show];
    });
}


- (CGRect)videoPreviewBoxForGravity:(NSString *)gravity frameSize:(CGSize)frameSize apertureSize:(CGSize)apertureSize
{
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat viewRatio = frameSize.width / frameSize.height;
    
    CGSize size = CGSizeZero;
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
        if (viewRatio > apertureRatio) {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        } else {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        if (viewRatio > apertureRatio) {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        } else {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
        size.width = frameSize.width;
        size.height = frameSize.height;
    }
    
    CGRect videoBox;
    videoBox.size = size;
    if (size.width < frameSize.width)
        videoBox.origin.x = (frameSize.width - size.width) / 2;
    else
        videoBox.origin.x = (size.width - frameSize.width) / 2;
    
    if ( size.height < frameSize.height )
        videoBox.origin.y = (frameSize.height - size.height) / 2;
    else
        videoBox.origin.y = (size.height - frameSize.height) / 2;
    
    return videoBox;
}

#define kRadianToDegrees(radian) (radian*180.0)/(M_PI)
- (void)drawFaces:(NSArray *)features forVideoBox:(CGRect)clearAperture orientation:(UIDeviceOrientation)orientation
{
    NSArray *sublayers = [NSArray arrayWithArray:[previewLayer sublayers]];
    NSInteger sublayersCount = [sublayers count], currentSublayer = 0;
    NSInteger featuresCount = [features count], currentFeature = 0;
    
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    
    for ( CALayer *layer in sublayers ) {
        if ( [[layer name] isEqualToString:@"FaceLayer"] )
            [layer setHidden:YES];
    }
    
    if ( featuresCount == 0 ) {
        [CATransaction commit];
        return;
    }
    
    CGSize parentFrameSize = [self.previewView frame].size;
    NSString *gravity = [previewLayer videoGravity];
    BOOL isMirrored = previewLayer.connection.videoMirrored;
    CGRect previewBox = [self videoPreviewBoxForGravity:gravity frameSize:parentFrameSize apertureSize:clearAperture.size];
    
//    [self.previewView setTransform:CGAffineTransformMakeScale(1, -1)];

    for ( CIFaceFeature *ff in features ) {
        CGRect faceRect = [ff bounds];
        
        CGFloat temp = faceRect.size.width+150;
        faceRect.size.width = faceRect.size.height+100;
        faceRect.size.height = temp;
        temp = faceRect.origin.x;
        faceRect.origin.x = faceRect.origin.y;
        faceRect.origin.y = temp;

        CGFloat widthScaleBy = previewBox.size.width / clearAperture.size.height;
        CGFloat heightScaleBy = previewBox.size.height / clearAperture.size.width;
        faceRect.size.width *= widthScaleBy;
        faceRect.size.height *= heightScaleBy;
        faceRect.origin.x *= widthScaleBy;
        faceRect.origin.y *= heightScaleBy;
        
        if ( isMirrored )
            faceRect = CGRectOffset(faceRect, previewBox.origin.x + previewBox.size.width - faceRect.size.width - (faceRect.origin.x * 2)+30, previewBox.origin.y-100);
        else
            faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y);
        
        CALayer *featureLayer = nil;
        
        while ( !featureLayer && (currentSublayer < sublayersCount) ) {
            CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
            if ( [[currentLayer name] isEqualToString:@"FaceLayer"] ) {
                featureLayer = currentLayer;
                [currentLayer setHidden:NO];
            }
        }
        
        if ( !featureLayer ) {
            featureLayer = [[CALayer alloc]init];
            featureLayer.contents = (id)borderImage.CGImage;
            [featureLayer setName:@"FaceLayer"];
            [previewLayer addSublayer:featureLayer];
            featureLayer = nil;
            
        }
        [featureLayer setFrame:faceRect];
        
//        CGFloat a = atan((faceRect.origin.y-faceRect.size.height/2)/(faceRect.origin.x-faceRect.size.width/2));
//
//        [featureLayer addAnimation:[self rotation:1000 degree:kRadianToDegrees(a) direction:1 repeatCount:MAXFLOAT] forKey:nil];
        
        
//        [ffView setCenter:ff.leftEyePosition];
//        [rView setCenter:ff.rightEyePosition];
//        [mView setCenter:ff.mouthPosition];

//        CALayer *glassFeatureLayer = nil;
//        
//        while ( !glassFeatureLayer && (currentSublayer < sublayersCount) ) {
//            CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
//            if ( [[currentLayer name] isEqualToString:@"FaceLayer"] ) {
//                glassFeatureLayer = currentLayer;
//                [currentLayer setHidden:NO];
//            }
//        }
//        
//        if ( !glassFeatureLayer ) {
//            glassFeatureLayer = [[CALayer alloc]init];
//            glassFeatureLayer.contents = (id)glassImage.CGImage;
//            [glassFeatureLayer setName:@"FaceLayer"];
//            [self.previewLayer addSublayer:glassFeatureLayer];
//            glassFeatureLayer = nil;
//            
//        }
//        [glassFeatureLayer setFrame:CGRectMake(faceRect.origin.x, faceRect.origin.y+10, faceRect.size.width, 50)];
//        
//        CALayer *noseFeatureLayer = nil;
//        
//        while ( !noseFeatureLayer && (currentSublayer < sublayersCount) ) {
//            CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
//            if ( [[currentLayer name] isEqualToString:@"FaceLayer"] ) {
//                noseFeatureLayer = currentLayer;
//                [currentLayer setHidden:NO];
//            }
//        }
//        
//        if ( !noseFeatureLayer ) {
//            noseFeatureLayer = [[CALayer alloc]init];
//            noseFeatureLayer.contents = (id)noseImage.CGImage;
//            [noseFeatureLayer setName:@"FaceLayer"];
//            [self.previewLayer addSublayer:noseFeatureLayer];
//            noseFeatureLayer = nil;
//            
//        }
//        
//        [noseFeatureLayer setFrame:CGRectMake(faceRect.origin.x +(faceRect.size.width-10)/2, glassFeatureLayer.frame.size.height+glassFeatureLayer.frame.origin.y+30, 10, 10)];
        
        
        switch (orientation) {
            case UIDeviceOrientationPortrait:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
//                [glassFeatureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
//                [noseFeatureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];

                break;
            case UIDeviceOrientationPortraitUpsideDown:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
//                [glassFeatureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
//                [noseFeatureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];

                break;
            case UIDeviceOrientationLandscapeLeft:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
//                [glassFeatureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
//                [noseFeatureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];

                break;
            case UIDeviceOrientationLandscapeRight:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
//                [glassFeatureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
//                [noseFeatureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];

                break;
            case UIDeviceOrientationFaceUp:
            case UIDeviceOrientationFaceDown:
            default:
                break;
        }
        currentFeature++;
    }
    
    [CATransaction commit];
}

- (NSNumber *) exifOrientation: (UIDeviceOrientation) orientation
{
    int exifOrientation;
        enum {
        PHOTOS_EXIF_0ROW_TOP_0COL_LEFT			= 1, 
        PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT			= 2, 
        PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3, 
        PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4, 
        PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5, 
        PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6, 
        PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7, 
        PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8
    };
    
    switch (orientation) {
        case UIDeviceOrientationPortraitUpsideDown:
            exifOrientation = PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM;
            break;
        case UIDeviceOrientationLandscapeLeft:
            if (isUsingFrontFacingCamera)
                exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
            else
                exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
            break;
        case UIDeviceOrientationLandscapeRight:
            if (isUsingFrontFacingCamera)
                exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
            else
                exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
            break;
        case UIDeviceOrientationPortrait:
        default:
            exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP;
            break;
    }
    return [NSNumber numberWithInt:exifOrientation];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer
                                                      options:(__bridge NSDictionary *)attachments];
    if (attachments) {
        CFRelease(attachments);
    }
    
    UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
    
    NSDictionary *imageOptions = nil;
    
    imageOptions = [NSDictionary dictionaryWithObject:[self exifOrientation:curDeviceOrientation]
                                               forKey:CIDetectorImageOrientation];
    
    NSArray *features = [faceDetector featuresInImage:ciImage
                                                   options:imageOptions];
    
    CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    CGRect cleanAperture = CMVideoFormatDescriptionGetCleanAperture(fdesc, false /*originIsTopLeft == false*/);
    
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [self drawFaces:features 
            forVideoBox:cleanAperture 
            orientation:curDeviceOrientation];
    });
}


#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    
    [self setupAVCapture];
    borderImage = [UIImage imageNamed:@"6666666"];
    NSDictionary *detectorOptions = [[NSDictionary alloc] initWithObjectsAndKeys:CIDetectorAccuracyLow, CIDetectorAccuracy, nil];
    faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions];
    
    glassImage = [UIImage imageNamed:@"glass_3"];
    
    noseImage = [self createImageWithColor:[UIColor redColor]];
    
//    ffView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
//    ffView.backgroundColor = [UIColor blueColor];
//    [self.previewView addSubview:ffView];
//    
//    rView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
//    rView.backgroundColor = [UIColor redColor];
//    [self.previewView addSubview:rView];
//    
//    mView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
//    mView.backgroundColor = [UIColor greenColor];
//    [self.previewView addSubview:mView];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    [self teardownAVCapture];
    faceDetector = nil;
    borderImage = nil;
    glassImage = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

-(UIImage*)createImageWithColor:(UIColor*)color
{
    CGRect rect = CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
    UIGraphicsBeginImageContext(rect.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [color CGColor]);
    CGContextFillRect(context, rect);
    UIImage *theImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return theImage;
}

#pragma mark ---------------> 旋转动画

-(CABasicAnimation *)rotation:(float)dur degree:(float)degree direction:(int)direction repeatCount:(int)repeatCount
{
    CATransform3D rotationTransform = CATransform3DMakeRotation(degree, 0, 0, direction);
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform"];
    animation.toValue = [NSValue valueWithCATransform3D:rotationTransform];
    animation.duration  =  dur;
    animation.autoreverses = NO;
    animation.cumulative = NO;
    animation.fillMode = kCAFillModeForwards;
    animation.repeatCount = repeatCount;
    animation.delegate = self;
    
    return animation;
    
}
@end


//
//  WebRTCModuleRTCMediaStream.m
//
//  Created by one on 2015/9/24.
//  Copyright © 2015 One. All rights reserved.
//

#import <objc/runtime.h>
#import <sys/utsname.h>

#import <React/RCTEventDispatcher.h>
#import <React/RCTImageLoader.h>

#import <WebRTC/RTCAVFoundationVideoSource.h>
#import <WebRTC/RTCVideoTrack.h>
#import <WebRTC/RTCMediaConstraints.h>

#import "WebRTCModule+RTCPeerConnection.h"
#import <AssetsLibrary/ALAssetsLibrary.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>

@implementation AVCaptureDevice (React)

- (NSString*)positionString {
  switch (self.position) {
    case AVCaptureDevicePositionUnspecified: return @"unspecified";
    case AVCaptureDevicePositionBack: return @"back";
    case AVCaptureDevicePositionFront: return @"front";
  }
  return nil;
}

@end

@implementation WebRTCModule (RTCMediaStream)

AVCaptureStillImageOutput *stillImageOutput;
RTCAVFoundationVideoSource *videoSource;

/**
 * {@link https://www.w3.org/TR/mediacapture-streams/#navigatorusermediaerrorcallback}
 */
typedef void (^NavigatorUserMediaErrorCallback)(NSString *errorType, NSString *errorMessage);

/**
 * {@link https://www.w3.org/TR/mediacapture-streams/#navigatorusermediasuccesscallback}
 */
typedef void (^NavigatorUserMediaSuccessCallback)(RTCMediaStream *mediaStream);

typedef NS_ENUM(NSInteger, RCTCameraCaptureTarget) {
    RCTCameraCaptureTargetMemory = 0,
    RCTCameraCaptureTargetDisk = 1,
    RCTCameraCaptureTargetTemp = 2,
    RCTCameraCaptureTargetCameraRoll = 3
};

- (RTCMediaConstraints *)defaultMediaStreamConstraints {
  NSDictionary *mandatoryConstraints
      = @{ kRTCMediaConstraintsMinWidth     : @"1280",
           kRTCMediaConstraintsMinHeight    : @"720",
           kRTCMediaConstraintsMinFrameRate : @"30" };
  RTCMediaConstraints* constraints =
  [[RTCMediaConstraints alloc]
   initWithMandatoryConstraints:mandatoryConstraints
   optionalConstraints:nil];
  return constraints;
}

- (NSDictionary *)constantsToExport
{
    return @{
             @"CaptureTarget": @{
                     @"memory": @(RCTCameraCaptureTargetMemory),
                     @"disk": @(RCTCameraCaptureTargetDisk),
                     @"temp": @(RCTCameraCaptureTargetTemp),
                     @"cameraRoll": @(RCTCameraCaptureTargetCameraRoll)
                     }
             };
}

RCT_EXPORT_METHOD(setZoom:(CGFloat)zoomFactor) {
  if (isnan(zoomFactor)) {
      return;
  }

  dispatch_async(self.sessionQueue, ^{
    NSError *error = nil;

    if ([self.videoCaptureDevice lockForConfiguration:&error]) {
        // device.videoZoomFactor = zoomFactor;
        [self.videoCaptureDevice rampToVideoZoomFactor:zoomFactor withRate:10.0];
        [self.videoCaptureDevice unlockForConfiguration];
    } else {
        NSLog(@"error: %@", error);
    }
  });
}

RCT_EXPORT_METHOD(setFocusPoint:(CGPoint)focusPoint: (BOOL)lockFocus) {
  dispatch_async( self.sessionQueue, ^{
      AVCaptureDevice *device = self.videoCaptureDevice;
      AVCaptureFocusMode *focusMode = lockFocus ? AVCaptureFocusModeAutoFocus : AVCaptureFocusModeContinuousAutoFocus;
      AVCaptureExposureMode *exposureMode = AVCaptureExposureModeContinuousAutoExposure;

      NSError *error = nil;
      if ( [device lockForConfiguration:&error] ) {
          // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
          // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
          if (device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode]) {
              // NSLog(@"KingdamApp current focusPointOfInterest: %@", NSStringFromCGPoint(device.focusPointOfInterest));
              // NSLog(@"KingdamApp focusPointOfInterest: %@", NSStringFromCGPoint(focusPoint));
              device.focusPointOfInterest = focusPoint;
              device.focusMode = focusMode;
          }

          if ( device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode] ) {
              // NSLog(@"KingdamApp current exposurePointOfInterest: %@", NSStringFromCGPoint(device.exposurePointOfInterest));
              // NSLog(@"KingdamApp exposurePointOfInterest: %@", NSStringFromCGPoint(focusPoint));
              device.exposurePointOfInterest = focusPoint;
              device.exposureMode = exposureMode;
          }

          [device unlockForConfiguration];
      }
      else {
          //NSLog( @"Could not lock device for configuration: %@", error );
      }
  } );
}

RCT_EXPORT_METHOD(setExposure:(CGFloat)exposure) {
  if (isnan(exposure)) {
      return;
  }

  dispatch_async(self.sessionQueue, ^{
    NSError *error = nil;

    if ([self.videoCaptureDevice lockForConfiguration:&error]) {
        self.videoCaptureDevice.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        [self.videoCaptureDevice setExposureTargetBias:exposure completionHandler:nil];
        [self.videoCaptureDevice unlockForConfiguration];
    } else {
        NSLog(@"error: %@", error);
    }
  });
}

RCT_EXPORT_METHOD(disableBarcodeScanner) {
  [self setBarcodeScannerEnabled:NO];
}

RCT_EXPORT_METHOD(enableBarcodeScanner) {
  [self setBarcodeScannerEnabled:YES];
}

RCT_EXPORT_METHOD(disableOrientationListener) {
  videoSource.listenOrientationChanges = NO;
}

RCT_EXPORT_METHOD(enableOrientationListener) {
  videoSource.listenOrientationChanges = YES;
}

RCT_EXPORT_METHOD(setOrientation:(NSInteger)orientation) {
  if (videoSource.listenOrientationChanges) {
    return;
  }

  videoSource.orientation = orientation;
}

RCT_EXPORT_METHOD(resetExposure) {
  dispatch_async(self.sessionQueue, ^{
    NSError *error = nil;

    if ([self.videoCaptureDevice lockForConfiguration:&error]) {
        [self.videoCaptureDevice setExposureTargetBias:0 completionHandler:nil];
        self.videoCaptureDevice.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        [self.videoCaptureDevice unlockForConfiguration];
    } else {
        NSLog(@"error: %@", error);
    }
  });
}

RCT_EXPORT_METHOD(setColorTemperature:(CGFloat)temperature tint:(CGFloat)tint) {
  if (isnan(temperature)) {
      return;
  }
  dispatch_async(self.sessionQueue, ^{
    NSError *error = nil;

    if ([self.videoCaptureDevice lockForConfiguration:&error]) {
      AVCaptureWhiteBalanceTemperatureAndTintValues gains = {
          .temperature = temperature,
          .tint = tint,
      };

      AVCaptureWhiteBalanceGains normalizedGains = [self normalizedGains:[self.videoCaptureDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:gains]];
      [self.videoCaptureDevice setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:normalizedGains completionHandler:nil];
      [self.videoCaptureDevice unlockForConfiguration];
    } else {
        NSLog(@"error: %@", error);
    }
  });
}

RCT_EXPORT_METHOD(resetColorTemperature) {
  dispatch_async(self.sessionQueue, ^{
    NSError *error = nil;

    if ([self.videoCaptureDevice lockForConfiguration:&error]) {
      self.videoCaptureDevice.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
      [self.videoCaptureDevice unlockForConfiguration];
    } else {
        NSLog(@"error: %@", error);
    }
  });
}

RCT_EXPORT_METHOD(setCameraSettings:(NSDictionary *)settings
                           setCameraSettingsResolver:(RCTPromiseResolveBlock)resolve
                           setCameraSettingsResolveRejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(self.sessionQueue, ^{
    NSError *error = nil;

    CGFloat zoomLevel = settings[@"zoomLevel"] != nil ? [[settings valueForKey:@"zoomLevel"] floatValue] : 1.0f;
    CGFloat tint = settings[@"tint"] != nil ? [[settings valueForKey:@"tint"] floatValue] : 0.0f;
    CGFloat exposure = settings[@"exposure"] != nil ? [[settings valueForKey:@"exposure"] floatValue] : nanf(NULL);
    CGFloat colorTemperature = settings[@"colorTemperature"] != nil ? [[settings valueForKey:@"colorTemperature"] floatValue] : nanf(NULL);
    CGPoint focusPoint = settings[@"focusPoint"] != nil ? [[settings valueForKey:@"focusPoint"] CGPointValue] : CGPointMake(0.5, 0.5);
    AVCaptureFocusMode *focusMode = settings[@"focusPoint"] != nil ? AVCaptureFocusModeAutoFocus : AVCaptureFocusModeContinuousAutoFocus;
    int captureQuality = settings[@"captureQuality"] != nil ? [[settings valueForKey:@"captureQuality"] intValue] : NULL;

    if ([self.videoCaptureDevice lockForConfiguration:&error]) {
      [self setCaptureQuality:captureQuality];

      self.videoCaptureDevice.videoZoomFactor = zoomLevel;
      // NSLog(@"KingdamApp:Native:setVideoZoomFactor: %f", zoomLevel);

      if (isnan(colorTemperature)) {
        self.videoCaptureDevice.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
      } else {
        AVCaptureWhiteBalanceTemperatureAndTintValues gains = {
            .temperature = colorTemperature,
            .tint = tint,
        };

        AVCaptureWhiteBalanceGains normalizedGains = [self normalizedGains:[self.videoCaptureDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:gains]];
        [self.videoCaptureDevice setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:normalizedGains completionHandler:nil];
      }
      if (isnan(exposure)) {
        [self.videoCaptureDevice setExposureTargetBias:0 completionHandler:nil];
      } else {
        [self.videoCaptureDevice setExposureTargetBias:exposure completionHandler:nil];
      }

      self.videoCaptureDevice.focusPointOfInterest = focusPoint;
      self.videoCaptureDevice.exposurePointOfInterest = focusPoint;

      self.videoCaptureDevice.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
      self.videoCaptureDevice.focusMode = focusMode;

      [self.videoCaptureDevice unlockForConfiguration];

      resolve(@(true));
    } else {
        NSLog(@"KingdamApp:Native:error: %@", error);
        reject(@"failed_to_set_camera_settings", @"Failed to set Camera settings", error);
    }
  });
}

RCT_EXPORT_METHOD(fetchMinAndMaxValues:(RCTResponseSenderBlock)successCallback
                  errorCallback:(RCTResponseSenderBlock)errorCallback) {

  CGFloat maxColorTemperatureHardcodedValue = 10000.0f;
  AVCaptureWhiteBalanceTemperatureAndTintValues maxWhiteBalanceGains = {
      .temperature = maxColorTemperatureHardcodedValue,
      .tint = 0,
  };
  AVCaptureWhiteBalanceTemperatureAndTintValues minWhiteBalanceGains = {
      .temperature = 0,
      .tint = 0,
  };

  AVCaptureWhiteBalanceGains maxWhiteBalanceGainsNormalized = [self normalizedGains:[self.videoCaptureDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:maxWhiteBalanceGains]];
  AVCaptureWhiteBalanceGains minWhiteBalanceGainsNormalized = [self normalizedGains:[self.videoCaptureDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:minWhiteBalanceGains]];

  AVCaptureWhiteBalanceTemperatureAndTintValues maxColorTempAndTint = [self.videoCaptureDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:maxWhiteBalanceGainsNormalized];
  AVCaptureWhiteBalanceTemperatureAndTintValues minColorTempAndTint = [self.videoCaptureDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:minWhiteBalanceGainsNormalized];

  CGFloat exposureDefaultValue = (abs(self.videoCaptureDevice.maxExposureTargetBias) - abs(self.videoCaptureDevice.minExposureTargetBias)) / 2;

  CGFloat maxColorTemperatureRawValue = maxColorTempAndTint.temperature;
  if (maxColorTemperatureRawValue < maxColorTemperatureHardcodedValue) {
    maxColorTemperatureRawValue = ceil(maxColorTemperatureRawValue / 100.0f);
  } else {
    maxColorTemperatureRawValue = floor(maxColorTemperatureRawValue / 100.0f);
  }

  CGFloat maxColorTemperatureValue = roundf(maxColorTemperatureRawValue) * 100;
  CGFloat minColorTemperatureValue = roundf(ceil(minColorTempAndTint.temperature / 100.0f)) * 100;
  CGFloat colorTemperatureDefaultValue = roundf(ceil((maxColorTemperatureValue - ((maxColorTemperatureValue - minColorTemperatureValue) / 2)) / 100.0f)) * 100;

  NSDictionary* result= @{
    @"zoomLevel" : @{
      @"minimumValue" : @1, // TODO: in ios 11+ use minAvailableVideoZoomFactor
      @"maximumValue" : @8, // @16, // TODO: in ios 11+ use maxAvailableVideoZoomFactor
      @"defaultValue" : @1
    },
    @"exposure" : @{
      @"minimumValue" : @(MAX(-4, self.videoCaptureDevice.minExposureTargetBias)),
      @"maximumValue" : @(MIN(4, self.videoCaptureDevice.maxExposureTargetBias)),
      @"defaultValue" : @(exposureDefaultValue)
    },
    @"colorTemperature" : @{
      @"minimumValue" : @(minColorTemperatureValue),
      @"maximumValue" : @(maxColorTemperatureValue),
      @"defaultValue" : @(colorTemperatureDefaultValue)
    },
    @"tint" : @{
      @"minimumValue" : @-150,
      @"maximumValue" : @150,
      @"defaultValue" : @0
    },
    @"focusPoint" : @{
      @"minimumValue" : @[@0, @0],
      @"maximumValue" : @[@1.0, @1.0],
      @"defaultValue" : @[@0.5, @0.5]
    }
  };

  successCallback(@[result]);
}

RCT_EXPORT_METHOD(takePicture:(NSDictionary *)options
                  successCallback:(RCTResponseSenderBlock)successCallback
                  errorCallback:(RCTResponseSenderBlock)errorCallback) {

    NSInteger captureTarget = [[options valueForKey:@"captureTarget"] intValue];
    NSInteger maxSize = [[options valueForKey:@"maxSize"] intValue];
    AVCaptureVideoOrientation orientation = options[@"orientation"] != nil ? [options[@"orientation"] integerValue] : 0;
    bool fixOrientation = true;

    dispatch_async(self.sessionQueue, ^{
      #if TARGET_IPHONE_SIMULATOR
            CGSize size = CGSizeMake(720, 1280);
            UIGraphicsBeginImageContextWithOptions(size, YES, 0);
                // Thanks https://gist.github.com/kylefox/1689973
                CGFloat hue = ( arc4random() % 256 / 256.0 );  //  0.0 to 1.0
                CGFloat saturation = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from white
                CGFloat brightness = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from black
                UIColor *color = [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1];
                [color setFill];
                UIRectFill(CGRectMake(0, 0, size.width, size.height));
                NSDate *currentDate = [NSDate date];
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                [dateFormatter setDateFormat:@"dd.MM.YY HH:mm:ss"];
                NSString *text = [dateFormatter stringFromDate:currentDate];
                UIFont *font = [UIFont systemFontOfSize:40.0];
                NSDictionary *attributes = [NSDictionary dictionaryWithObjects:
                                            @[font, [UIColor blackColor]]
                                                                       forKeys:
                                            @[NSFontAttributeName, NSForegroundColorAttributeName]];
                [text drawAtPoint:CGPointMake(size.width/3, size.height/2) withAttributes:attributes];
                UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            NSData *imageData = UIImageJPEGRepresentation(image, 1.0);
            [self saveImage:imageData target:captureTarget metadata:nil success:successCallback error:errorCallback];
      #else
        if (orientation) {
          [[stillImageOutput connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:orientation];
        }
        [stillImageOutput captureStillImageAsynchronouslyFromConnection:[stillImageOutput connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {

            if (imageDataSampleBuffer) {
                NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];

                // Create image source
                CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)imageData, NULL);

                // Get all the metadata in the image
                NSMutableDictionary *imageMetadata = [(NSDictionary *) CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) mutableCopy];

                // Create cgimage
                CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);

                // Rotate it
                CGImageRef rotatedCGImage;

                if (fixOrientation) {
                  // Get metadata orientation
                  int metadataOrientation = [[imageMetadata objectForKey:(NSString *)kCGImagePropertyOrientation] intValue];

                  bool rotated = false;
                  //see http://www.impulseadventure.com/photo/exif-orientation.html
                  if (metadataOrientation == 6) {
                    rotatedCGImage = [self newCGImageRotatedByAngle:cgImage angle:270];
                    rotated = true;
                  } else if (metadataOrientation == 3) {
                    rotatedCGImage = [self newCGImageRotatedByAngle:cgImage angle:180];
                    rotated = true;
                  } else {
                    rotatedCGImage = cgImage;
                  }

                  if(rotated) {
                    [imageMetadata setObject:[NSNumber numberWithInteger:1] forKey:(NSString *)kCGImagePropertyOrientation];
                    CGImageRelease(cgImage);
                  }
                } else {
                  rotatedCGImage = cgImage;
                }

                // Erase stupid TIFF stuff
                [imageMetadata removeObjectForKey:(NSString *)kCGImagePropertyTIFFDictionary];

                // Create destination thing
                NSMutableData *rotatedImageData = [NSMutableData data];
                CGImageDestinationRef destination = CGImageDestinationCreateWithData((CFMutableDataRef)rotatedImageData, CGImageSourceGetType(source), 1, NULL);
                CFRelease(source);
                // add the image to the destination, reattaching metadata
                CGImageDestinationAddImage(destination, rotatedCGImage, (CFDictionaryRef) imageMetadata);
                // And write
                CGImageDestinationFinalize(destination);
                CFRelease(destination);

                [self saveImage:rotatedImageData target:captureTarget metadata:imageMetadata success:successCallback error:errorCallback];

                CGImageRelease(rotatedCGImage);
            }
            else {
                errorCallback(@[error.description]);
            }
        }];
      #endif
    });
}

RCT_EXPORT_METHOD(saveImageToDisk:(NSString *)uri
                  targetPath:(NSString *)targetPath
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  NSURLRequest *request = [RCTConvert NSURLRequest:uri];
  [self.bridge.imageLoader loadImageWithURLRequest:request
                                    callback:^(NSError *loadError, UIImage *loadedImage) {
    if (loadError) {
      reject(@"failed_to_load_image_from_uri", @"Failed to load image from uri", loadError);
      return;
    }

    NSData *imageData = UIImageJPEGRepresentation(loadedImage, 1.0);
    [imageData writeToFile:targetPath atomically:YES];

    resolve(@(true));
  }];
}

- (AVCaptureWhiteBalanceGains)normalizedGains:(AVCaptureWhiteBalanceGains)gains
{
    AVCaptureWhiteBalanceGains g = gains;

    g.redGain = MAX( 1.0, g.redGain );
    g.greenGain = MAX( 1.0, g.greenGain );
    g.blueGain = MAX( 1.0, g.blueGain );

    g.redGain = MIN( self.videoCaptureDevice.maxWhiteBalanceGain, g.redGain );
    g.greenGain = MIN( self.videoCaptureDevice.maxWhiteBalanceGain, g.greenGain );
    g.blueGain = MIN( self.videoCaptureDevice.maxWhiteBalanceGain, g.blueGain );

    return g;
}

- (void)saveImage:(NSData*)imageData target:(NSInteger)target metadata:(NSDictionary *)metadata success:(RCTResponseSenderBlock)successCallback error:(RCTResponseSenderBlock)errorCallback {

    if (target == RCTCameraCaptureTargetMemory) {
        NSString* base64encodedImage =[imageData base64EncodedStringWithOptions:0];
        successCallback(@[base64encodedImage]);
        return;
    }

    else if (target == RCTCameraCaptureTargetDisk) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths firstObject];

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *fullPath = [[documentsDirectory stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] stringByAppendingPathExtension:@"jpg"];

        [fileManager createFileAtPath:fullPath contents:imageData attributes:nil];

        successCallback(@[fullPath]);
        return;
    }

    else if (target == RCTCameraCaptureTargetCameraRoll) {
        [[[ALAssetsLibrary alloc] init] writeImageDataToSavedPhotosAlbum:imageData metadata:metadata completionBlock:^(NSURL* url, NSError* error) {
            if (error == nil) {
                successCallback(@[[url absoluteString]]);
            }
            else {
                errorCallback(@[error.description]);
            }
        }];
        return;
    }

    else if (target == RCTCameraCaptureTargetTemp) {
        NSString *fileName = [[NSProcessInfo processInfo] globallyUniqueString];
        NSString *fullPath = [NSString stringWithFormat:@"%@%@.jpg", NSTemporaryDirectory(), fileName];

        // TODO: check if image successfully stored
        [imageData writeToFile:fullPath atomically:YES];
        successCallback(@[fullPath]);

        // NSError* error;
        // [imageData writeToFile:fullPath atomically:YES error:&error];

        // if(error != nil) {
        //     errorCallback(@[error.description]);
        // } else {
        //     successCallback(@[fullPath])
        // }
    }
}

- (CGImageRef)newCGImageRotatedByAngle:(CGImageRef)imgRef angle:(CGFloat)angle
{
    CGFloat angleInRadians = angle * (M_PI / 180);
    CGFloat width = CGImageGetWidth(imgRef);
    CGFloat height = CGImageGetHeight(imgRef);

    CGRect imgRect = CGRectMake(0, 0, width, height);
    CGAffineTransform transform = CGAffineTransformMakeRotation(angleInRadians);
    CGRect rotatedRect = CGRectApplyAffineTransform(imgRect, transform);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bmContext = CGBitmapContextCreate(NULL, rotatedRect.size.width, rotatedRect.size.height, 8, 0, colorSpace, (CGBitmapInfo) kCGImageAlphaPremultipliedFirst);

    // if (self.mirrorImage) {
    //     CGAffineTransform transform = CGAffineTransformMakeTranslation(rotatedRect.size.width, 0.0);
    //     transform = CGAffineTransformScale(transform, -1.0, 1.0);
    //     CGContextConcatCTM(bmContext, transform);
    // }

    CGContextSetAllowsAntialiasing(bmContext, TRUE);
    CGContextSetInterpolationQuality(bmContext, kCGInterpolationNone);

    CGColorSpaceRelease(colorSpace);

    CGContextTranslateCTM(bmContext, (rotatedRect.size.width/2), (rotatedRect.size.height/2));
    CGContextRotateCTM(bmContext, angleInRadians);
    CGContextTranslateCTM(bmContext, -(rotatedRect.size.width/2), -(rotatedRect.size.height/2));

    CGContextDrawImage(bmContext, CGRectMake((rotatedRect.size.width-width)/2.0f, (rotatedRect.size.height-height)/2.0f, width, height), imgRef);

    CGImageRef rotatedImage = CGBitmapContextCreateImage(bmContext);
    CFRelease(bmContext);
    return rotatedImage;
}

- (NSMutableArray *)getRuntimeBarCodeTypes
{
  NSMutableArray *runtimeBarcodeTypes = [[NSMutableArray alloc] initWithObjects:
  AVMetadataObjectTypeUPCECode,
  AVMetadataObjectTypeCode39Code,
  AVMetadataObjectTypeCode39Mod43Code,
  AVMetadataObjectTypeEAN13Code,
  AVMetadataObjectTypeEAN8Code,
  AVMetadataObjectTypeCode93Code,
  AVMetadataObjectTypeCode128Code,
  AVMetadataObjectTypePDF417Code,
  AVMetadataObjectTypeQRCode,
  AVMetadataObjectTypeAztecCode
  ,nil];

  if (&AVMetadataObjectTypeInterleaved2of5Code != NULL) {
      [runtimeBarcodeTypes addObject:AVMetadataObjectTypeInterleaved2of5Code];
  }

  if(&AVMetadataObjectTypeITF14Code != NULL){
      [runtimeBarcodeTypes addObject:AVMetadataObjectTypeITF14Code];
  }

  if(&AVMetadataObjectTypeDataMatrixCode != NULL){
      [runtimeBarcodeTypes addObject:AVMetadataObjectTypeDataMatrixCode];
  }

  return runtimeBarcodeTypes;
}


/**
 * Initializes a new {@link RTCAudioTrack} which satisfies specific constraints,
 * adds it to a specific {@link RTCMediaStream}, and reports success to a
 * specific callback. Implements the audio-specific counterpart of the
 * {@code getUserMedia()} algorithm.
 *
 * @param constraints The {@code MediaStreamConstraints} which the new
 * {@code RTCAudioTrack} instance is to satisfy.
 * @param successCallback The {@link NavigatorUserMediaSuccessCallback} to which
 * success is to be reported.
 * @param errorCallback The {@link NavigatorUserMediaErrorCallback} to which
 * failure is to be reported.
 * @param mediaStream The {@link RTCMediaStream} which is being initialized as
 * part of the execution of the {@code getUserMedia()} algorithm, to which a
 * new {@code RTCAudioTrack} is to be added, and which is to be reported to
 * {@code successCallback} upon success.
 */
- (void)getUserAudio:(NSDictionary *)constraints
     successCallback:(NavigatorUserMediaSuccessCallback)successCallback
       errorCallback:(NavigatorUserMediaErrorCallback)errorCallback
         mediaStream:(RTCMediaStream *)mediaStream {
  NSString *trackId = [[NSUUID UUID] UUIDString];
  RTCAudioTrack *audioTrack
    = [self.peerConnectionFactory audioTrackWithTrackId:trackId];

  [mediaStream addAudioTrack:audioTrack];

  successCallback(mediaStream);
}

// TODO: Use RCTConvert for constraints ...
RCT_EXPORT_METHOD(getUserMedia:(NSDictionary *)constraints
               resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
  // Initialize RTCMediaStream with a unique label in order to allow multiple
  // RTCMediaStream instances initialized by multiple getUserMedia calls to be
  // added to 1 RTCPeerConnection instance. As suggested by
  // https://www.w3.org/TR/mediacapture-streams/#mediastream to be a good
  // practice, use a UUID (conforming to RFC4122).
  NSString *mediaStreamId = [[NSUUID UUID] UUIDString];
  RTCMediaStream *mediaStream
    = [self.peerConnectionFactory mediaStreamWithStreamId:mediaStreamId];

  [self
    getUserMedia:constraints
    successCallback:^ (RTCMediaStream *mediaStream) {
      NSString *mediaStreamId = mediaStream.streamId;
      NSMutableArray *tracks = [NSMutableArray array];

      for (NSString *propertyName in @[ @"audioTracks", @"videoTracks" ]) {
        SEL sel = NSSelectorFromString(propertyName);
        for (RTCMediaStreamTrack *track in [mediaStream performSelector:sel]) {
          NSString *trackId = track.trackId;

          self.localTracks[trackId] = track;
          [tracks addObject:@{
                              @"enabled": @(track.isEnabled),
                              @"id": trackId,
                              @"kind": track.kind,
                              @"label": trackId,
                              @"readyState": @"live",
                              @"remote": @(NO)
                              }];
        }
      }
      self.localStreams[mediaStreamId] = mediaStream;
      resolve(@[ mediaStreamId, tracks ]);
    }
    errorCallback:^ (NSString *errorType, NSString *errorMessage) {
      reject(errorType, errorMessage, nil);
    }
    mediaStream:mediaStream];
}

/**
 * Initializes a new {@link RTCAudioTrack} or a new {@link RTCVideoTrack} which
 * satisfies specific constraints and adds it to a specific
 * {@link RTCMediaStream} if the specified {@code mediaStream} contains no track
 * of the respective media type and the specified {@code constraints} specify
 * that a track of the respective media type is required; otherwise, reports
 * success for the specified {@code mediaStream} to a specific
 * {@link NavigatorUserMediaSuccessCallback}. In other words, implements a media
 * type-specific iteration of or successfully concludes the
 * {@code getUserMedia()} algorithm. The method will be recursively invoked to
 * conclude the whole {@code getUserMedia()} algorithm either with (successful)
 * satisfaction of the specified {@code constraints} or with failure.
 *
 * @param constraints The {@code MediaStreamConstraints} which specifies the
 * requested media types and which the new {@code RTCAudioTrack} or
 * {@code RTCVideoTrack} instance is to satisfy.
 * @param successCallback The {@link NavigatorUserMediaSuccessCallback} to which
 * success is to be reported.
 * @param errorCallback The {@link NavigatorUserMediaErrorCallback} to which
 * failure is to be reported.
 * @param mediaStream The {@link RTCMediaStream} which is being initialized as
 * part of the execution of the {@code getUserMedia()} algorithm.
 */
- (void)getUserMedia:(NSDictionary *)constraints
     successCallback:(NavigatorUserMediaSuccessCallback)successCallback
       errorCallback:(NavigatorUserMediaErrorCallback)errorCallback
         mediaStream:(RTCMediaStream *)mediaStream {
  // If mediaStream contains no audioTracks and the constraints request such a
  // track, then run an iteration of the getUserMedia() algorithm to obtain
  // local audio content.
  if (mediaStream.audioTracks.count == 0) {
    // constraints.audio
    id audioConstraints = constraints[@"audio"];
    if (audioConstraints && [audioConstraints boolValue]) {
      [self requestAccessForMediaType:AVMediaTypeAudio
                          constraints:constraints
                      successCallback:successCallback
                        errorCallback:errorCallback
                          mediaStream:mediaStream];
      return;
    }
  }

  // If mediaStream contains no videoTracks and the constraints request such a
  // track, then run an iteration of the getUserMedia() algorithm to obtain
  // local video content.
  if (mediaStream.videoTracks.count == 0) {
    // constraints.video
    id videoConstraints = constraints[@"video"];
    if (videoConstraints) {
      BOOL requestAccessForVideo
        = [videoConstraints isKindOfClass:[NSNumber class]]
          ? [videoConstraints boolValue]
          : [videoConstraints isKindOfClass:[NSDictionary class]];

      if (requestAccessForVideo) {
        [self requestAccessForMediaType:AVMediaTypeVideo
                            constraints:constraints
                        successCallback:successCallback
                          errorCallback:errorCallback
                            mediaStream:mediaStream];
        return;
      }
    }
  }

  // There are audioTracks and/or videoTracks in mediaStream as requested by
  // constraints so the getUserMedia() is to conclude with success.
  successCallback(mediaStream);
}

/**
 * Initializes a new {@link RTCVideoTrack} which satisfies specific constraints,
 * adds it to a specific {@link RTCMediaStream}, and reports success to a
 * specific callback. Implements the video-specific counterpart of the
 * {@code getUserMedia()} algorithm.
 *
 * @param constraints The {@code MediaStreamConstraints} which the new
 * {@code RTCVideoTrack} instance is to satisfy.
 * @param successCallback The {@link NavigatorUserMediaSuccessCallback} to which
 * success is to be reported.
 * @param errorCallback The {@link NavigatorUserMediaErrorCallback} to which
 * failure is to be reported.
 * @param mediaStream The {@link RTCMediaStream} which is being initialized as
 * part of the execution of the {@code getUserMedia()} algorithm, to which a
 * new {@code RTCVideoTrack} is to be added, and which is to be reported to
 * {@code successCallback} upon success.
 */
- (void)getUserVideo:(NSDictionary *)constraints
     successCallback:(NavigatorUserMediaSuccessCallback)successCallback
       errorCallback:(NavigatorUserMediaErrorCallback)errorCallback
         mediaStream:(RTCMediaStream *)mediaStream {
  id videoConstraints = constraints[@"video"];
  AVCaptureDevice *videoDevice;
  if ([videoConstraints isKindOfClass:[NSDictionary class]]) {
    // constraints.video.optional
    id optionalVideoConstraints = videoConstraints[@"optional"];
    if (optionalVideoConstraints
        && [optionalVideoConstraints isKindOfClass:[NSArray class]]) {
      NSArray *options = optionalVideoConstraints;
      for (id item in options) {
        if ([item isKindOfClass:[NSDictionary class]]) {
          NSString *sourceId = ((NSDictionary *)item)[@"sourceId"];
          if (sourceId) {
            videoDevice = [AVCaptureDevice deviceWithUniqueID:sourceId];
            if (videoDevice) {
              break;
            }
          }
        }
      }
    }
    if (!videoDevice) {
      // constraints.video.facingMode
      //
      // https://www.w3.org/TR/mediacapture-streams/#def-constraint-facingMode
      id facingMode = videoConstraints[@"facingMode"];
      if (facingMode && [facingMode isKindOfClass:[NSString class]]) {
        AVCaptureDevicePosition position;
        if ([facingMode isEqualToString:@"environment"]) {
          position = AVCaptureDevicePositionBack;
        } else if ([facingMode isEqualToString:@"user"]) {
          position = AVCaptureDevicePositionFront;
        } else {
          // If the specified facingMode value is not supported, fall back to
          // the default video device.
          position = AVCaptureDevicePositionUnspecified;
        }
        if (AVCaptureDevicePositionUnspecified != position) {
          for (AVCaptureDevice *aVideoDevice in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
            if (aVideoDevice.position == position) {
              videoDevice = aVideoDevice;
              break;
            }
          }
        }
      }
    }
    if (!videoDevice) {
      videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
  }

  if (videoDevice) {
    // TODO: Actually use constraints...
    // RTCAVFoundationVideoSource *videoSource = [self.peerConnectionFactory avFoundationVideoSourceWithConstraints:[self defaultMediaStreamConstraints]];

            NSDictionary *mandatoryConstraints = [videoConstraints valueForKey:@"mandatory"];

            if (mandatoryConstraints &&
                [mandatoryConstraints objectForKey:@"minWidth"] &&
                [mandatoryConstraints objectForKey:@"minHeight"]) {

                NSString *minWidth = [[mandatoryConstraints valueForKey:@"minWidth"] stringValue];
                NSString *minHeight = [[mandatoryConstraints valueForKey:@"minHeight"] stringValue];

                mandatoryConstraints = @{
                                         @"minWidth": minWidth,
                                         @"minHeight": minHeight,
                                         };
            } else {
                mandatoryConstraints == nil;
            }

            RTCMediaConstraints *rtcMediaContraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatoryConstraints optionalConstraints:nil];

            videoSource = [self.peerConnectionFactory avFoundationVideoSourceWithConstraints:rtcMediaContraints];
    // FIXME The effort above to find a videoDevice value which satisfies the
    // specified constraints was pretty much wasted. Salvage facingMode for
    // starters because it is kind of a common and hence important feature on
    // a mobile device.
    switch (videoDevice.position) {
    case AVCaptureDevicePositionBack:
      if (videoSource.canUseBackCamera) {
        videoSource.useBackCamera = YES;
      }
      break;
    case AVCaptureDevicePositionFront:
      videoSource.useBackCamera = NO;
      break;
    }

    self.videoCaptureDevice = videoDevice;

    NSString *trackUUID = [[NSUUID UUID] UUIDString];
    RTCVideoTrack *videoTrack = [self.peerConnectionFactory videoTrackWithSource:videoSource trackId:trackUUID];
    [mediaStream addVideoTrack:videoTrack];


            self.videoCaptureSession = videoSource.captureSession;

            // setup output for still image
            stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
            [stillImageOutput setHighResolutionStillImageOutputEnabled:false];

            NSDictionary *outputSettings = @{ AVVideoCodecKey : AVVideoCodecJPEG};

            [stillImageOutput setOutputSettings:outputSettings];

            if ([self.videoCaptureSession canAddOutput:stillImageOutput])
            {
                [self.videoCaptureSession addOutput:stillImageOutput];

                [self setCaptureQualityAsync:3];

                successCallback(mediaStream);
                // TODO: error message
                //erroCallback();
            } else {
                            // TODO: error message
                            //erroCallback();
            }

            AVCaptureMetadataOutput *metadataOutput = [[AVCaptureMetadataOutput alloc] init];
            if ([self.videoCaptureSession canAddOutput:metadataOutput]) {
              [metadataOutput setMetadataObjectsDelegate:self queue:self.sessionQueue];
              [self.videoCaptureSession addOutput:metadataOutput];
              [metadataOutput setMetadataObjectTypes:[self getRuntimeBarCodeTypes]];
              self.metadataOutput = metadataOutput;
            } else {
                            // TODO: error message
                            //erroCallback();
            }
        } else {
    // According to step 6.2.3 of the getUserMedia() algorithm, if there is no
    // source, fail with a new OverconstrainedError.
    errorCallback(@"OverconstrainedError", /* errorMessage */ nil);
  }
}

RCT_EXPORT_METHOD(setCaptureQuality:(int)quality)
{
  NSString *preset = AVCaptureSessionPresetPhoto;
  switch(quality) {
    case 0:
      preset = AVCaptureSessionPresetLow;
      // NSLog(@"KingdamApp native : AVCaptureSessionPresetLow");
      break;
    case 1:
      // NSLog(@"KingdamApp native : AVCaptureSessionPresetMedium");
      preset = AVCaptureSessionPresetMedium;
      break;
    case 2:
      // NSLog(@"KingdamApp native : AVCaptureSessionPresetHigh");
      preset = AVCaptureSessionPresetHigh;
      break;
    case 3:
    default:
      // NSLog(@"KingdamApp native : AVCaptureSessionPresetPhoto");
      preset = AVCaptureSessionPresetPhoto;
      break;
  }

  [self.videoCaptureSession beginConfiguration];
  if ([self.videoCaptureSession canSetSessionPreset:preset]) {
    // NSLog(@"KingdamApp native : sessionPreset %@ : %d", preset, quality);
    [self.videoCaptureSession setSessionPreset:preset];

    [stillImageOutput setHighResolutionStillImageOutputEnabled:preset == AVCaptureSessionPresetPhoto];
  }
  [self.videoCaptureSession commitConfiguration];
}

RCT_EXPORT_METHOD(setCaptureQualityAsync:(int)quality)
{
  dispatch_async(self.sessionQueue, ^{
    CGFloat zoomFactor = self.videoCaptureDevice.videoZoomFactor;
    [self setCaptureQuality:quality];
    [self setZoom:zoomFactor]; // set factor back original
  });
}

RCT_EXPORT_METHOD(mediaStreamRelease:(nonnull NSString *)streamID)
{
  RTCMediaStream *stream = self.localStreams[streamID];
  if (stream) {
    for (RTCVideoTrack *track in stream.videoTracks) {
      [self.localTracks removeObjectForKey:track.trackId];
    }
    for (RTCAudioTrack *track in stream.audioTracks) {
      [self.localTracks removeObjectForKey:track.trackId];
    }
    [self.localStreams removeObjectForKey:streamID];
  }
}

RCT_EXPORT_METHOD(mediaStreamTrackGetSources:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  NSMutableArray *sources = [NSMutableArray array];
  NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];


      NSDictionary *resolutions =  [self maxCameraResolutions];

      NSArray *frontResolutions = [resolutions valueForKey:@"front"];
      NSArray *backResolutions = [resolutions valueForKey:@"back"];


  for (AVCaptureDevice *device in videoDevices) {

            NSString *facing = device.positionString;

            NSArray *res;

            if(facing == @"front") {
                res = frontResolutions;
            } else {
                res = backResolutions;
            }

            NSString *maxWidth = [res valueForKey:@"width"];
            NSString *maxHeight = [res valueForKey:@"height"];;


    [sources addObject:@{
                         @"facing": device.positionString,
                         @"id": device.uniqueID,
                         @"label": device.localizedName,
                         @"kind": @"video",
                                                      @"maxWidth": maxWidth,
                                                      @"maxHeight": maxHeight,
                         }];
  }
  NSArray *audioDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
  for (AVCaptureDevice *device in audioDevices) {
    [sources addObject:@{
                         @"facing": @"",
                         @"id": device.uniqueID,
                         @"label": device.localizedName,
                         @"kind": @"audio",
                         }];
  }
  resolve(@[sources]);
}

- (NSString*) deviceName {
    struct utsname systemInfo;
    uname(&systemInfo);

    return [NSString stringWithCString:systemInfo.machine
                              encoding:NSUTF8StringEncoding];
}

- (NSDictionary*) createResolutionDict: (NSNumber*) frontCamWidth
                        frontCamHeight: (NSNumber*) frontCamHeight
                          backCamWidth: (NSNumber*) backCamWidth
                         backCamHeight: (NSNumber*) backCamHeight{

    NSDictionary* frontCam = @{@"width":frontCamWidth,
                              @"height":frontCamHeight};

    NSDictionary* backCam = @{@"width":backCamWidth,
                             @"height":backCamHeight};

    return @{@"front":frontCam, @"back":backCam};
}

- (NSDictionary*) maxCameraResolutions {
    NSString* deviceModel = [self deviceName];
    NSDictionary* resolutions = nil;


    // iPhone 4S
    if ([deviceModel isEqualToString:@"iPhone4,1"]) {
        resolutions = [self createResolutionDict:@640 frontCamHeight:@480 backCamWidth:@3264 backCamHeight:@2448];
    }
    // iPhone 5/5C/5S/6/6/iPod 6
    else if ([deviceModel isEqualToString:@"iPhone5,1"]
             || [deviceModel isEqualToString:@"iPhone5,2"]
             || [deviceModel isEqualToString:@"iPhone5,3"]
             || [deviceModel isEqualToString:@"iPhone5,4"]
             || [deviceModel isEqualToString:@"iPhone6,1"]
             || [deviceModel isEqualToString:@"iPhone6,2"]
             || [deviceModel isEqualToString:@"iPhone7,1"]
             || [deviceModel isEqualToString:@"iPhone7,2"]
             || [deviceModel isEqualToString:@"iPod7,1"]) {
        resolutions = [self createResolutionDict:@1280 frontCamHeight:@960 backCamWidth:@3264 backCamHeight:@2448];
    }
    // iPhone 6S/6S
    else if ([deviceModel isEqualToString:@"iPhone8,1"]
             || [deviceModel isEqualToString:@"iPhone8,2"]) {
        resolutions = [self createResolutionDict:@1280 frontCamHeight:@960 backCamWidth:@4032 backCamHeight:@3024];
    }
    // iPad 2
    else if ([deviceModel isEqualToString:@"iPad2,1"]
             || [deviceModel isEqualToString:@"iPad2,2"]
             || [deviceModel isEqualToString:@"iPad2,3"]
             || [deviceModel isEqualToString:@"iPad2,4"]) {
        resolutions = [self createResolutionDict:@640 frontCamHeight:@480 backCamWidth:@1280 backCamHeight:@720];
    }
    // iPad 3
    else if ([deviceModel isEqualToString:@"iPad3,1"]
             || [deviceModel isEqualToString:@"iPad3,2"]
             || [deviceModel isEqualToString:@"iPad3,3"]) {
        resolutions = [self createResolutionDict:@640 frontCamHeight:@480 backCamWidth:@2592 backCamHeight:@1936];
    }
    // iPad 4/Air/Mini/Mini 2/Mini 3/iPod 5G
    else if ([deviceModel isEqualToString:@"iPad3,4"]
             || [deviceModel isEqualToString:@"iPad3,5"]
             || [deviceModel isEqualToString:@"iPad3,6"]
             || [deviceModel isEqualToString:@"iPad4,1"]
             || [deviceModel isEqualToString:@"iPad4,2"]
             || [deviceModel isEqualToString:@"iPad4,3"]
             || [deviceModel isEqualToString:@"iPad4,4"]
             || [deviceModel isEqualToString:@"iPad4,5"]
             || [deviceModel isEqualToString:@"iPad4,6"]
             || [deviceModel isEqualToString:@"iPad4,7"]
             || [deviceModel isEqualToString:@"iPad4,8"]
             || [deviceModel isEqualToString:@"iPod5,1"]) {
        resolutions = [self createResolutionDict:@1280 frontCamHeight:@960 backCamWidth:@2592 backCamHeight:@1936];
    }
    // iPad Air 2/Mini 4/Pro
    else if ([deviceModel isEqualToString:@"iPad5,3"]
             || [deviceModel isEqualToString:@"iPad5,4"]) {
        resolutions = [self createResolutionDict:@1280 frontCamHeight:@960 backCamWidth:@3264 backCamHeight:@2448];
    }

    if(resolutions == nil) {
        // TODO: this is a fallback for deviced which are not listed (i.e. newer iPhones/iPads
        resolutions = [self createResolutionDict:@640 frontCamHeight:@480 backCamWidth:@1280 backCamHeight:@720];
    }

    return resolutions;
}

- (NSDictionary*) resStringToDictionary: (NSString*) resString {

    NSArray *resStringArray = [resString componentsSeparatedByString:@","];

    int n = [resStringArray count];
    NSMutableArray *resolutions = [NSMutableArray arrayWithCapacity:n];
    for (int i = 0; i < n; i) {
        NSString *resStr = resStringArray[i];
        NSArray *res = [resStr componentsSeparatedByString:@"x"];
        NSDictionary *resDict = @{@"width": res[0], @"height": res[1]};
        resolutions[i] = resDict;
    }

    return resolutions;
}


RCT_EXPORT_METHOD(mediaStreamTrackRelease:(nonnull NSString *)streamID : (nonnull NSString *)trackID)
{
  // what's different to mediaStreamTrackStop? only call mediaStream explicitly?
  RTCMediaStream *mediaStream = self.localStreams[streamID];
  RTCMediaStreamTrack *track = self.localTracks[trackID];
  if (mediaStream && track) {
    track.isEnabled = NO;
    // FIXME this is called when track is removed from the MediaStream,
    // but it doesn't mean it can not be added back using MediaStream.addTrack
    [self.localTracks removeObjectForKey:trackID];
    if ([track.kind isEqualToString:@"audio"]) {
      [mediaStream removeAudioTrack:(RTCAudioTrack *)track];
    } else if([track.kind isEqualToString:@"video"]) {
      [mediaStream removeVideoTrack:(RTCVideoTrack *)track];
    }
  }
}

RCT_EXPORT_METHOD(mediaStreamTrackSetEnabled:(nonnull NSString *)trackID : (BOOL)enabled)
{
  RTCMediaStreamTrack *track = self.localTracks[trackID];
  if (track && track.isEnabled != enabled) {
    track.isEnabled = enabled;
  }
}

RCT_EXPORT_METHOD(mediaStreamTrackSwitchCamera:(nonnull NSString *)trackID)
{
  RTCMediaStreamTrack *track = self.localTracks[trackID];
  if (track) {
    RTCVideoTrack *videoTrack = (RTCVideoTrack *)track;
    RTCVideoSource *source = videoTrack.source;
    if ([source isKindOfClass:[RTCAVFoundationVideoSource class]]) {
      RTCAVFoundationVideoSource *avSource = (RTCAVFoundationVideoSource *)source;
      avSource.useBackCamera = !avSource.useBackCamera;
    }
  }
}

RCT_EXPORT_METHOD(mediaStreamTrackStop:(nonnull NSString *)trackID)
{
  RTCMediaStreamTrack *track = self.localTracks[trackID];
  if (track) {
    track.isEnabled = NO;
    [self.localTracks removeObjectForKey:trackID];
  }
}

/**
 * Obtains local media content of a specific type. Requests access for the
 * specified {@code mediaType} if necessary. In other words, implements a media
 * type-specific iteration of the {@code getUserMedia()} algorithm.
 *
 * @param mediaType Either {@link AVMediaTypAudio} or {@link AVMediaTypeVideo}
 * which specifies the type of the local media content to obtain.
 * @param constraints The {@code MediaStreamConstraints} which are to be
 * satisfied by the obtained local media content.
 * @param successCallback The {@link NavigatorUserMediaSuccessCallback} to which
 * success is to be reported.
 * @param errorCallback The {@link NavigatorUserMediaErrorCallback} to which
 * failure is to be reported.
 * @param mediaStream The {@link RTCMediaStream} which is to collect the
 * obtained local media content of the specified {@code mediaType}.
 */
- (void)requestAccessForMediaType:(NSString *)mediaType
                      constraints:(NSDictionary *)constraints
                  successCallback:(NavigatorUserMediaSuccessCallback)successCallback
                    errorCallback:(NavigatorUserMediaErrorCallback)errorCallback
                      mediaStream:(RTCMediaStream *)mediaStream {
  // According to step 6.2.1 of the getUserMedia() algorithm, if there is no
  // source, fail "with a new DOMException object whose name attribute has the
  // value NotFoundError."
  // XXX The following approach does not work for audio in Simulator. That is
  // because audio capture is done using AVAudioSession which does not use
  // AVCaptureDevice there. Anyway, Simulator will not (visually) request access
  // for audio.
  if (mediaType == AVMediaTypeVideo
      && [AVCaptureDevice devicesWithMediaType:mediaType].count == 0) {
    // Since successCallback and errorCallback are asynchronously invoked
    // elsewhere, make sure that the invocation here is consistent.
    dispatch_async(dispatch_get_main_queue(), ^ {
      errorCallback(@"DOMException", @"NotFoundError");
    });
    return;
  }

  [AVCaptureDevice
    requestAccessForMediaType:mediaType
    completionHandler:^ (BOOL granted) {
      dispatch_async(dispatch_get_main_queue(), ^ {
        if (granted) {
          NavigatorUserMediaSuccessCallback scb
            = ^ (RTCMediaStream *mediaStream) {
              [self getUserMedia:constraints
                 successCallback:successCallback
                   errorCallback:errorCallback
                     mediaStream:mediaStream];
            };

          if (mediaType == AVMediaTypeAudio) {
            [self getUserAudio:constraints
               successCallback:scb
                 errorCallback:errorCallback
                   mediaStream:mediaStream];
          } else if (mediaType == AVMediaTypeVideo) {
            [self getUserVideo:constraints
               successCallback:scb
                 errorCallback:errorCallback
                   mediaStream:mediaStream];
          }
        } else {
          // According to step 10 Permission Failure of the getUserMedia()
          // algorithm, if the user has denied permission, fail "with a new
          // DOMException object whose name attribute has the value
          // NotAllowedError."
          errorCallback(@"DOMException", @"NotAllowedError");
        }
      });
    }];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
  if (![self isBarcodeScannerEnabled]) {
    return;
  }

  for (AVMetadataMachineReadableCodeObject *metadata in metadataObjects) {

    // Transform the meta-data coordinates to screen coords
    // AVMetadataMachineReadableCodeObject *transformed = (AVMetadataMachineReadableCodeObject *)[_previewLayer transformedMetadataObjectForMetadataObject:metadata];

    NSDictionary *event = @{
      @"type": metadata.type,
      @"data": metadata.stringValue
      /*@"bounds": @{
        @"origin": @{
          @"x": [NSString stringWithFormat:@"%f", transformed.bounds.origin.x],
          @"y": [NSString stringWithFormat:@"%f", transformed.bounds.origin.y]
        },
        @"size": @{
          @"height": [NSString stringWithFormat:@"%f", transformed.bounds.size.height],
          @"width": [NSString stringWithFormat:@"%f", transformed.bounds.size.width],
        }
      }*/
    };

    // NSLog(@"KingdamApp:Native:barcode %@", metadata.type);
    [self.bridge.eventDispatcher sendAppEventWithName:@"CameraBarCodeRead" body:event];

  }
}

@end

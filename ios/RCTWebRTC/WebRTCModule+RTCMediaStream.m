//
//  WebRTCModuleRTCMediaStream.m
//
//  Created by one on 2015/9/24.
//  Copyright © 2015 One. All rights reserved.
//

#import <objc/runtime.h>
#import <sys/utsname.h>

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
    NSError *error = nil;
    // TODO use selected camera, should refer to self.something...
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([device lockForConfiguration:&error]) {
        // device.videoZoomFactor = zoomFactor;
        [device rampToVideoZoomFactor:zoomFactor withRate:10.0];
        [device unlockForConfiguration];
    } else {
        NSLog(@"error: %@", error);
    }
}

RCT_EXPORT_METHOD(setExposure:(CGFloat)exposure) {
    if (isnan(exposure)) {
        return;
    }
    NSError *error = nil;
    // TODO use selected camera, should refer to self.something...
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([device lockForConfiguration:&error]) {
        [device setExposureTargetBias:exposure completionHandler:nil];
        [device unlockForConfiguration];
    } else {
        NSLog(@"error: %@", error);
    }
}

RCT_EXPORT_METHOD(setColorTemperature:(CGFloat)temperature) {
    if (isnan(temperature)) {
        return;
    }
    NSError *error = nil;
    // TODO use selected camera, should refer to self.something...
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([device lockForConfiguration:&error]) {
      AVCaptureWhiteBalanceTemperatureAndTintValues gains = {
          .temperature = temperature,
          .tint = 0,
      };

      AVCaptureWhiteBalanceGains normalizedGains = [self normalizedGains:[device deviceWhiteBalanceGainsForTemperatureAndTintValues:gains]];
      [device setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:normalizedGains completionHandler:nil];
      [device unlockForConfiguration];
    } else {
        NSLog(@"error: %@", error);
    }
}

RCT_EXPORT_METHOD(resetColorTemperature) {
    NSError *error = nil;
    // TODO use selected camera, should refer to self.something...
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([device lockForConfiguration:&error]) {
      device.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
      [device unlockForConfiguration];
    } else {
        NSLog(@"error: %@", error);
    }
}

RCT_EXPORT_METHOD(takePicture:(NSDictionary *)options
                  successCallback:(RCTResponseSenderBlock)successCallback
                  errorCallback:(RCTResponseSenderBlock)errorCallback) {

    NSInteger captureTarget = [[options valueForKey:@"captureTarget"] intValue];
    NSInteger maxSize = [[options valueForKey:@"maxSize"] intValue];
    CGFloat jpegQuality = [[options valueForKey:@"maxJpegQuality"] floatValue];


    if(jpegQuality < 0) {
        jpegQuality = 0;
    } else if(jpegQuality > 1) {
        jpegQuality = 1;
    }

    [stillImageOutput captureStillImageAsynchronouslyFromConnection:[stillImageOutput connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {

        if (imageDataSampleBuffer) {
            NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];

            // Create image source
            CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)imageData, NULL);
            // Get all the metadata in the image
            NSMutableDictionary *imageMetadata = [(NSDictionary *) CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) mutableCopy];

            // Create cgimage
            CGImageRef CGImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);

            // Resize cgimage
            CGImage = [self resizeCGImage:CGImage maxSize:maxSize];

            // Rotate it
            CGImageRef rotatedCGImage;

            // Get metadata orientation
            int metadataOrientation = [[imageMetadata objectForKey:(NSString *)kCGImagePropertyOrientation] intValue];

            if (metadataOrientation == 6) {
                rotatedCGImage = [self newCGImageRotatedByAngle:CGImage angle:270];
            } else if (metadataOrientation == 1) {
                rotatedCGImage = [self newCGImageRotatedByAngle:CGImage angle:0];
            } else if (metadataOrientation == 3) {
                rotatedCGImage = [self newCGImageRotatedByAngle:CGImage angle:180];
            } else {
                rotatedCGImage = [self newCGImageRotatedByAngle:CGImage angle:0];
            }

            CGImageRelease(CGImage);

            // Erase metadata orientation
            [imageMetadata removeObjectForKey:(NSString *)kCGImagePropertyOrientation];
            // Erase stupid TIFF stuff
            [imageMetadata removeObjectForKey:(NSString *)kCGImagePropertyTIFFDictionary];


            // Create destination thing
            NSMutableData *rotatedImageData = [NSMutableData data];
            CGImageDestinationRef destinationRef = CGImageDestinationCreateWithData((CFMutableDataRef)rotatedImageData, CGImageSourceGetType(source), 1, NULL);
            CFRelease(source);

            // Set compression
            NSDictionary *properties = @{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @(jpegQuality)};
            CGImageDestinationSetProperties(destinationRef,
                                            (__bridge CFDictionaryRef)properties);

            // Add the image to the destination, reattaching metadata
            CGImageDestinationAddImage(destinationRef, rotatedCGImage, (CFDictionaryRef) imageMetadata);

            // And write
            CGImageDestinationFinalize(destinationRef);
            CFRelease(destinationRef);


            [self saveImage:rotatedImageData target:captureTarget metadata:imageMetadata success:successCallback error:errorCallback];
        }
        else {
            errorCallback(@[error.description]);
        }
    }];
}

- (AVCaptureWhiteBalanceGains)normalizedGains:(AVCaptureWhiteBalanceGains)gains
{
    // TODO use selected camera, should refer to self.something...
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];

    AVCaptureWhiteBalanceGains g = gains;

    g.redGain = MAX( 1.0, g.redGain );
    g.greenGain = MAX( 1.0, g.greenGain );
    g.blueGain = MAX( 1.0, g.blueGain );

    g.redGain = MIN( device.maxWhiteBalanceGain, g.redGain );
    g.greenGain = MIN( device.maxWhiteBalanceGain, g.greenGain );
    g.blueGain = MIN( device.maxWhiteBalanceGain, g.blueGain );

    return g;
}

- (CGImageRef)resizeCGImage:(CGImageRef)image maxSize:(int)maxSize {

    size_t originalWidth = CGImageGetWidth(image);
    size_t originalHeight = CGImageGetHeight(image);

    // only resize if image larger than maxSize
    if(originalWidth <= maxSize && originalHeight <= maxSize) {
        return image;
    }

    size_t newWidth = originalWidth;
    size_t newHeight = originalHeight;

    // first check if we need to scale width
    if (originalWidth > maxSize) {
        //scale width to fit
        newWidth = maxSize;
        //scale height to maintain aspect ratio
        newHeight = (newWidth * originalHeight) / originalWidth;
    }

    // then check if we need to scale even with the new height
    if (newHeight > maxSize) {
        //scale height to fit instead
        newHeight = maxSize;
        //scale width to maintain aspect ratio
        newWidth = (newHeight * originalWidth) / originalHeight;
    }

    // create context, keeping original image properties
    CGColorSpaceRef colorspace = CGImageGetColorSpace(image);
    CGContextRef context = CGBitmapContextCreate(NULL, newWidth, newHeight,
                                                 CGImageGetBitsPerComponent(image),
                                                 CGImageGetBytesPerRow(image),
                                                 colorspace,
                                                 CGImageGetAlphaInfo(image));
    CGColorSpaceRelease(colorspace);

    if(context == NULL)
        return image;



    // draw image to context (resizing it)
    CGContextDrawImage(context, CGRectMake(0, 0, newWidth, newHeight), image);
    // extract resulting image from context
    CGImageRef imgRef = CGBitmapContextCreateImage(context);
    CGContextRelease(context);

    return imgRef;
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
               successCallback:(RCTResponseSenderBlock)successCallback
                 errorCallback:(RCTResponseSenderBlock)errorCallback) {
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
      successCallback(@[ mediaStreamId, tracks ]);
    }
    errorCallback:^ (NSString *errorType, NSString *errorMessage) {
      errorCallback(@[ errorType, errorMessage ]);
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

            RTCAVFoundationVideoSource *videoSource = [self.peerConnectionFactory avFoundationVideoSourceWithConstraints:rtcMediaContraints];
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

    self.videoCaptureDeviceInput = videoDevice;

    NSString *trackUUID = [[NSUUID UUID] UUIDString];
    RTCVideoTrack *videoTrack = [self.peerConnectionFactory videoTrackWithSource:videoSource trackId:trackUUID];
    [mediaStream addVideoTrack:videoTrack];


            AVCaptureSession *captureSession = videoSource.captureSession;

            // setup output for still image
            stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
            [stillImageOutput setHighResolutionStillImageOutputEnabled:true];

            NSDictionary *outputSettings = @{ AVVideoCodecKey : AVVideoCodecJPEG};

            [stillImageOutput setOutputSettings:outputSettings];

            if ([captureSession canAddOutput:stillImageOutput])
            {
                [captureSession addOutput:stillImageOutput];

                successCallback(mediaStream);
                // TODO: error message
                //erroCallback();
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

RCT_EXPORT_METHOD(mediaStreamTrackGetSources:(RCTResponseSenderBlock)callback) {
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
  callback(@[sources]);
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

@end

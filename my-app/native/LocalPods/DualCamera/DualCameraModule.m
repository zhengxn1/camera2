#import "DualCameraModule.h"
#import "DualCameraSessionManager.h"
#import "DualCameraEventEmitter.h"
#import <AVFoundation/AVFoundation.h>
#import <AVFAudio/AVFAudio.h>

@interface DualCameraModule ()
@property (nonatomic, strong) AVAudioRecorder *audioRecorder;
@property (nonatomic, strong) NSTimer *audioMeteringTimer;
@property (nonatomic, assign) BOOL isAudioMetering;
@end

@implementation DualCameraModule

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup {
  return YES;
}

RCT_EXPORT_METHOD(startSession) {
  [[DualCameraSessionManager shared] startSession];
}

RCT_EXPORT_METHOD(stopSession) {
  [[DualCameraSessionManager shared] stopSession];
}

RCT_EXPORT_METHOD(takePhoto) {
  [[DualCameraSessionManager shared] takePhoto];
}

RCT_EXPORT_METHOD(startRecording) {
  [[DualCameraSessionManager shared] startRecording];
}

RCT_EXPORT_METHOD(stopRecording) {
  [[DualCameraSessionManager shared] stopRecording];
}

RCT_EXPORT_METHOD(startAudioMetering) {
  if (self.isAudioMetering) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self setupAudioRecorder];
  });
}

RCT_EXPORT_METHOD(stopAudioMetering) {
  if (!self.isAudioMetering) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self teardownAudioRecorder];
  });
}

#pragma mark - Audio Metering

- (void)setupAudioRecorder {
  if (self.audioRecorder) return;

  NSURL *url = [NSURL fileURLWithPath:@"/dev/null"];
  NSDictionary *settings = @{
    AVFormatIDKey: @(kAudioFormatAppleLossless),
    AVSampleRateKey: @44100.0,
    AVNumberOfChannelsKey: @1,
    AVEncoderAudioQualityKey: @(AVAudioQualityMin)
  };

  NSError *err = nil;
  self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&err];
  if (err || !self.audioRecorder) {
    NSLog(@"[DualCamera] Audio recorder init failed: %@", err.localizedDescription);
    return;
  }

  NSError *sessionErr = nil;
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayAndRecord
           withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth
                 error:&sessionErr];
  [session setActive:YES error:&sessionErr];
  if (sessionErr) {
    NSLog(@"[DualCamera] Audio session activation failed: %@", sessionErr.localizedDescription);
  }

  self.audioRecorder.meteringEnabled = YES;
  [self.audioRecorder prepareToRecord];
  [self.audioRecorder record];

  self.isAudioMetering = YES;

  self.audioMeteringTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                             target:self
                                                           selector:@selector(updateAudioMeters)
                                                           userInfo:nil
                                                            repeats:YES];
}

- (void)updateAudioMeters {
  if (!self.audioRecorder.isRecording) return;

  [self.audioRecorder updateMeters];
  float averagePower = [self.audioRecorder averagePowerForChannel:0];
  float peakPower = [self.audioRecorder peakPowerForChannel:0];

  // Convert dB to 0-1 linear scale (dB range: -160 to 0)
  float normalizedAverage = (averagePower + 60.0) / 60.0;
  float normalizedPeak = (peakPower + 60.0) / 60.0;
  normalizedAverage = MAX(0.0, MIN(1.0, normalizedAverage));
  normalizedPeak = MAX(0.0, MIN(1.0, normalizedPeak));

  [[DualCameraEventEmitter shared] sendAudioLevel:normalizedAverage peak:normalizedPeak];
}

- (void)teardownAudioRecorder {
  [self.audioMeteringTimer invalidate];
  self.audioMeteringTimer = nil;
  [self.audioRecorder stop];
  self.audioRecorder = nil;
  self.isAudioMetering = NO;

  NSError *deactErr = nil;
  [[AVAudioSession sharedInstance] setActive:NO
                                  withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                        error:&deactErr];
}

- (void)dealloc {
  [self teardownAudioRecorder];
}

@end

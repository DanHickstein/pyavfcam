// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy

#include <iostream>

#include "avf_impl.h"
#include "avf.h"
#include "camera_frame.h"
#include "util.h"

@interface ACWeakProxy : NSProxy {
    id _object;
}

@property(assign) id object;

- (id)initWithObject:(id)object;

@end

@implementation ACWeakProxy

@synthesize object = _object;

- (id)initWithObject:(id)object {
    // no init method in superclass
    _object = object;
    return self;
}

- (BOOL)isKindOfClass:(Class)aClass {
    return [super isKindOfClass:aClass] || [_object isKindOfClass:aClass];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation setTarget:_object];
    [invocation invoke];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    return [_object methodSignatureForSelector:sel];
}

@end

static dispatch_queue_t _backgroundQueue = nil;

@implementation AVCaptureDelegate

+ (void)initialize {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    _backgroundQueue = dispatch_queue_create(
        "pyavfcam.background",
        DISPATCH_QUEUE_SERIAL);
  });
}

// Keep the runloop alive
-(void)keepAlive:(NSTimer *)timer
{
//    std::cout << "keep alive cur " << CFRunLoopGetCurrent() << std::endl;
}

// Constructor delegate
-(void)createSession
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    ACWeakProxy * proxy = [[ACWeakProxy alloc] initWithObject:self];
    m_timer = [NSTimer scheduledTimerWithTimeInterval:1 
                                               target:proxy
                                             selector:@selector(keepAlive:)
                                             userInfo:nil repeats:YES];
    [proxy release];

    m_pDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (m_pDevice) {
        m_pSession = [[AVCaptureSession alloc] init];
        if (m_pSession) {
            NSError *error = nil;
            m_pVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:m_pDevice error:&error];
            if (m_pVideoInput)
                [m_pSession addInput:m_pVideoInput];
            if (m_instance->isSinkFileSet())
                m_pVideoFileOutput = [[AVCaptureMovieFileOutput alloc] init];
            if (m_pVideoFileOutput)
                [m_pSession addOutput:m_pVideoFileOutput];
            if (m_instance->isSinkImageSet())
                m_pStillImageOutput = [[AVCaptureStillImageOutput alloc] init];

            if (m_pStillImageOutput) {
                // If outputSettings is not set no iamge is returned
                NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
                NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
                NSDictionary* outputSettings = [NSDictionary dictionaryWithObject:value forKey:key];
                [m_pStillImageOutput setOutputSettings:outputSettings];

                [m_pSession addOutput:m_pStillImageOutput];
            }

            if (m_pVideoFileOutput) {
                // Set movie to 30fps by default
                AVCaptureConnection *videoConnection = [m_pVideoFileOutput connectionWithMediaType:AVMediaTypeVideo];
                if (videoConnection) {
                    if (videoConnection.isVideoMinFrameDurationSupported)
                        videoConnection.videoMinFrameDuration = CMTimeMake(1, 30);
                    if (videoConnection.isVideoMaxFrameDurationSupported)
                        videoConnection.videoMaxFrameDuration = CMTimeMake(1, 30);
                }
            }
        }
    }
    if (m_pSession) {
        m_pSession.sessionPreset = AVCaptureSessionPreset640x480;
        // Start the AV session
        AVCaptureSession* session = m_pSession;
        dispatch_sync(_backgroundQueue, ^{
                      [session startRunning];
        });
    }

    [pool drain];
}

- (void)stopRecording
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    if (m_pVideoFileOutput)
        [m_pVideoFileOutput stopRecording];

    // Note that some samples will be flushed in the backgrouns and the callback will know when the file is ready

    [pool drain];
}

- (void)startRecordingToOutputFileURL:(NSURL *)url
  withDuration:(float)duration
  withBlocking:(unsigned int)blocking
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    // Set the duration of the video, pretend fps is 600, be a nice sheep
    if (duration > 0)
        [m_pVideoFileOutput setMaxRecordedDuration:CMTimeMakeWithSeconds((unsigned int)duration, 600)];

    if (m_semFile) {
        dispatch_release(m_semFile);
        m_semFile = NULL;
    }
    if (blocking)
        m_semFile = dispatch_semaphore_create(0);

    // BUG: ref count of self is increased but unfortunately it seems it is not a weak reference, so later it is not reclaimed !!
    //  The workarond is to use a proxy to force it being used as a weak reference: http://stackoverflow.com/a/3618797/311567
    ACWeakProxy * proxy = [[ACWeakProxy alloc] initWithObject:self];
    // Start recordign the video and let me know when it is done
    [m_pVideoFileOutput startRecordingToOutputFileURL:url recordingDelegate:(AVCaptureDelegate *)proxy];
    [proxy release];

    if (m_semFile) {
        float wait = duration + blocking;
        int err;
        while ((err = dispatch_semaphore_wait(m_semFile, DISPATCH_TIME_NOW))) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, NO);
            wait -= 0.05;
            if (wait <= 0)
               break;
        }
        // Make sure recording stops
        if (m_pVideoFileOutput.recording)
            [m_pVideoFileOutput stopRecording];
        if (err != 0)
            std::cerr << "output not called in time " << wait << std::endl;
    }
    [pool release];
}

- (void)captureFrameWithBlocking:(unsigned int)blocking
  error:(NSError * *)error
  frameHandler:(void (^)(CameraFrame & frame))handle
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    AVCaptureConnection *videoConnection = nil;
    for (AVCaptureConnection *connection in m_pStillImageOutput.connections) {
        for (AVCaptureInputPort *port in [connection inputPorts]) {
            if ([[port mediaType] isEqual:AVMediaTypeVideo] ) {
                videoConnection = connection;
                break;
            }
        }
        if (videoConnection)
            break;
    }
    if (!videoConnection) {
        if (error) {
            NSMutableDictionary* details = [NSMutableDictionary dictionary];
            [details setValue:@"No AVCaptureConnection found for still image capture" forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"pyavfcam" code:100 userInfo:details];
        }
        [pool release];
        return;
    }

    __block dispatch_semaphore_t sem = NULL;
    __block NSError *_err = nil;
    if (blocking)
        sem = dispatch_semaphore_create(0);

    [m_pStillImageOutput captureStillImageAsynchronouslyFromConnection:videoConnection
                         completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error) {

            if (error) {
                _err = error;
                NSLog(@"err %@", error);
            } else {
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                CameraFrame frame(imageSampleBuffer);
                if (handle)
                    handle(frame);
                // Callback at the end
                m_instance->image_output(frame);
                if (sem)
                    dispatch_semaphore_signal(sem);

                [pool drain];
            }
    }];
    if (error)
        *error = _err;
    if (sem) {
        // This is blocking call so wait at most handful of seconds for the signal
        float wait = blocking;
        int err;
        while ((err = dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW))) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, YES);
            wait -= 0.05;
            if (wait <= 0)
                break;
        }
        dispatch_release(sem);
        sem = NULL;
    }

    [pool release];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
  didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
  fromConnection:(AVCaptureConnection *)connection
{
    if (!m_instance)
        return;

    CameraFrame frame(sampleBuffer);
    m_instance->video_output(frame);

}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
  didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
  fromConnections:(NSArray *)connections
  error:(NSError *)error
{
    if (m_semFile)
        dispatch_semaphore_signal(m_semFile);

    if (!m_instance)
        return;

    m_instance->file_output_done(error != NULL);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
  didStartRecordingToOutputFileAtURL:(NSURL *)outputFileURL
  fromConnections:(NSArray *)connections
{
//    std::cout << " recording started cur " << CFRunLoopGetCurrent() << std::endl;
}

- (id)init
{
    return [self initWithInstance:NULL];
}

- (id)initWithInstance:(CppAVFCam *)pInstance
{
    self = [super init];
    if(self) {
        m_semFile = nil;
        m_instance = pInstance;

        m_pSession = nil;
        m_pDevice = nil;
        m_pVideoInput = nil;
        m_pVideoFileOutput = nil;
        m_pStillImageOutput = nil;

        NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:AVCaptureSessionRuntimeErrorNotification
                            object:nil
                             queue:nil
                        usingBlock:^(NSNotification* notification) {
          NSLog(@"Capture session error: %@", notification.userInfo);
        }];

        [self createSession];

    }
    return self;
}

// Change the c++ instance I am delegated to
- (void)setInstance:(CppAVFCam *)pInstance
{
    m_instance = pInstance;
}

// Destructor delegate
-(void)deallocateSession
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    // no more timer source
    if (m_timer)
        [m_timer invalidate];
    
    AVCaptureSession* pSession = m_pSession;
    AVCaptureDevice * pDevice = m_pDevice;
    AVCaptureDeviceInput * pVideoInput = m_pVideoInput;
    AVCaptureMovieFileOutput * pVideoFileOutput = m_pVideoFileOutput;
    AVCaptureStillImageOutput * pStillImageOutput = m_pStillImageOutput;
    // Close the session in a background session
    dispatch_async(_backgroundQueue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        if (pSession) {
            // std::cout << "   pSession " << CFGetRetainCount((__bridge CFTypeRef)pSession) << std::endl;
            if (pSession.isRunning)
                [pSession stopRunning];
            [pSession release];
        }
        // BUG: I cannot release these safely because AVFoundation segfaults!
        
        // Release the rest
        if (pDevice) {
//             std::cout << "   pDevice " << CFGetRetainCount((__bridge CFTypeRef)pDevice) << std::endl;
//             [pDevice release];
        }
        if (pVideoInput) {
//             std::cout << "   pVideoInput " << CFGetRetainCount((__bridge CFTypeRef)pVideoInput) << std::endl;
//             [pVideoInput release];
        }
        if (pVideoFileOutput) {
//             std::cout << "   pVideoFileOutput " << CFGetRetainCount((__bridge CFTypeRef)pVideoFileOutput) << std::endl;
//             [pVideoFileOutput release];
        }
        if (pStillImageOutput) {
//             std::cout << "   pStillImageOutput " << CFGetRetainCount((__bridge CFTypeRef)pStillImageOutput) << std::endl;
//             [pStillImageOutput release];
        }
        [pool release];
    });
    m_pSession = NULL;
    m_pVideoInput = NULL;
    m_pVideoFileOutput = NULL;
    m_pStillImageOutput = NULL;
    m_pDevice = NULL;

    [pool release];
}

// Destructor
-(void)dealloc
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [self deallocateSession];

    [pool release];

    [super dealloc];
}

@end

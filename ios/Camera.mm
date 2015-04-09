#include "Camera.h"

static NSString* s_frameSize = AVCaptureSessionPreset640x480;

extern App* g_appInst;

struct CameraFrame
{
	unsigned char* data;
	int width;
	int height;
	int bytesPerRow;
	
	bool IsValid()
	{
		return (data != nullptr);
	};
	
	void Free()
	{
		if(data)
		{
			free(data);
			data = nullptr;
		}
	};
};

@interface CameraiOS : NSObject<AVCaptureVideoDataOutputSampleBufferDelegate>

@property (strong) AVCaptureSession* session;
@property (strong) AVCaptureDevice* device;
@property (atomic) BOOL	frameLock;
@property (nonatomic) CameraFrame frame;

-(bool)Initialize;

-(bool)Start;
-(void)Stop;
-(void)SetFocusPoint:(CGPoint)focusPoint;

@end

@implementation CameraiOS

@synthesize session = m_session;
@synthesize device = m_device;
@synthesize frameLock = m_frameLock;
@synthesize frame = m_frame;

-(bool)Initialize
{
	NSError *error = nil;
	m_session = [[AVCaptureSession alloc] init];
	m_session.sessionPreset = s_frameSize;
	
	m_device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	[self SetFocusPoint:CGPointMake(0.5f, 0.5f)];
	
	AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:m_device error:&error];
	if(!input)
	{
		return false;
	}
	
	if(!input || ![m_session canAddInput:input])
	{
		LOG_ERROR("Cannot add AVCaptureDeviceInput to AVCaptureSession");
		if(error)
			LOG_ERROR("%s", [error localizedDescription].UTF8String);
		return false;
	}
	[m_session addInput:input];
	
	AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
	if(!output || ![m_session canAddOutput:output])
	{
		LOG_ERROR("Cannot add AVCaptureVideoDataOutput to AVCaptureSession");
		return false;
	}
	
	[m_session addOutput:output];
	
	output.videoSettings = @{ (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
	
	dispatch_queue_t queue = dispatch_queue_create("CameraQueue", NULL);
	[output setSampleBufferDelegate:self queue:queue];
	dispatch_release(queue);
	
	m_frameLock = NO;
	
	return true;
}

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
	// While frame lock is acquired new frames should be dropped.
	if(!m_frameLock)
	{
		[self UpdateVideoOrientationForConnection:connection];
		
		m_frame.Free();
		
		CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
		CVPixelBufferLockBaseAddress(imageBuffer, 0);
		
		void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
		
		m_frame.bytesPerRow = (unsigned int)CVPixelBufferGetBytesPerRow(imageBuffer);
		m_frame.width = (unsigned int)CVPixelBufferGetWidth(imageBuffer);
		m_frame.height = (unsigned int)CVPixelBufferGetHeight(imageBuffer);
		
		int pixelsNum = m_frame.width * m_frame.height * 4;
		m_frame.data = (unsigned char*)malloc(pixelsNum);
		memcpy(m_frame.data, baseAddress, pixelsNum);
		
		CVPixelBufferUnlockBaseAddress(imageBuffer,0);

		m_frameLock = true;
	}
}

-(void)UpdateVideoOrientationForConnection:(AVCaptureConnection*)connection
{
	InterfaceOrientation orientation = g_appInst->GetOrientation();
	AVCaptureVideoOrientation avOrientation = AVCaptureVideoOrientationLandscapeRight;
	switch(orientation)
	{
		case InterfaceOrientation_Portrait:
			avOrientation = AVCaptureVideoOrientationPortrait;
			break;
		case InterfaceOrientation_UpsideDown:
			avOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
			break;
		case InterfaceOrientation_LandscapeLeft:
			avOrientation = AVCaptureVideoOrientationLandscapeLeft;
			break;
		case InterfaceOrientation_LandscapeRight:
			avOrientation = AVCaptureVideoOrientationLandscapeRight;
			break;
		default:
			break;
	}
	[connection setVideoOrientation:avOrientation];
}

-(bool)Start
{
	[m_session startRunning];
	return true;
}

-(void)Stop
{
	[m_session stopRunning];
}

-(CGPoint)ConvertFocusPointToOrientation:(CGPoint)focusPoint
{
	CGPoint point;
	InterfaceOrientation orientation = g_appInst->GetOrientation();
	switch(orientation)
	{
		case InterfaceOrientation_Portrait:
			point = CGPointMake(focusPoint.y, focusPoint.x);
			break;
		case InterfaceOrientation_UpsideDown:
			point = CGPointMake(1.f - focusPoint.y, focusPoint.x);
			break;
		case InterfaceOrientation_LandscapeLeft:
			point = CGPointMake(1.f - focusPoint.x, 1.f - focusPoint.y);
			break;
		case InterfaceOrientation_LandscapeRight:
			point = focusPoint;
			break;
		default:
			point = focusPoint;			
			break;
	}
	return point;
}

-(void)SetFocusPoint:(CGPoint)focusPoint
{
	if(!m_device)
		return;
	
	if([m_device isFocusPointOfInterestSupported] && [m_device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
	{
		NSError* error;
		if([m_device lockForConfiguration:&error])
		{
			[m_device setFocusPointOfInterest:[self ConvertFocusPointToOrientation:focusPoint]];
			[m_device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
			[m_device unlockForConfiguration];
		}
		else
		{
			LOG_ERROR("Could not lock for configuration AVCaptureDevice. Error: %s", [error localizedDescription].UTF8String);
		}
	}
}

@end

class PCamera : public Camera
{
public:
	PCamera();
	virtual ~PCamera();
	
	bool	Initialize();
	void	Deinitialize();
	bool	Start();
	void	Stop();
	void	Update();
	void	TakePhoto(const char* path);
	void	SetFocusPoint(const Vector2& focusPoint);
	
	CameraiOS* m_camera;
};

PCamera::PCamera()
{
	
}

PCamera::~PCamera()
{
	m_camera.frame.Free();
}

bool PCamera::Initialize()
{
	m_takePhoto = false;
	
	m_camera = [[CameraiOS alloc] init];
	if(!m_camera || ![m_camera Initialize])
		return false;
	return true;
}

void PCamera::Deinitialize()
{
	
}

bool PCamera::Start()
{
	return [m_camera Start];
}

void PCamera::Stop()
{
	[m_camera Stop];
}

void PCamera::Update()
{
	if(m_camera.frameLock)
	{
		if(!m_camera.frame.IsValid())
		{
			m_camera.frameLock = false;
			return;
		}
		
		m_frameUpdateCB(m_callbackData, (void*)m_camera.frame.data, m_camera.frame.width, m_camera.frame.height, 4);
		
		if(m_takePhoto)
		{
			if(m_camera.session.running)
			{
				bool success = true;
				NSError* error;
				NSString* path = [NSString stringWithUTF8String:m_photoPath.c_str()];
				NSFileManager* fileManager = [NSFileManager defaultManager];
				if([fileManager fileExistsAtPath:path] == NO)
				{
					if(![fileManager createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error])
					{
						success = false;
						LOG_ERROR("Cannot create directory '%s'. Error: %s", m_photoPath.c_str(), [error localizedDescription].UTF8String);
					}
				}
				else
				{
					[fileManager removeItemAtPath:path error:&error];
					if(error)
					{
						success = false;
						LOG_ERROR("Cannot delete '%s'. Error: %s", m_photoPath.c_str(), [error localizedDescription].UTF8String);
					}
				}
				
				if(success)
				{
					// Switch from BGRA to RGBA.
					CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
					CGContextRef context = CGBitmapContextCreate(m_camera.frame.data, m_camera.frame.width, m_camera.frame.height, 8, m_camera.frame.bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst);
					CGImageRef quartzImage = CGBitmapContextCreateImage(context);
					CGContextRelease(context);
					CGColorSpaceRelease(colorSpace);
					UIImage* img = [UIImage imageWithCGImage:quartzImage];
					CGImageRelease(quartzImage);
					CGFloat jpegQuality = 0.9;
					
					success = [UIImageJPEGRepresentation(img, jpegQuality) writeToFile:[NSString stringWithUTF8String:m_photoPath.c_str()] options:0 error:&error];
					if(error)
						LOG_ERROR("[CAMERA] Cannot save image at: %s. Error: %s", m_photoPath.c_str(), [error localizedDescription].UTF8String);
					else
						LOG("[CAMERA] Saved image at: %s", m_photoPath.c_str());
				}
				m_photoSavedCB(m_callbackData, success);
			}
			else
			{
				m_photoSavedCB(m_callbackData, false);
			}
			m_takePhoto = false;
		}
		
		m_camera.frameLock = false;
	}
}

void PCamera::TakePhoto(const char* path)
{
	m_photoPath = path;
	m_takePhoto = true;
}

void PCamera::SetFocusPoint(const Vector2& focusPoint)
{
	[m_camera SetFocusPoint:CGPointMake(focusPoint.x, focusPoint.y)];
}

Camera* Camera::GetCamera(void* callbackData, FrameUpdateCallback frameUpdateCB, PhotoSavedCallback photoSavedCB)
{
	PCamera *camera = new PCamera;
	if(!camera || !camera->Initialize())
		return nullptr;
	
	camera->m_frameUpdateCB = frameUpdateCB;
	camera->m_photoSavedCB = photoSavedCB;
	camera->m_callbackData = callbackData;
	
	return camera;
}

Camera::~Camera()
{
	
}

Vector2 Camera::GetFrameSize()
{
	if(s_frameSize == AVCaptureSessionPreset640x480)
		return Vector2(640, 480);
	else if(s_frameSize == AVCaptureSessionPreset1280x720)
		return Vector2(1280, 720);
	else if(s_frameSize == AVCaptureSessionPreset1920x1080)
		return Vector2(1920, 1080);
	return Vector2(640, 480);
}

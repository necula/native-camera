#include "Camera.h"

static jclass		g_cameraClass = nullptr;
static jmethodID	g_initMethodId = nullptr;
static jmethodID	g_startPreviewMethodId = nullptr;
static jmethodID	g_stopPreviewMethodId = nullptr;
static jmethodID	g_takePhotoMethodId = nullptr;
static jmethodID	g_getCameraMethodId = nullptr;
static jmethodID	g_setCallbackDataMethodId = nullptr;
static jobject		g_cameraObject = nullptr;

static jint g_data[640*480];
static bool g_frameLock = false;

class PCamera : public Camera
{
public:
	
	enum PhotoSavedState
	{
		PhotoSaved_Failed,
		PhotoSaved_OK,
		PhotoSaved_Waiting
	};
	
	PCamera();
	virtual ~PCamera();
	
	bool	Initialize();
	void	Deinitialize();
	bool	Start();
	void	Stop();
	void	Update();
	void	TakePhoto(const char* path);
	void	SetFocusPoint(const Vector2& focusPoint);
	
	void	PhotoSavedCB(bool success);
	
	
private:
	bool	m_initialized;
	PhotoSavedState m_photoSavedState;
};

PCamera::PCamera()
{
	m_initialized = false;
	m_takePhoto = false;
	m_photoSavedState = PhotoSaved_Waiting;
}

PCamera::~PCamera()
{

}

bool PCamera::Initialize()
{
	JNIEnv* env = g_env;
	if(!env)
		return false;
	
	if(!g_cameraClass)
	{
		jclass tmp = FindJavaClass("com/Camera");
		g_cameraClass = (jclass)env->NewGlobalRef(tmp);
		if(!g_cameraClass)
		{
			LOG_ERROR("Could not find class 'com/Camera'.");
			return false;
		}
	}
	
	if(!g_getCameraMethodId)
	{
		g_getCameraMethodId = env->GetStaticMethodID(g_cameraClass, "getCamera", "()Lcom/Camera;");
		if(!g_getCameraMethodId)
		{
			LOG_ERROR("Could not get static method 'getCamera'.");
			return false;
		}
	}
	
	if(!g_cameraObject)
	{
		jobject tmp1 = env->CallStaticObjectMethod(g_cameraClass, g_getCameraMethodId);
		g_cameraObject = (jobject)env->NewGlobalRef(tmp1);
	}
		
	if(!g_startPreviewMethodId)
		g_startPreviewMethodId = env->GetMethodID(g_cameraClass, "startPreview", "()V");
	assert(g_startPreviewMethodId);
	
	if(!g_stopPreviewMethodId)
		g_stopPreviewMethodId = env->GetMethodID(g_cameraClass, "stopPreview", "()V");
	assert(g_stopPreviewMethodId);
	
	if(!g_takePhotoMethodId)
		g_takePhotoMethodId = env->GetMethodID(g_cameraClass, "takePhoto", "(Ljava/lang/String;)V");
	assert(g_takePhotoMethodId);
	
	if(!g_setCallbackDataMethodId)
		g_setCallbackDataMethodId = env->GetMethodID(g_cameraClass, "setCallbackData", ("(J)V"));
	assert(g_setCallbackDataMethodId);
	
	env->CallVoidMethod(g_cameraObject, g_setCallbackDataMethodId, (long long)this);
	
	m_initialized = true;
	return true;
}

void PCamera::Deinitialize()
{

}

bool PCamera::Start()
{
	g_env->CallVoidMethod(g_cameraObject, g_startPreviewMethodId);
	return true;
}

void PCamera::Stop()
{
	g_env->CallVoidMethod(g_cameraObject, g_stopPreviewMethodId);
}

void PCamera::Update()
{
	if(!m_initialized && !Initialize())
		return;
	
	if(g_frameLock)
	{
		m_frameUpdateCB(m_callbackData, (void*)g_data, 640, 480, 4);
		g_frameLock = false;
	}
	
	if(m_takePhoto)
	{
		if(m_photoSavedState != PhotoSaved_Waiting)
		{
			m_takePhoto = false;
			m_photoSavedState = PhotoSaved_Waiting;
			
			m_photoSavedCB(m_callbackData, m_photoSavedState);
		}
	}
}

void PCamera::TakePhoto(const char* path)
{
	m_takePhoto = true;
	
	jstring jPath = g_env->NewStringUTF(path);
	g_env->CallVoidMethod(g_cameraObject, g_takePhotoMethodId, jPath);
	g_env->DeleteLocalRef(jPath);
}

void PCamera::SetFocusPoint(const Vector2& focusPoint)
{

}

void PCamera::PhotoSavedCB(bool success)
{
	m_photoSavedState = success ? PhotoSaved_OK : PhotoSaved_Failed;
}

Camera* Camera::GetCamera(void* callbackData, FrameUpdateCallback frameUpdateCB, PhotoSavedCallback photoSavedCB)
{
	PCamera *camera = new PCamera;
	if(!camera)
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
	return Vector2(640, 480);
}

extern "C"
{
	JNIEXPORT void JNICALL Java_com_Camera_frameUpdate(JNIEnv * env, jobject jobj, jintArray data);
	JNIEXPORT void JNICALL Java_com_Camera_photoSaved(JNIEnv * env, jobject jobj, jlong callbackData, jboolean success);
}

JNIEXPORT void JNICALL Java_com_Camera_frameUpdate(JNIEnv * env, jobject jobj, jintArray data)
{
	if(!g_frameLock)
	{
		env->GetIntArrayRegion(data, 0, 640*480, g_data);
		g_frameLock = true;
	}
}

JNIEXPORT void JNICALL Java_com_Camera_photoSaved(JNIEnv * env, jobject jobj, jlong callbackData, jboolean success)
{
	PCamera* c = (PCamera*)callbackData;
	if(c)
		c->PhotoSavedCB(success);
}
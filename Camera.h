#pragma once

class Camera
{
public:
	typedef void (*FrameUpdateCallback)(void* priv, void* data, int width, int height, int numChannels);
	typedef void (*PhotoSavedCallback)(void* priv, bool success);
	
    virtual ~Camera();
	
	static Camera*	GetCamera(void* callbackData, FrameUpdateCallback frameUpdateCB, PhotoSavedCallback photoSavedCB);
	static Vector2 GetFrameSize();
	
	virtual bool	Initialize() = 0;
	virtual void	Deinitialize() = 0;
	virtual bool	Start() = 0;
	virtual void	Stop() = 0;
	virtual void	Update() = 0;
	virtual void	TakePhoto(const char* path) = 0;
	virtual void	SetFocusPoint(const Vector2& focusPoint) = 0;
		
	FrameUpdateCallback m_frameUpdateCB;
	PhotoSavedCallback m_photoSavedCB;
	void* m_callbackData;
	
	bool m_takePhoto;
	std::string m_photoPath;
};
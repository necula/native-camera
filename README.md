# native-camera (2014)

#####**This is a cross-platform C++ interface that you can use to get access to the hardware camera on iOS & Android devices.** 
I wrote this for a game where we needed to update an OpenGL texture with the camera feed.

It supports live video feed, picture capturing and focusing. Check Camera.h for a quick overview.

######Quick start:
Implement the two callbacks (FrameUpdateCallback & PhotoSavedCallback) in your delegate object, call GetCamera() & Start() and then call Update() whenever you need the video feed.








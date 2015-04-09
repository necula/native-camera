
public class Camera
{
	public Camera camera;
	public SurfaceTexture surface;
	public boolean newFrame;
	
	public static String photoPath;
	
	static native void frameUpdate(int[] data);
	static native void photoSaved(long callbackData, boolean success);
	
	public long callbackData;

	
	public static Camera getCamera()
	{
		Camera mc = new Camera();
		return mc;
	}
	
	public Camera()
	{
		init();
	}
	
	public void setCallbackData(long callbackData)
	{
		this.callbackData = callbackData;
	}
	
	public void init()
	{
		surface = new SurfaceTexture(0);
		
		CameraInfo info = new CameraInfo();
		int cameraId = -1;
		int numberOfCameras = Camera.getNumberOfCameras();
		for(int i = 0; i < numberOfCameras; i++)
		{
			Camera.getCameraInfo(i, info);
			if(info.facing == CameraInfo.CAMERA_FACING_BACK)
			{
				cameraId = i;
				break;
			}
		}
		
		if(cameraId == -1)
			return;
		
		camera = Camera.open(cameraId);
		
		Camera.Parameters params = camera.getParameters();
		params.setPreviewSize(640, 480);
		params.setPictureSize(640, 480);
		params.setPictureFormat(PixelFormat.JPEG);
		params.setJpegQuality(90);
		camera.setParameters(params);
		
				
		camera.setPreviewCallback(new PreviewCallback() {
			public void onPreviewFrame(byte[] data, Camera arg1) {
				
				boolean flip = false;
				int rotation = Utils.getRotation();
				
				if(rotation == Surface.ROTATION_180 || rotation == Surface.ROTATION_270)
					flip = true;
				
				int[] pixels = convertYUV420_NV21toARGB8888(data, 640, 480, flip);
				frameUpdate(pixels);
			}
		});
		
		try
		{
			camera.setPreviewTexture(surface);
		}
		catch(IOException ioe)
		{
		}
	}
	
	public void takePhoto(final String photoPath)
	{				
		camera.takePicture(null, null, new PictureCallback() {
			public void onPictureTaken(byte [] rawData, Camera camera) {
				try {
					if (rawData != null) {
						int rawDataLength = rawData.length;
						
						String dirStr = "";
						int pos = photoPath.lastIndexOf("/", photoPath.length() - 1);
						if(pos == -1)
							return;
						dirStr = photoPath.substring(0, pos);
						
						File dir = new File(dirStr);
						dir.mkdirs();
						
						File rawoutput = new File(photoPath);
						rawoutput.createNewFile();
						FileOutputStream outstream = new FileOutputStream(rawoutput);
						
						boolean flip = false;
						int rotation = Utils.getRotation();
						if(rotation == Surface.ROTATION_180 || rotation == Surface.ROTATION_270)
							flip = true;
						if(flip)
						{
							Bitmap bitmap = BitmapFactory.decodeByteArray(rawData, 0, rawData.length);
							ByteArrayOutputStream rotatedStream = new ByteArrayOutputStream();
							
							// Rotate the Bitmap
							Matrix matrix = new Matrix();
							matrix.postRotate(180);
							
							// We rotate the same Bitmap
							bitmap = Bitmap.createBitmap(bitmap, 0, 0, 640, 480, matrix, false);
							
							// We dump the rotated Bitmap to the stream
							bitmap.compress(CompressFormat.JPEG, 90, rotatedStream);
							
							rawData = rotatedStream.toByteArray();
						}
						
						outstream.write(rawData);

						photoSaved(callbackData, true);
					}
				} catch (Exception e) {
					Log.w("", "[CAMERA] takePhoto error " + e.toString());
				}
			}
		});
	}
	
	public void startPreview()
	{
		if(camera == null)
			init();
		camera.startPreview();
	}
	
	public void stopPreview()
	{
		camera.stopPreview();
		camera.release();
		camera = null;
	}
	
	public static int[] convertYUV420_NV21toARGB8888(byte [] data, int width, int height, boolean flip) {
		int size = width*height;
		int offset = size;
		int[] pixels = new int[size];
		int u, v, y1, y2, y3, y4;
		
		int startPos = 0;
		int helperIdx = -1;
		if(flip)
		{
			startPos = size - 1;
			helperIdx = 1;
		}
		
		// i along Y and the final pixels
		// k along pixels U and V
		for(int i=0, k=0; i < size; i+=2, k+=2) {
			y1 = data[i  ]&0xff;
			y2 = data[i+1]&0xff;
			y3 = data[width+i  ]&0xff;
			y4 = data[width+i+1]&0xff;
			
			v = data[offset+k  ]&0xff;
			u = data[offset+k+1]&0xff;
			v = v-128;
			u = u-128;
			
			pixels[startPos - helperIdx*i  ] = convertYUVtoARGB(y1, u, v);
			pixels[startPos - helperIdx*(i+1)] = convertYUVtoARGB(y2, u, v);
			pixels[startPos - helperIdx*(width+i)  ] = convertYUVtoARGB(y3, u, v);
			pixels[startPos - helperIdx*(width+i+1)] = convertYUVtoARGB(y4, u, v);
			
			if (i!=0 && (i+2)%width==0)
				i += width;
		}
		
		return pixels;
	}
	
	private static int convertYUVtoARGB(int y, int u, int v) {
		int r = y + (int)(1.772f*v);
		int g = y - (int)(0.344f*v + 0.714f*u);
		int b = y + (int)(1.402f*u);
		r = r>255? 255 : r<0 ? 0 : r;
		g = g>255? 255 : g<0 ? 0 : g;
		b = b>255? 255 : b<0 ? 0 : b;
		return 0xff000000 | r | (g<<8) | (b<<16);
	}
};
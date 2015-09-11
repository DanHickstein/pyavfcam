// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy
//--------------------------------------------------------------
//
// Keep the resemblence of a pure C++ header as much as possible
//

#include <vector>

@class AVCaptureDevice;
@class AVCaptureSession;
@class AVCaptureDelegate;
@class AVCaptureDeviceInput;
@class AVCaptureFileOutput;

@class CMSampleBufferRef;

struct _object;
typedef _object PyObject;;

class CppAVFCam
{
private:
    PyObject * m_pObj;  // Python binding
    AVCaptureSession * m_pSession;
    AVCaptureDevice * m_pDevice;              // Camera device
    AVCaptureDelegate * m_pCapture;           // Capture delegate
    AVCaptureDeviceInput * m_pVideoInput;
    AVCaptureFileOutput * m_pVideoFileOutput;

public:
    virtual void file_output_done(bool error);
    virtual void video_output(CMSampleBufferRef sampleBuffer);

public:

    CppAVFCam();
    CppAVFCam(bool sink_file, bool sink_callback, PyObject * pObj=NULL);
    CppAVFCam(const CppAVFCam& other);
    virtual ~CppAVFCam();

    CppAVFCam & operator= (CppAVFCam other);
    friend void swap(CppAVFCam& first, CppAVFCam& second); // nothrow

    void set_settings(unsigned int width, unsigned int height, unsigned int fps);
    void record(std::string path, unsigned int duration, bool blocking=false);
    void stop_recording();
    void get_device_formats();
    std::vector<unsigned int> get_dimension();
};

/* Generated by Cython 0.23.2 */

#ifndef __PYX_HAVE__pyavfcam
#define __PYX_HAVE__pyavfcam


#ifndef __PYX_HAVE_API__pyavfcam

#ifndef __PYX_EXTERN_C
  #ifdef __cplusplus
    #define __PYX_EXTERN_C extern "C"
  #else
    #define __PYX_EXTERN_C extern
  #endif
#endif

#ifndef DL_IMPORT
  #define DL_IMPORT(_T) _T
#endif

__PYX_EXTERN_C DL_IMPORT(PyObject) *cy_get_frame(CameraFrame &);
__PYX_EXTERN_C DL_IMPORT(void) cy_call_func(PyObject *, int *, char *, PyObject *, PyObject *);

#endif /* !__PYX_HAVE_API__pyavfcam */

#if PY_MAJOR_VERSION < 3
PyMODINIT_FUNC initpyavfcam(void);
#else
PyMODINIT_FUNC PyInit_pyavfcam(void);
#endif

#endif /* !__PYX_HAVE__pyavfcam */

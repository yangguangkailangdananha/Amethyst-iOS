/*
  Amethyst iOS SDL3 video driver - shared declarations.

  This driver does not create any UIKit windows. It forwards window/GL
  operations to the Amethyst host (Natives/mc26/AmethystSDLHost.m), which in
  turn uses the existing ctxbridges (EGL/OSMesa) and game surface.

  The host is resolved at runtime with dlsym(RTLD_DEFAULT, "Amethyst_GetHost"),
  so libSDL3 stays independent from the app binary.
*/
#ifndef SDL_amethystvideo_h_
#define SDL_amethystvideo_h_

#include "SDL_internal.h"
#include "../SDL_sysvideo.h"

typedef struct AMETHYST_Host
{
    int version;
    bool (*init)(void);
    void (*quit)(void);
    void *(*createContext)(void *share);
    void (*destroyContext)(void *context);
    bool (*makeCurrent)(void *context);
    bool (*swapBuffers)(void);
    bool (*setSwapInterval)(int interval);
    bool (*getSwapInterval)(int *interval);
    void *(*getProcAddress)(const char *name);
    bool (*loadLibrary)(const char *path);
    void (*unloadLibrary)(void);
    void (*getScreenSize)(int *w, int *h, float *refresh_rate, float *scale);
    const char *(*getClipboardText)(void);
    bool (*setClipboardText)(const char *text);
    void (*showMessageBox)(const char *title, const char *message);
    void *(*getMetalLayer)(void);
    const char *(*getVulkanLibraryPath)(void);
} AMETHYST_Host;

typedef struct AMETHYST_WindowData
{
    int w, h;
    float scale;
    SDL_GLContext gl_context;
} AMETHYST_WindowData;

extern AMETHYST_Host *AMETHYST_host;

extern SDL_VideoDevice *AMETHYST_CreateDevice(void);
extern bool AMETHYST_ShowMessageBox(const SDL_MessageBoxData *messageboxdata, int *buttonID);

extern bool AMETHYST_VideoInit(SDL_VideoDevice *_this);
extern void AMETHYST_VideoQuit(SDL_VideoDevice *_this);
extern bool AMETHYST_GetDisplayModes(SDL_VideoDevice *_this, SDL_VideoDisplay *display);
extern bool AMETHYST_SetDisplayMode(SDL_VideoDevice *_this, SDL_VideoDisplay *display, SDL_DisplayMode *mode);
extern bool AMETHYST_GetDisplayBounds(SDL_VideoDevice *_this, SDL_VideoDisplay *display, SDL_Rect *rect);
extern bool AMETHYST_GetDisplayUsableBounds(SDL_VideoDevice *_this, SDL_VideoDisplay *display, SDL_Rect *rect);

extern bool AMETHYST_CreateWindow(SDL_VideoDevice *_this, SDL_Window *window, SDL_PropertiesID create_props);
extern void AMETHYST_DestroyWindow(SDL_VideoDevice *_this, SDL_Window *window);
extern void AMETHYST_SetWindowTitle(SDL_VideoDevice *_this, SDL_Window *window);
extern bool AMETHYST_SetWindowIcon(SDL_VideoDevice *_this, SDL_Window *window, SDL_Surface *icon);
extern bool AMETHYST_SetWindowPosition(SDL_VideoDevice *_this, SDL_Window *window);
extern void AMETHYST_SetWindowSize(SDL_VideoDevice *_this, SDL_Window *window);
extern void AMETHYST_SetWindowMinimumSize(SDL_VideoDevice *_this, SDL_Window *window);
extern void AMETHYST_SetWindowMaximumSize(SDL_VideoDevice *_this, SDL_Window *window);
extern void AMETHYST_ShowWindow(SDL_VideoDevice *_this, SDL_Window *window);
extern void AMETHYST_HideWindow(SDL_VideoDevice *_this, SDL_Window *window);
extern void AMETHYST_RaiseWindow(SDL_VideoDevice *_this, SDL_Window *window);
extern void AMETHYST_MaximizeWindow(SDL_VideoDevice *_this, SDL_Window *window);
extern void AMETHYST_MinimizeWindow(SDL_VideoDevice *_this, SDL_Window *window);
extern void AMETHYST_RestoreWindow(SDL_VideoDevice *_this, SDL_Window *window);
extern void AMETHYST_SetWindowBordered(SDL_VideoDevice *_this, SDL_Window *window, bool bordered);
extern void AMETHYST_SetWindowResizable(SDL_VideoDevice *_this, SDL_Window *window, bool resizable);
extern void AMETHYST_SetWindowAlwaysOnTop(SDL_VideoDevice *_this, SDL_Window *window, bool on_top);
extern SDL_FullscreenResult AMETHYST_SetWindowFullscreen(SDL_VideoDevice *_this, SDL_Window *window, SDL_VideoDisplay *display, SDL_FullscreenOp fullscreen);
extern SDL_DisplayID AMETHYST_GetDisplayForWindow(SDL_VideoDevice *_this, SDL_Window *window);
extern bool AMETHYST_SetWindowMouseRect(SDL_VideoDevice *_this, SDL_Window *window);
extern bool AMETHYST_SetWindowMouseGrab(SDL_VideoDevice *_this, SDL_Window *window, bool grabbed);
extern bool AMETHYST_SetWindowKeyboardGrab(SDL_VideoDevice *_this, SDL_Window *window, bool grabbed);
extern bool AMETHYST_SyncWindow(SDL_VideoDevice *_this, SDL_Window *window);
extern bool AMETHYST_SetWindowFocusable(SDL_VideoDevice *_this, SDL_Window *window, bool focusable);
extern bool AMETHYST_SetWindowOpacity(SDL_VideoDevice *_this, SDL_Window *window, float opacity);
extern void AMETHYST_GetWindowSizeInPixels(SDL_VideoDevice *_this, SDL_Window *window, int *w, int *h);
extern float AMETHYST_GetWindowContentScale(SDL_VideoDevice *_this, SDL_Window *window);

extern bool AMETHYST_GL_LoadLibrary(SDL_VideoDevice *_this, const char *path);
extern SDL_FunctionPointer AMETHYST_GL_GetProcAddress(SDL_VideoDevice *_this, const char *proc);
extern void AMETHYST_GL_UnloadLibrary(SDL_VideoDevice *_this);
extern SDL_GLContext AMETHYST_GL_CreateContext(SDL_VideoDevice *_this, SDL_Window *window);
extern bool AMETHYST_GL_MakeCurrent(SDL_VideoDevice *_this, SDL_Window *window, SDL_GLContext context);
extern bool AMETHYST_GL_SetSwapInterval(SDL_VideoDevice *_this, int interval);
extern bool AMETHYST_GL_GetSwapInterval(SDL_VideoDevice *_this, int *interval);
extern bool AMETHYST_GL_SwapWindow(SDL_VideoDevice *_this, SDL_Window *window);
extern bool AMETHYST_GL_DestroyContext(SDL_VideoDevice *_this, SDL_GLContext context);

extern void AMETHYST_PumpEvents(SDL_VideoDevice *_this);
extern bool AMETHYST_SetClipboardText(SDL_VideoDevice *_this, const char *text);
extern char *AMETHYST_GetClipboardText(SDL_VideoDevice *_this);

extern void AMETHYST_SetInputWindow(SDL_Window *window);
extern void AMETHYST_NotifyWindowShown(void);

#ifdef SDL_VIDEO_VULKAN
extern void AMETHYST_InstallVulkan(SDL_VideoDevice *device);
#endif

#endif /* SDL_amethystvideo_h_ */

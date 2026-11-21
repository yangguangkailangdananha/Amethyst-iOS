/*
  Amethyst iOS SDL3 video driver - window handling.

  Amethyst already owns the game surface (GameSurfaceView + ctxbridges), so
  SDL windows are only bookkeeping objects: no UIWindow/UIView is created.
*/
#include "SDL_internal.h"

#ifdef SDL_VIDEO_DRIVER_AMETHYST

#include "SDL_amethystvideo.h"

bool AMETHYST_CreateWindow(SDL_VideoDevice *_this, SDL_Window *window, SDL_PropertiesID create_props)
{
    AMETHYST_WindowData *data = (AMETHYST_WindowData *)SDL_calloc(1, sizeof(AMETHYST_WindowData));
    if (!data) {
        return false;
    }
    // The drawable is the full Amethyst game surface; MC's requested window
    // size is ignored so the SDL framebuffer matches the EGL surface.
    int w = 1920, h = 1080;
    float refresh = 60.0f, scale = 1.0f;
    if (AMETHYST_host && AMETHYST_host->getScreenSize) {
        AMETHYST_host->getScreenSize(&w, &h, &refresh, &scale);
    }
    data->w = w > 0 ? w : 1920;
    data->h = h > 0 ? h : 1080;
    data->scale = 1.0f;
    data->gl_context = NULL;

    window->internal = data;
    window->w = data->w;
    window->h = data->h;
    SDL_Log("[Amethyst] create window id=%u %dx%d (requested %dx%d, flags 0x%llx)",
            (unsigned)window->id, data->w, data->h,
            (int)SDL_GetNumberProperty(create_props, SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, 0),
            (int)SDL_GetNumberProperty(create_props, SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, 0),
            (unsigned long long)window->flags);
    AMETHYST_SetInputWindow(window);
    AMETHYST_NotifyWindowShown();
    return true;
}

void AMETHYST_DestroyWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    AMETHYST_SetInputWindow(NULL);
    if (window->internal) {
        SDL_free(window->internal);
        window->internal = NULL;
    }
}

void AMETHYST_SetWindowTitle(SDL_VideoDevice *_this, SDL_Window *window)
{
    // The title belongs to the Amethyst launcher UI; nothing to do.
}

bool AMETHYST_SetWindowIcon(SDL_VideoDevice *_this, SDL_Window *window, SDL_Surface *icon)
{
    return true;
}

bool AMETHYST_SetWindowPosition(SDL_VideoDevice *_this, SDL_Window *window)
{
    return true;
}

void AMETHYST_SetWindowSize(SDL_VideoDevice *_this, SDL_Window *window)
{
    AMETHYST_WindowData *data = (AMETHYST_WindowData *)window->internal;
    if (data) {
        // The Amethyst surface always fills the screen; ignore resize requests
        // and restore the drawable size so SDL state stays consistent.
        window->w = data->w;
        window->h = data->h;
    }
}

void AMETHYST_SetWindowMinimumSize(SDL_VideoDevice *_this, SDL_Window *window)
{
}

void AMETHYST_SetWindowMaximumSize(SDL_VideoDevice *_this, SDL_Window *window)
{
}

void AMETHYST_ShowWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
}

void AMETHYST_HideWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
}

void AMETHYST_RaiseWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
}

void AMETHYST_MaximizeWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
}

void AMETHYST_MinimizeWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
}

void AMETHYST_RestoreWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
}

void AMETHYST_SetWindowBordered(SDL_VideoDevice *_this, SDL_Window *window, bool bordered)
{
}

void AMETHYST_SetWindowResizable(SDL_VideoDevice *_this, SDL_Window *window, bool resizable)
{
}

void AMETHYST_SetWindowAlwaysOnTop(SDL_VideoDevice *_this, SDL_Window *window, bool on_top)
{
}

SDL_FullscreenResult AMETHYST_SetWindowFullscreen(SDL_VideoDevice *_this, SDL_Window *window, SDL_VideoDisplay *display, SDL_FullscreenOp fullscreen)
{
    return SDL_FULLSCREEN_SUCCEEDED;
}

SDL_DisplayID AMETHYST_GetDisplayForWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    if (_this->num_displays > 0) {
        return _this->displays[0]->id;
    }
    return 0;
}

bool AMETHYST_SetWindowMouseRect(SDL_VideoDevice *_this, SDL_Window *window)
{
    return true;
}

bool AMETHYST_SetWindowMouseGrab(SDL_VideoDevice *_this, SDL_Window *window, bool grabbed)
{
    return true;
}

bool AMETHYST_SetWindowKeyboardGrab(SDL_VideoDevice *_this, SDL_Window *window, bool grabbed)
{
    return true;
}

bool AMETHYST_SyncWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    return true;
}

bool AMETHYST_SetWindowFocusable(SDL_VideoDevice *_this, SDL_Window *window, bool focusable)
{
    return true;
}

bool AMETHYST_SetWindowOpacity(SDL_VideoDevice *_this, SDL_Window *window, float opacity)
{
    return true;
}

void AMETHYST_GetWindowSizeInPixels(SDL_VideoDevice *_this, SDL_Window *window, int *w, int *h)
{
    AMETHYST_WindowData *data = (AMETHYST_WindowData *)window->internal;
    if (data) {
        *w = data->w;
        *h = data->h;
    } else {
        *w = window->w;
        *h = window->h;
    }
}

float AMETHYST_GetWindowContentScale(SDL_VideoDevice *_this, SDL_Window *window)
{
    AMETHYST_WindowData *data = (AMETHYST_WindowData *)window->internal;
    return data ? data->scale : 1.0f;
}

#endif /* SDL_VIDEO_DRIVER_AMETHYST */

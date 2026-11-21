/*
  Amethyst iOS SDL3 video driver - OpenGL context handling.

  All GL work is delegated to the Amethyst host, which wraps the existing
  ctxbridges (EGL/OSMesa + MobileGlues/ANGLE/gl4es). This keeps SDL away from
  EAGL and UIKit entirely.
*/
#include "SDL_internal.h"

#ifdef SDL_VIDEO_DRIVER_AMETHYST

#include "SDL_amethystvideo.h"

bool AMETHYST_GL_LoadLibrary(SDL_VideoDevice *_this, const char *path)
{
    if (!AMETHYST_host) {
        return SDL_SetError("Amethyst host is not available");
    }
    if (AMETHYST_host->loadLibrary) {
        return AMETHYST_host->loadLibrary(path);
    }
    return true;
}

SDL_FunctionPointer AMETHYST_GL_GetProcAddress(SDL_VideoDevice *_this, const char *proc)
{
    if (AMETHYST_host && AMETHYST_host->getProcAddress) {
        return (SDL_FunctionPointer)AMETHYST_host->getProcAddress(proc);
    }
    return NULL;
}

void AMETHYST_GL_UnloadLibrary(SDL_VideoDevice *_this)
{
    if (AMETHYST_host && AMETHYST_host->unloadLibrary) {
        AMETHYST_host->unloadLibrary();
    }
}

SDL_GLContext AMETHYST_GL_CreateContext(SDL_VideoDevice *_this, SDL_Window *window)
{
    AMETHYST_WindowData *data = (AMETHYST_WindowData *)window->internal;
    void *context;

    if (!AMETHYST_host || !AMETHYST_host->createContext) {
        SDL_SetError("Amethyst host has no GL support");
        return NULL;
    }
    context = AMETHYST_host->createContext(NULL);
    if (!context) {
        SDL_SetError("Amethyst GL context creation failed");
        SDL_Log("[Amethyst] GL context creation FAILED");
        return NULL;
    }
    if (data) {
        data->gl_context = (SDL_GLContext)context;
    }
    SDL_Log("[Amethyst] GL context created: %p (%dx%d)", context, data ? data->w : 0, data ? data->h : 0);
    return (SDL_GLContext)context;
}

bool AMETHYST_GL_MakeCurrent(SDL_VideoDevice *_this, SDL_Window *window, SDL_GLContext context)
{
    if (!AMETHYST_host || !AMETHYST_host->makeCurrent) {
        return SDL_SetError("Amethyst host has no GL support");
    }
    return AMETHYST_host->makeCurrent(context);
}

bool AMETHYST_GL_SetSwapInterval(SDL_VideoDevice *_this, int interval)
{
    if (AMETHYST_host && AMETHYST_host->setSwapInterval) {
        return AMETHYST_host->setSwapInterval(interval);
    }
    return true;
}

bool AMETHYST_GL_GetSwapInterval(SDL_VideoDevice *_this, int *interval)
{
    if (AMETHYST_host && AMETHYST_host->getSwapInterval) {
        return AMETHYST_host->getSwapInterval(interval);
    }
    *interval = 0;
    return true;
}

bool AMETHYST_GL_SwapWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    if (AMETHYST_host && AMETHYST_host->swapBuffers) {
        return AMETHYST_host->swapBuffers();
    }
    return true;
}

bool AMETHYST_GL_DestroyContext(SDL_VideoDevice *_this, SDL_GLContext context)
{
    if (AMETHYST_host && AMETHYST_host->destroyContext) {
        AMETHYST_host->destroyContext(context);
    }
    return true;
}

#endif /* SDL_VIDEO_DRIVER_AMETHYST */

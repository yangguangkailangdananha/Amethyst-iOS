/*
  Amethyst iOS SDL3 video driver - device bootstrap and displays.

  See SDL_amethystvideo.h. The host callbacks are resolved at runtime so this
  driver can live inside libSDL3 without linking against the app binary.
*/
#include "SDL_internal.h"

#ifdef SDL_VIDEO_DRIVER_AMETHYST

#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

#include "SDL_amethystvideo.h"

AMETHYST_Host *AMETHYST_host = NULL;

// Also append diagnostics to a file under AME_HOME: native stderr is not
// reliably captured by the launcher log view on iOS.
void AMETHYST_FileLog(const char *fmt, ...)
{
    const char *home = getenv("AME_HOME");
    if (!home || !*home) {
        return;
    }
    char path[1024];
    snprintf(path, sizeof(path), "%s/mc26_sdl.log", home);
    FILE *f = fopen(path, "a");
    if (!f) {
        return;
    }
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

static bool AMETHYST_ResolveHost(void)
{
    if (AMETHYST_host) {
        return true;
    }
    typedef AMETHYST_Host *(*GetHostFn)(void);
    GetHostFn getHost = (GetHostFn)dlsym(RTLD_DEFAULT, "Amethyst_GetHost");
    const char *source = "RTLD_DEFAULT";
    if (!getHost) {
        // On iOS a dlopen'ed library may not see the main executable in the
        // RTLD_DEFAULT scope; retry with an explicit handle for the main image.
        void *mainHandle = dlopen(NULL, RTLD_NOW | RTLD_GLOBAL);
        if (mainHandle) {
            getHost = (GetHostFn)dlsym(mainHandle, "Amethyst_GetHost");
            source = "dlopen(NULL)";
        }
    }
    if (!getHost) {
        fprintf(stderr, "[Amethyst] Amethyst_GetHost NOT FOUND (dlsym RTLD_DEFAULT and main image)\n");
        AMETHYST_FileLog("[Amethyst] Amethyst_GetHost NOT FOUND");
        SDL_Log("[Amethyst] Amethyst_GetHost NOT FOUND (dlsym failed)");
        return false;
    }
    AMETHYST_host = getHost();
    fprintf(stderr, "[Amethyst] host resolved via %s: %p\n", source, (void *)AMETHYST_host);
    AMETHYST_FileLog("[Amethyst] host resolved via %s: %p", source, (void *)AMETHYST_host);
    SDL_Log("[Amethyst] host resolved via %s: %p", source, (void *)AMETHYST_host);
    return AMETHYST_host != NULL;
}

bool AMETHYST_ShowMessageBox(const SDL_MessageBoxData *messageboxdata, int *buttonID)
{
    if (!AMETHYST_ResolveHost() || !AMETHYST_host->showMessageBox) {
        return false;
    }
    AMETHYST_host->showMessageBox(messageboxdata->title, messageboxdata->message);
    if (buttonID) {
        *buttonID = 0;
    }
    return true;
}

static void AMETHYST_DeleteDevice(SDL_VideoDevice *device)
{
    SDL_free(device);
}

SDL_VideoDevice *AMETHYST_CreateDevice(void)
{
    SDL_VideoDevice *device;

    SDL_Log("[Amethyst] CreateDevice called");
    AMETHYST_FileLog("[Amethyst] CreateDevice called");
    if (!AMETHYST_ResolveHost()) {
        // Not running inside Amethyst: let another driver handle it.
        return NULL;
    }

    device = (SDL_VideoDevice *)SDL_calloc(1, sizeof(SDL_VideoDevice));
    if (!device) {
        return NULL;
    }

    device->name = "amethyst";
    device->VideoInit = AMETHYST_VideoInit;
    device->VideoQuit = AMETHYST_VideoQuit;
    device->GetDisplayModes = AMETHYST_GetDisplayModes;
    device->SetDisplayMode = AMETHYST_SetDisplayMode;
    device->GetDisplayBounds = AMETHYST_GetDisplayBounds;
    device->GetDisplayUsableBounds = AMETHYST_GetDisplayUsableBounds;

    device->CreateSDLWindow = AMETHYST_CreateWindow;
    device->DestroyWindow = AMETHYST_DestroyWindow;
    device->SetWindowTitle = AMETHYST_SetWindowTitle;
    device->SetWindowIcon = AMETHYST_SetWindowIcon;
    device->SetWindowPosition = AMETHYST_SetWindowPosition;
    device->SetWindowSize = AMETHYST_SetWindowSize;
    device->SetWindowMinimumSize = AMETHYST_SetWindowMinimumSize;
    device->SetWindowMaximumSize = AMETHYST_SetWindowMaximumSize;
    device->ShowWindow = AMETHYST_ShowWindow;
    device->HideWindow = AMETHYST_HideWindow;
    device->RaiseWindow = AMETHYST_RaiseWindow;
    device->MaximizeWindow = AMETHYST_MaximizeWindow;
    device->MinimizeWindow = AMETHYST_MinimizeWindow;
    device->RestoreWindow = AMETHYST_RestoreWindow;
    device->SetWindowBordered = AMETHYST_SetWindowBordered;
    device->SetWindowResizable = AMETHYST_SetWindowResizable;
    device->SetWindowAlwaysOnTop = AMETHYST_SetWindowAlwaysOnTop;
    device->SetWindowFullscreen = AMETHYST_SetWindowFullscreen;
    device->GetDisplayForWindow = AMETHYST_GetDisplayForWindow;
    device->SetWindowMouseRect = AMETHYST_SetWindowMouseRect;
    device->SetWindowMouseGrab = AMETHYST_SetWindowMouseGrab;
    device->SetWindowKeyboardGrab = AMETHYST_SetWindowKeyboardGrab;
    device->SyncWindow = AMETHYST_SyncWindow;
    device->SetWindowFocusable = AMETHYST_SetWindowFocusable;
    device->SetWindowOpacity = AMETHYST_SetWindowOpacity;
    device->GetWindowSizeInPixels = AMETHYST_GetWindowSizeInPixels;
    device->GetWindowContentScale = AMETHYST_GetWindowContentScale;

    device->GL_LoadLibrary = AMETHYST_GL_LoadLibrary;
    device->GL_GetProcAddress = AMETHYST_GL_GetProcAddress;
    device->GL_UnloadLibrary = AMETHYST_GL_UnloadLibrary;
    device->GL_CreateContext = AMETHYST_GL_CreateContext;
    device->GL_MakeCurrent = AMETHYST_GL_MakeCurrent;
    device->GL_SetSwapInterval = AMETHYST_GL_SetSwapInterval;
    device->GL_GetSwapInterval = AMETHYST_GL_GetSwapInterval;
    device->GL_SwapWindow = AMETHYST_GL_SwapWindow;
    device->GL_DestroyContext = AMETHYST_GL_DestroyContext;

    device->PumpEvents = AMETHYST_PumpEvents;
    device->SetClipboardText = AMETHYST_SetClipboardText;
    device->GetClipboardText = AMETHYST_GetClipboardText;

#ifdef SDL_VIDEO_VULKAN
    AMETHYST_InstallVulkan(device);
#endif

    device->free = AMETHYST_DeleteDevice;

    return device;
}

VideoBootStrap AMETHYST_bootstrap = {
    "amethyst", "Amethyst iOS video driver",
    AMETHYST_CreateDevice,
    AMETHYST_ShowMessageBox,
    true // preferred over the UIKit driver when the host is available
};

bool AMETHYST_VideoInit(SDL_VideoDevice *_this)
{
    SDL_DisplayMode mode;
    int w = 1024, h = 768;
    float refresh = 60.0f, scale = 1.0f;

    SDL_Log("[Amethyst] VideoInit");
    AMETHYST_FileLog("[Amethyst] VideoInit");
    if (!AMETHYST_ResolveHost() || !AMETHYST_host->init) {
        return SDL_SetError("Amethyst host is not available");
    }
    if (!AMETHYST_host->init()) {
        return SDL_SetError("Amethyst host video init failed");
    }

    if (AMETHYST_host->getScreenSize) {
        AMETHYST_host->getScreenSize(&w, &h, &refresh, &scale);
    }
    SDL_Log("[Amethyst] video init %dx%d @ %.1f Hz (scale %.2f, SDL %s)",
            w, h, refresh, scale, SDL_GetRevision());

    SDL_zero(mode);
    mode.format = SDL_PIXELFORMAT_XRGB8888;
    mode.w = w;
    mode.h = h;
    mode.refresh_rate = refresh;
    if (SDL_AddBasicVideoDisplay(&mode) == 0) {
        return SDL_SetError("Couldn't add Amethyst display");
    }
    return true;
}

void AMETHYST_VideoQuit(SDL_VideoDevice *_this)
{
    if (AMETHYST_host && AMETHYST_host->quit) {
        AMETHYST_host->quit();
    }
}

bool AMETHYST_GetDisplayModes(SDL_VideoDevice *_this, SDL_VideoDisplay *display)
{
    SDL_DisplayMode mode = display->desktop_mode;
    return SDL_AddFullscreenDisplayMode(display, &mode);
}

bool AMETHYST_SetDisplayMode(SDL_VideoDevice *_this, SDL_VideoDisplay *display, SDL_DisplayMode *mode)
{
    return true;
}

bool AMETHYST_GetDisplayBounds(SDL_VideoDevice *_this, SDL_VideoDisplay *display, SDL_Rect *rect)
{
    const SDL_DisplayMode *mode = display->current_mode ? display->current_mode : &display->desktop_mode;
    rect->x = 0;
    rect->y = 0;
    rect->w = mode->w;
    rect->h = mode->h;
    return true;
}

bool AMETHYST_GetDisplayUsableBounds(SDL_VideoDevice *_this, SDL_VideoDisplay *display, SDL_Rect *rect)
{
    return AMETHYST_GetDisplayBounds(_this, display, rect);
}

#endif /* SDL_VIDEO_DRIVER_AMETHYST */

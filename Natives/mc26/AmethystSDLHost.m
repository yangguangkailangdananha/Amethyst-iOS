/*
  Amethyst host for the custom SDL3 video driver (Minecraft 26.x).

  libSDL3 resolves Amethyst_GetHost with dlsym(RTLD_DEFAULT, ...) and uses the
  callbacks below instead of touching UIKit. Everything is forwarded to the
  existing ctxbridges (EGL/OSMesa) and the launcher UI, so the SDL driver can
  run on the JVM thread exactly like the GLFW bridge does today.
*/
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <limits.h>

// Report the video drivers compiled into our libSDL3. If "amethyst" is
// missing here the driver was not registered by the build.
__attribute__((visibility("default"))) void Amethyst_LogSDLDrivers(void)
{
    NSString *sdlPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/lwjgl343/libSDL3.dylib"];
    void *sdl = dlopen(sdlPath.UTF8String, RTLD_NOW | RTLD_GLOBAL);
    if (sdl) {
        int (*numDrivers)(void) = (int (*)(void))dlsym(sdl, "SDL_GetNumVideoDrivers");
        const char *(*driverName)(int) = (const char *(*)(int))dlsym(sdl, "SDL_GetVideoDriver");
        int count = numDrivers ? numDrivers() : -1;
        NSMutableString *names = [NSMutableString string];
        for (int i = 0; i < count; i++) {
            const char *name = driverName ? driverName(i) : NULL;
            if (name) {
                [names appendFormat:@"%s,", name];
            }
        }
        NSLog(@"[MC26] SDL3 video drivers (%d): %@", count, names);
    } else {
        NSLog(@"[MC26] SDL3 dlopen failed: %s", dlerror());
    }
}

// Logged before the JVM starts: confirms that the exported entry point is
// visible to dlopen'ed libraries (the SDL driver resolves it the same way).
__attribute__((constructor)) static void amc26_host_constructor(void)
{
    void *symbol = dlsym(RTLD_DEFAULT, "Amethyst_GetHost");
    void *mainHandle = dlopen(NULL, RTLD_NOW | RTLD_GLOBAL);
    void *mainSymbol = mainHandle ? dlsym(mainHandle, "Amethyst_GetHost") : NULL;
    NSLog(@"[MC26] host ctor: RTLD_DEFAULT=%p main=%p mainHandle=%p", symbol, mainSymbol, mainHandle);
}
#import <math.h>
#import <stdbool.h>
#import <stdlib.h>
#import <string.h>

#include "ctxbridges/bridge_tbl.h"
#include "ios_uikit_bridge.h"
#include "SurfaceViewController.h"

#define AMETHYST_HOST_VERSION 2

typedef struct AmethystHost {
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
} AmethystHost;

static int hostScreenWidth = 1920;
static int hostScreenHeight = 1080;
static float hostScreenScale = 1.0f;
static float hostRefreshRate = 60.0f;
static int hostSwapInterval = 1;
static char *hostClipboardCache = NULL;

static void amc26_read_screen(void)
{
    __block CGSize size = CGSizeMake(1920, 1080);
    __block CGFloat scale = 1.0;
    __block NSInteger fps = 60;
    dispatch_block_t read = ^{
        UIScreen *screen = UIScreen.mainScreen;
        size = screen.bounds.size;
        scale = screen.scale;
        fps = (NSInteger)screen.maximumFramesPerSecond;
    };
    if ([NSThread isMainThread]) {
        read();
    } else {
        dispatch_sync(dispatch_get_main_queue(), read);
    }
    hostScreenScale = (float)scale;
    hostScreenWidth = (int)lround(size.width * scale);
    hostScreenHeight = (int)lround(size.height * scale);
    hostRefreshRate = fps > 0 ? (float)fps : 60.0f;
}

typedef void (*amc26_sdl_log_fn)(void *userdata, int category, int priority, const char *message);
typedef void (*amc26_sdl_set_log_fn)(amc26_sdl_log_fn callback, void *userdata);

static void amc26_sdl_log(void *userdata, int category, int priority, const char *message)
{
    NSLog(@"[SDL] %s", message ? message : "");
}

static bool amc26_init(void)
{
    extern int pojavInit(BOOL useStackQueue);
    pojavInit(YES);
    NSLog(@"[MC26] pojavInit called (isInputReady=1)");
    // Route SDL logs through NSLog so they end up in the launcher log file.
    void *sdlHandle = dlopen("@rpath/libSDL3.dylib", RTLD_NOW | RTLD_GLOBAL);
    if (!sdlHandle) {
        sdlHandle = dlopen("libSDL3.dylib", RTLD_NOW | RTLD_GLOBAL);
    }
    if (sdlHandle) {
        amc26_sdl_set_log_fn setLog = (amc26_sdl_set_log_fn)dlsym(sdlHandle, "SDL_SetLogOutputFunction");
        if (setLog) {
            setLog(amc26_sdl_log, NULL);
            NSLog(@"[MC26] SDL log callback installed");
        }
    } else {
        NSLog(@"[MC26] could not dlopen libSDL3 for log callback");
    }

    const char *renderer = getenv("RENDERER");
    if (!renderer || !*renderer || strcmp(renderer, "auto") == 0) {
        // Same default as pojavInitOpenGL(): gl4es when the profile uses "auto".
        renderer = "libgl4es_114.dylib";
    }
    if (strstr(renderer, "OSMesa") != NULL) {
        set_osm_bridge_tbl();
    } else {
        set_gl_bridge_tbl();
    }
    NSString *lib = [NSString stringWithFormat:@"@rpath/%s", renderer];
    void *rendererHandle = dlopen(lib.UTF8String, RTLD_GLOBAL);
    NSLog(@"[MC26] host init renderer=%s handle=%p bridge=%p", renderer, rendererHandle, (void *)br_init);

    if (!br_init || !br_init()) {
        NSLog(@"[MC26] host br_init FAILED");
        return false;
    }
    amc26_read_screen();
    NSLog(@"[MC26] host ready drawable=%dx%d scale=%.2f refresh=%.1f",
          hostScreenWidth, hostScreenHeight, hostScreenScale, hostRefreshRate);
    return true;
}

static void amc26_quit(void)
{
    if (br_terminate) {
        br_terminate();
    }
}

static void *amc26_create_context(void *share)
{
    if (!br_init_context) {
        return NULL;
    }
    return br_init_context((basic_render_window_t *)share);
}

static void amc26_destroy_context(void *context)
{
    if (context) {
        free(context);
    }
}

static bool amc26_make_current(void *context)
{
    if (!br_make_current) {
        return false;
    }
    br_make_current((basic_render_window_t *)context);
    return true;
}

static bool amc26_swap_buffers(void)
{
    if (br_swap_buffers) {
        br_swap_buffers();
    }
    return true;
}

static bool amc26_set_swap_interval(int interval)
{
    hostSwapInterval = interval;
    if (br_swap_interval) {
        br_swap_interval(interval);
    }
    return true;
}

static bool amc26_get_swap_interval(int *interval)
{
    if (interval) {
        *interval = hostSwapInterval;
    }
    return true;
}

static void *amc26_get_proc_address(const char *name)
{
    void *symbol = name ? dlsym(RTLD_DEFAULT, name) : NULL;
    if (!symbol && name) {
        static void *(*eglGetProcAddress)(const char *) = NULL;
        if (!eglGetProcAddress) {
            eglGetProcAddress = (void *(*)(const char *))dlsym(RTLD_DEFAULT, "eglGetProcAddress");
        }
        if (eglGetProcAddress) {
            symbol = eglGetProcAddress(name);
        }
    }
    return symbol;
}

static bool amc26_load_library(const char *path)
{
    if (path && *path) {
        dlopen(path, RTLD_GLOBAL);
    }
    return true;
}

static void amc26_unload_library(void)
{
}

static void amc26_get_screen_size(int *w, int *h, float *refresh_rate, float *scale)
{
    if (w) *w = hostScreenWidth;
    if (h) *h = hostScreenHeight;
    if (refresh_rate) *refresh_rate = hostRefreshRate;
    if (scale) *scale = hostScreenScale;
}

static const char *amc26_get_clipboard_text(void)
{
    __block NSString *text = nil;
    dispatch_block_t read = ^{
        text = UIPasteboard.generalPasteboard.string;
    };
    if ([NSThread isMainThread]) {
        read();
    } else {
        dispatch_sync(dispatch_get_main_queue(), read);
    }
    if (hostClipboardCache) {
        free(hostClipboardCache);
        hostClipboardCache = NULL;
    }
    if (text) {
        hostClipboardCache = strdup(text.UTF8String);
    }
    return hostClipboardCache ? hostClipboardCache : "";
}

static bool amc26_set_clipboard_text(const char *text)
{
    if (!text) {
        return false;
    }
    NSString *value = [NSString stringWithUTF8String:text];
    dispatch_block_t write = ^{
        UIPasteboard.generalPasteboard.string = value;
    };
    if ([NSThread isMainThread]) {
        write();
    } else {
        dispatch_sync(dispatch_get_main_queue(), write);
    }
    return true;
}

static void amc26_show_message_box(const char *title, const char *message)
{
    NSString *t = title ? [NSString stringWithUTF8String:title] : @"";
    NSString *m = message ? [NSString stringWithUTF8String:message] : @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        showDialog(t, m);
    });
}

static void *amc26_get_metal_layer(void)
{
    __block void *layer = NULL;
    dispatch_block_t read = ^{
        layer = (__bridge void *)SurfaceViewController.surface.layer;
    };
    if ([NSThread isMainThread]) {
        read();
    } else {
        dispatch_sync(dispatch_get_main_queue(), read);
    }
    return layer;
}

static const char *amc26_get_vulkan_library_path(void)
{
    static char path[PATH_MAX];
    if (path[0] == '\0') {
        snprintf(path, sizeof(path), "%s/Frameworks/libMoltenVK.dylib",
                 NSBundle.mainBundle.bundlePath.UTF8String);
    }
    return path;
}

static AmethystHost host = {
    AMETHYST_HOST_VERSION,
    amc26_init,
    amc26_quit,
    amc26_create_context,
    amc26_destroy_context,
    amc26_make_current,
    amc26_swap_buffers,
    amc26_set_swap_interval,
    amc26_get_swap_interval,
    amc26_get_proc_address,
    amc26_load_library,
    amc26_unload_library,
    amc26_get_screen_size,
    amc26_get_clipboard_text,
    amc26_set_clipboard_text,
    amc26_show_message_box,
    amc26_get_metal_layer,
    amc26_get_vulkan_library_path,
};

__attribute__((visibility("default"))) AmethystHost *Amethyst_GetHost(void)
{
    return &host;
}

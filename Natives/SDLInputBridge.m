#import "SDLInputBridge.h"

#import <SDL3/SDL.h>
#import "SurfaceViewController.h"
#import "glfw_keycodes.h"
#import "utils.h"

extern bool AMESDL_SendKey(Uint64 timestamp, int rawcode, SDL_Scancode scancode, bool down);
extern void AMESDL_SendKeyboardText(const char *text);
extern void AMESDL_SendMouseMotion(Uint64 timestamp, SDL_Window *window, bool relative, float x, float y);
extern void AMESDL_SendMouseButton(Uint64 timestamp, SDL_Window *window, Uint8 button, bool down);
extern void AMESDL_SendMouseWheel(Uint64 timestamp, SDL_Window *window, float x, float y, SDL_MouseWheelDirection direction);

static __weak SurfaceViewController *ameSDLController;
static __weak UIWindow *ameSDLAttachedWindow;
static id ameSDLWindowObserver;
static NSTimer *ameSDLOverlayTimer;
static jchar ameSDLHighSurrogate;

static UIWindow *AMESDLGetUIKitWindow(SDL_Window *window) {
    if (!window) return nil;
    SDL_PropertiesID properties = SDL_GetWindowProperties(window);
    return (__bridge UIWindow *)SDL_GetPointerProperty(properties,
        SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL);
}

static SDL_Window *AMESDLWindowForUIKitWindow(UIWindow *uiwindow) {
    if (!uiwindow || !SDL_WasInit(SDL_INIT_VIDEO)) return NULL;
    int count = 0;
    SDL_Window **windows = SDL_GetWindows(&count);
    SDL_Window *result = NULL;
    for (int i = 0; i < count; i++) {
        if (AMESDLGetUIKitWindow(windows[i]) == uiwindow) {
            result = windows[i];
            break;
        }
    }
    SDL_free(windows);
    return result;
}

static SDL_Window *AMESDLPrimaryWindow(void) {
    if (!SDL_WasInit(SDL_INIT_VIDEO)) return NULL;
    SDL_Window *window = SDL_GetKeyboardFocus();
    if (!window) window = SDL_GetMouseFocus();
    if (window) return window;
    int count = 0;
    SDL_Window **windows = SDL_GetWindows(&count);
    window = count > 0 ? windows[0] : NULL;
    SDL_free(windows);
    return window;
}

static void AMESDLUpdateGrabState(void) {
    SurfaceViewController *controller = ameSDLController;
    UIWindow *uiwindow = ameSDLAttachedWindow;
    if (!controller || !uiwindow) return;
    SDL_Window *window = AMESDLWindowForUIKitWindow(uiwindow);
    if (!window) return;

    if (uiwindow.rootViewController.view != controller.view.superview) {
        [controller attachSDLControlsToWindow:uiwindow];
    }
    BOOL grabbing = SDL_GetWindowRelativeMouseMode(window);
    if (grabbing != (BOOL)isGrabbing) {
        isGrabbing = grabbing;
        [controller updateGrabState];
    }
}

static void AMESDLStartOverlayTimer(void) {
    [ameSDLOverlayTimer invalidate];
    ameSDLOverlayTimer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
        if (!ameSDLController || !ameSDLAttachedWindow) {
            [timer invalidate];
            return;
        }
        AMESDLUpdateGrabState();
    }];
    [NSRunLoop.mainRunLoop addTimer:ameSDLOverlayTimer forMode:NSRunLoopCommonModes];
}

void AMESDLRegisterSurfaceViewController(SurfaceViewController *controller) {
    ameSDLController = controller;
    if (ameSDLWindowObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:ameSDLWindowObserver];
    }
    ameSDLWindowObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:UIWindowDidBecomeKeyNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
            UIWindow *uiwindow = notification.object;
            if (!AMESDLWindowForUIKitWindow(uiwindow)) return;
            ameSDLAttachedWindow = uiwindow;
            [ameSDLController attachSDLControlsToWindow:uiwindow];
            AMESDLStartOverlayTimer();
        }];
}

void AMESDLHideWindows(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ AMESDLHideWindows(); });
        return;
    }
    if (!SDL_WasInit(SDL_INIT_VIDEO)) {
        [ameSDLOverlayTimer invalidate];
        ameSDLOverlayTimer = nil;
        ameSDLAttachedWindow = nil;
        return;
    }
    int count = 0;
    SDL_Window **windows = SDL_GetWindows(&count);
    for (int i = 0; i < count; i++) {
        AMESDLGetUIKitWindow(windows[i]).hidden = YES;
    }
    SDL_free(windows);
    [ameSDLOverlayTimer invalidate];
    ameSDLOverlayTimer = nil;
    ameSDLAttachedWindow = nil;
}

static SDL_Scancode AMESDLScancodeFromGLFW(int key) {
    if (key >= GLFW_KEY_A && key <= GLFW_KEY_Z) {
        return SDL_SCANCODE_A + key - GLFW_KEY_A;
    }
    if (key >= GLFW_KEY_1 && key <= GLFW_KEY_9) {
        return SDL_SCANCODE_1 + key - GLFW_KEY_1;
    }
    if (key >= GLFW_KEY_F1 && key <= GLFW_KEY_F12) {
        return SDL_SCANCODE_F1 + key - GLFW_KEY_F1;
    }
    if (key >= GLFW_KEY_F13 && key <= GLFW_KEY_F24) {
        return SDL_SCANCODE_F13 + key - GLFW_KEY_F13;
    }
    if (key >= GLFW_KEY_NUMPAD_0 && key <= GLFW_KEY_NUMPAD_9) {
        return SDL_SCANCODE_KP_0 + key - GLFW_KEY_NUMPAD_0;
    }

    switch (key) {
        case GLFW_KEY_SPACE: return SDL_SCANCODE_SPACE;
        case GLFW_KEY_APOSTROPHE: return SDL_SCANCODE_APOSTROPHE;
        case GLFW_KEY_COMMA: return SDL_SCANCODE_COMMA;
        case GLFW_KEY_MINUS: return SDL_SCANCODE_MINUS;
        case GLFW_KEY_PERIOD: return SDL_SCANCODE_PERIOD;
        case GLFW_KEY_SLASH: return SDL_SCANCODE_SLASH;
        case GLFW_KEY_0: return SDL_SCANCODE_0;
        case GLFW_KEY_SEMICOLON: return SDL_SCANCODE_SEMICOLON;
        case GLFW_KEY_EQUAL: return SDL_SCANCODE_EQUALS;
        case GLFW_KEY_LEFT_BRACKET: return SDL_SCANCODE_LEFTBRACKET;
        case GLFW_KEY_BACKSLASH: return SDL_SCANCODE_BACKSLASH;
        case GLFW_KEY_RIGHT_BRACKET: return SDL_SCANCODE_RIGHTBRACKET;
        case GLFW_KEY_GRAVE_ACCENT: return SDL_SCANCODE_GRAVE;
        case GLFW_KEY_WORLD_1: return SDL_SCANCODE_NONUSBACKSLASH;
        case GLFW_KEY_WORLD_2: return SDL_SCANCODE_INTERNATIONAL1;
        case GLFW_KEY_ESCAPE: return SDL_SCANCODE_ESCAPE;
        case GLFW_KEY_ENTER: return SDL_SCANCODE_RETURN;
        case GLFW_KEY_TAB: return SDL_SCANCODE_TAB;
        case GLFW_KEY_BACKSPACE: return SDL_SCANCODE_BACKSPACE;
        case GLFW_KEY_INSERT: return SDL_SCANCODE_INSERT;
        case GLFW_KEY_DELETE: return SDL_SCANCODE_DELETE;
        case GLFW_KEY_DPAD_RIGHT: return SDL_SCANCODE_RIGHT;
        case GLFW_KEY_DPAD_LEFT: return SDL_SCANCODE_LEFT;
        case GLFW_KEY_DPAD_DOWN: return SDL_SCANCODE_DOWN;
        case GLFW_KEY_DPAD_UP: return SDL_SCANCODE_UP;
        case GLFW_KEY_PAGE_UP: return SDL_SCANCODE_PAGEUP;
        case GLFW_KEY_PAGE_DOWN: return SDL_SCANCODE_PAGEDOWN;
        case GLFW_KEY_HOME: return SDL_SCANCODE_HOME;
        case GLFW_KEY_END: return SDL_SCANCODE_END;
        case GLFW_KEY_CAPS_LOCK: return SDL_SCANCODE_CAPSLOCK;
        case GLFW_KEY_SCROLL_LOCK: return SDL_SCANCODE_SCROLLLOCK;
        case GLFW_KEY_NUM_LOCK: return SDL_SCANCODE_NUMLOCKCLEAR;
        case GLFW_KEY_PRINT_SCREEN: return SDL_SCANCODE_PRINTSCREEN;
        case GLFW_KEY_PAUSE: return SDL_SCANCODE_PAUSE;
        case GLFW_KEY_NUMPAD_DECIMAL: return SDL_SCANCODE_KP_DECIMAL;
        case GLFW_KEY_NUMPAD_DIVIDE: return SDL_SCANCODE_KP_DIVIDE;
        case GLFW_KEY_NUMPAD_MULTIPLY: return SDL_SCANCODE_KP_MULTIPLY;
        case GLFW_KEY_NUMPAD_SUBTRACT: return SDL_SCANCODE_KP_MINUS;
        case GLFW_KEY_NUMPAD_ADD: return SDL_SCANCODE_KP_PLUS;
        case GLFW_KEY_NUMPAD_ENTER: return SDL_SCANCODE_KP_ENTER;
        case GLFW_KEY_NUMPAD_EQUAL: return SDL_SCANCODE_KP_EQUALS;
        case GLFW_KEY_LEFT_SHIFT: return SDL_SCANCODE_LSHIFT;
        case GLFW_KEY_LEFT_CONTROL: return SDL_SCANCODE_LCTRL;
        case GLFW_KEY_LEFT_ALT: return SDL_SCANCODE_LALT;
        case GLFW_KEY_LEFT_SUPER: return SDL_SCANCODE_LGUI;
        case GLFW_KEY_RIGHT_SHIFT: return SDL_SCANCODE_RSHIFT;
        case GLFW_KEY_RIGHT_CONTROL: return SDL_SCANCODE_RCTRL;
        case GLFW_KEY_RIGHT_ALT: return SDL_SCANCODE_RALT;
        case GLFW_KEY_RIGHT_SUPER: return SDL_SCANCODE_RGUI;
        case GLFW_KEY_MENU: return SDL_SCANCODE_MENU;
        default: return SDL_SCANCODE_UNKNOWN;
    }
}

BOOL AMESDLSendKey(int key, int scancode, int action, int mods) {
    SDL_Window *window = AMESDLPrimaryWindow();
    if (!window) return NO;
    SDL_Scancode sdlScancode = AMESDLScancodeFromGLFW(key);
    if (sdlScancode == SDL_SCANCODE_UNKNOWN) return YES;

    (void)mods; // SDL derives modifier state from the native key events.
    AMESDL_SendKey(SDL_GetTicksNS(), scancode, sdlScancode, action != ACTION_UP);
    return YES;
}

BOOL AMESDLSendChar(jchar codepoint) {
    SDL_Window *window = AMESDLPrimaryWindow();
    if (!window) return NO;
    if (!codepoint) return YES;

    char text[5] = {0};
    unsigned int value = codepoint;
    if (value >= 0xd800 && value <= 0xdbff) {
        ameSDLHighSurrogate = codepoint;
        return YES;
    }
    if (value >= 0xdc00 && value <= 0xdfff) {
        if (!ameSDLHighSurrogate) return YES;
        value = 0x10000 + ((ameSDLHighSurrogate - 0xd800) << 10) + (value - 0xdc00);
        ameSDLHighSurrogate = 0;
    } else {
        ameSDLHighSurrogate = 0;
    }
    if (value <= 0x7f) {
        text[0] = (char)value;
    } else if (value <= 0x7ff) {
        text[0] = (char)(0xc0 | (value >> 6));
        text[1] = (char)(0x80 | (value & 0x3f));
    } else if (value <= 0xffff) {
        text[0] = (char)(0xe0 | (value >> 12));
        text[1] = (char)(0x80 | ((value >> 6) & 0x3f));
        text[2] = (char)(0x80 | (value & 0x3f));
    } else {
        text[0] = (char)(0xf0 | (value >> 18));
        text[1] = (char)(0x80 | ((value >> 12) & 0x3f));
        text[2] = (char)(0x80 | ((value >> 6) & 0x3f));
        text[3] = (char)(0x80 | (value & 0x3f));
    }

    AMESDL_SendKeyboardText(text);
    return YES;
}

static void AMESDLGetInputScale(SDL_Window *window, float *scaleX, float *scaleY) {
    int width = 0, height = 0;
    SDL_GetWindowSize(window, &width, &height);
    *scaleX = windowWidth > 0 ? (float)width / windowWidth : 1.0f;
    *scaleY = windowHeight > 0 ? (float)height / windowHeight : 1.0f;
}

BOOL AMESDLSendCursorPos(char eventType, CGFloat x, CGFloat y) {
    SDL_Window *window = AMESDLPrimaryWindow();
    if (!window) return NO;
    float scaleX, scaleY;
    AMESDLGetInputScale(window, &scaleX, &scaleY);
    BOOL relative = SDL_GetWindowRelativeMouseMode(window) || eventType == ACTION_MOVE_MOTION;
    float deltaX = 0, deltaY = 0;

    if (relative) {
        if (eventType == ACTION_MOVE) {
            deltaX = (x - cLastX) * scaleX;
            deltaY = (y - cLastY) * scaleY;
        } else if (eventType == ACTION_MOVE_MOTION) {
            deltaX = x * scaleX;
            deltaY = y * scaleY;
        }
        AMESDL_SendMouseMotion(SDL_GetTicksNS(), window, true, deltaX, deltaY);
    } else {
        AMESDL_SendMouseMotion(SDL_GetTicksNS(), window, false, x * scaleX, y * scaleY);
    }
    return YES;
}

static Uint8 AMESDLMouseButtonFromGLFW(int button) {
    switch (button) {
        case GLFW_MOUSE_BUTTON_LEFT: return SDL_BUTTON_LEFT;
        case GLFW_MOUSE_BUTTON_MIDDLE: return SDL_BUTTON_MIDDLE;
        case GLFW_MOUSE_BUTTON_RIGHT: return SDL_BUTTON_RIGHT;
        default: return button >= 0 ? button + 1 : 0;
    }
}

BOOL AMESDLSendMouseButton(int button, int action) {
    SDL_Window *window = AMESDLPrimaryWindow();
    if (!window) return NO;
    Uint8 sdlButton = AMESDLMouseButtonFromGLFW(button);
    if (!sdlButton) return YES;
    AMESDL_SendMouseButton(SDL_GetTicksNS(), window, sdlButton, action != ACTION_UP);
    return YES;
}

BOOL AMESDLSendScroll(CGFloat xoffset, CGFloat yoffset) {
    SDL_Window *window = AMESDLPrimaryWindow();
    if (!window) return NO;
    AMESDL_SendMouseWheel(SDL_GetTicksNS(), window, xoffset, yoffset, SDL_MOUSEWHEEL_NORMAL);
    return YES;
}

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

#import "AmethystSDLInput.h"

// GLFW key codes (glfw3.h) -> SDL3 scancodes (USB HID usage page 0x07).
static int AmethystSDL_ScancodeFromGLFW(int key)
{
    if (key >= 'A' && key <= 'Z') return 4 + (key - 'A');
    if (key >= '1' && key <= '9') return 30 + (key - '1');
    if (key == '0') return 39;
    switch (key) {
        case 32: return 44;   // space
        case 39: return 52;   // apostrophe
        case 44: return 54;   // comma
        case 45: return 45;   // minus
        case 46: return 55;   // period
        case 47: return 56;   // slash
        case 59: return 51;   // semicolon
        case 61: return 46;   // equal
        case 91: return 47;   // left bracket
        case 92: return 49;   // backslash
        case 93: return 48;   // right bracket
        case 96: return 53;   // grave accent
        case 256: return 41;  // escape
        case 257: return 40;  // enter
        case 258: return 43;  // tab
        case 259: return 42;  // backspace
        case 260: return 73;  // insert
        case 261: return 76;  // delete
        case 262: return 79;  // right
        case 263: return 80;  // left
        case 264: return 81;  // down
        case 265: return 82;  // up
        case 266: return 75;  // page up
        case 267: return 78;  // page down
        case 268: return 74;  // home
        case 269: return 77;  // end
        case 280: return 57;  // caps lock
        case 281: return 71;  // scroll lock
        case 282: return 83;  // num lock
        case 283: return 70;  // print screen
        case 284: return 72;  // pause
        case 290: case 291: case 292: case 293: case 294:
        case 295: case 296: case 297: case 298: case 299:
        case 300: case 301:
            return 58 + (key - 290); // F1..F12
        case 302: case 303: case 304: case 305: case 306:
        case 307: case 308: case 309: case 310: case 311:
        case 312: case 313: case 314:
            return 104 + (key - 302); // F13..F25
        case 320: case 321: case 322: case 323: case 324:
        case 325: case 326: case 327: case 328: case 329:
            return (key == 320) ? 98 : 89 + (key - 321); // KP_0..KP_9
        case 330: return 99;  // KP decimal
        case 331: return 84;  // KP divide
        case 332: return 85;  // KP multiply
        case 333: return 86;  // KP subtract
        case 334: return 87;  // KP add
        case 335: return 88;  // KP enter
        case 336: return 103; // KP equal
        case 340: return 225; // left shift
        case 341: return 224; // left control
        case 342: return 226; // left alt
        case 343: return 227; // left super
        case 344: return 229; // right shift
        case 345: return 228; // right control
        case 346: return 230; // right alt
        case 347: return 231; // right super
        case 348: return 101; // menu
        default: return 0;
    }
}

typedef void (*AmethystSendKeyFn)(int, int);
typedef void (*AmethystSendTextFn)(const char *);
typedef void (*AmethystSendMouseMotionFn)(float, float, int);
typedef void (*AmethystSendMouseButtonFn)(int, int);
typedef void (*AmethystSendMouseWheelFn)(float, float);
typedef void (*AmethystSendWindowSizeFn)(int, int);

static void *amethystSDLHandle = NULL;
static AmethystSendKeyFn amethystSendKey = NULL;
static AmethystSendTextFn amethystSendText = NULL;
static AmethystSendMouseMotionFn amethystSendMouseMotion = NULL;
static AmethystSendMouseButtonFn amethystSendMouseButton = NULL;
static AmethystSendMouseWheelFn amethystSendMouseWheel = NULL;
static AmethystSendWindowSizeFn amethystSendWindowSize = NULL;
static BOOL amethystInputActive = NO;

BOOL AmethystSDL_InputActive(void)
{
    // Do not cache a negative result: touch events can arrive before
    // JavaLauncher sets AME_MC26 for the 26.x profile.
    if (!amethystInputActive) {
        const char *flag = getenv("AME_MC26");
        if (flag == NULL || flag[0] == '\0') {
            return NO;
        }
        amethystInputActive = YES;
        NSLog(@"[MC26] input check AME_MC26=%s -> enabling SDL input", flag);
        NSString *path = [NSString stringWithFormat:@"%@/Frameworks/lwjgl343/libSDL3.dylib",
                          NSBundle.mainBundle.bundlePath];
        amethystSDLHandle = dlopen(path.UTF8String, RTLD_NOW | RTLD_GLOBAL);
        if (amethystSDLHandle) {
            amethystSendKey = (AmethystSendKeyFn)dlsym(amethystSDLHandle, "AMETHYST_SendKey");
            amethystSendText = (AmethystSendTextFn)dlsym(amethystSDLHandle, "AMETHYST_SendText");
            amethystSendMouseMotion = (AmethystSendMouseMotionFn)dlsym(amethystSDLHandle, "AMETHYST_SendMouseMotion");
            amethystSendMouseButton = (AmethystSendMouseButtonFn)dlsym(amethystSDLHandle, "AMETHYST_SendMouseButton");
            amethystSendMouseWheel = (AmethystSendMouseWheelFn)dlsym(amethystSDLHandle, "AMETHYST_SendMouseWheel");
            amethystSendWindowSize = (AmethystSendWindowSizeFn)dlsym(amethystSDLHandle, "AMETHYST_SendWindowSize");
        }
        NSLog(@"[MC26] SDL input active=%d key=%p", amethystSendKey != NULL, (void *)amethystSendKey);
    }
    return amethystInputActive && amethystSendKey != NULL;
}

void AmethystSDL_SendKey(int glfwKey, int action, int mods)
{
    if (!AmethystSDL_InputActive()) {
        return;
    }
    int scancode = AmethystSDL_ScancodeFromGLFW(glfwKey);
    if (scancode <= 0) {
        return;
    }
    amethystSendKey(scancode, action != 0); // GLFW_RELEASE == 0
}

void AmethystSDL_SendChar(unsigned int codepoint)
{
    if (!AmethystSDL_InputActive() || !amethystSendText || codepoint == 0) {
        return;
    }
    char utf8[5] = {0, 0, 0, 0, 0};
    if (codepoint < 0x80) {
        utf8[0] = (char)codepoint;
    } else if (codepoint < 0x800) {
        utf8[0] = (char)(0xC0 | (codepoint >> 6));
        utf8[1] = (char)(0x80 | (codepoint & 0x3F));
    } else if (codepoint < 0x10000) {
        utf8[0] = (char)(0xE0 | (codepoint >> 12));
        utf8[1] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
        utf8[2] = (char)(0x80 | (codepoint & 0x3F));
    } else {
        utf8[0] = (char)(0xF0 | (codepoint >> 18));
        utf8[1] = (char)(0x80 | ((codepoint >> 12) & 0x3F));
        utf8[2] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
        utf8[3] = (char)(0x80 | (codepoint & 0x3F));
    }
    amethystSendText(utf8);
}

void AmethystSDL_SendMouseButton(int glfwButton, int action)
{
    if (!AmethystSDL_InputActive() || !amethystSendMouseButton) {
        return;
    }
    int sdlButton;
    if (glfwButton == 0) {
        sdlButton = 1; // left
    } else if (glfwButton == 1) {
        sdlButton = 3; // right
    } else if (glfwButton == 2) {
        sdlButton = 2; // middle
    } else {
        sdlButton = glfwButton + 1;
    }
    amethystSendMouseButton(sdlButton, action != 0);
}

void AmethystSDL_SendCursorPos(float x, float y, int relative)
{
    if (!AmethystSDL_InputActive() || !amethystSendMouseMotion) {
        return;
    }
    CGFloat scale = UIScreen.mainScreen.scale;
    if (scale <= 0) {
        scale = 1.0;
    }
    amethystSendMouseMotion(x * (float)scale, y * (float)scale, relative);
}

void AmethystSDL_SendScroll(float dx, float dy)
{
    if (!AmethystSDL_InputActive() || !amethystSendMouseWheel) {
        return;
    }
    // GLFW scroll: positive y is up; SDL: positive y scrolls down.
    amethystSendMouseWheel(dx, -dy);
}

void AmethystSDL_SendScreenSize(int width, int height)
{
    if (!AmethystSDL_InputActive() || !amethystSendWindowSize) {
        return;
    }
    amethystSendWindowSize(width, height);
}

/*
  Amethyst iOS SDL3 video driver - input injection.

  The Amethyst input bridge (touch controls, keyboard, mouse, controller) calls
  these helpers through libSDL3's exported symbols. They feed the normal SDL
  event queue and keyboard/mouse state, so Minecraft 26.x sees the same events
  it would get from a native SDL backend.
*/
#include "SDL_internal.h"

#ifdef SDL_VIDEO_DRIVER_AMETHYST

#include "SDL_amethystvideo.h"
#include "../../events/SDL_keyboard_c.h"
#include "../../events/SDL_mouse_c.h"
#include "../../events/SDL_windowevents_c.h"

static SDL_Window *AMETHYST_input_window = NULL;

void AMETHYST_SetInputWindow(SDL_Window *window)
{
    AMETHYST_input_window = window;
}

static bool AMETHYST_HasInputWindow(void)
{
    return AMETHYST_input_window != NULL;
}

void AMETHYST_NotifyWindowShown(void)
{
    if (!AMETHYST_HasInputWindow()) {
        return;
    }
    SDL_SendWindowEvent(AMETHYST_input_window, SDL_EVENT_WINDOW_SHOWN, 0, 0);
    SDL_SendWindowEvent(AMETHYST_input_window, SDL_EVENT_WINDOW_FOCUS_GAINED, 0, 0);
}

__attribute__((visibility("default")))
void AMETHYST_SendKey(int scancode, int down)
{
    if (!AMETHYST_HasInputWindow() || scancode <= SDL_SCANCODE_UNKNOWN || scancode >= SDL_SCANCODE_COUNT) {
        return;
    }
    SDL_SendKeyboardKey(SDL_GetTicksNS(), SDL_DEFAULT_KEYBOARD_ID, 0,
                        (SDL_Scancode)scancode, down != 0);
}

__attribute__((visibility("default")))
void AMETHYST_SendText(const char *text)
{
    if (!AMETHYST_HasInputWindow() || !text || !*text) {
        return;
    }
    SDL_SendKeyboardText(text);
}

__attribute__((visibility("default")))
void AMETHYST_SendMouseMotion(float x, float y, int relative)
{
    if (!AMETHYST_HasInputWindow()) {
        return;
    }
    SDL_SendMouseMotion(SDL_GetTicksNS(), AMETHYST_input_window, SDL_DEFAULT_MOUSE_ID,
                        relative != 0, x, y);
}

__attribute__((visibility("default")))
void AMETHYST_SendMouseButton(int button, int down)
{
    if (!AMETHYST_HasInputWindow() || button <= 0) {
        return;
    }
    SDL_SendMouseButton(SDL_GetTicksNS(), AMETHYST_input_window, SDL_DEFAULT_MOUSE_ID,
                        (Uint8)button, down != 0);
}

__attribute__((visibility("default")))
void AMETHYST_SendMouseWheel(float x, float y)
{
    if (!AMETHYST_HasInputWindow()) {
        return;
    }
    SDL_SendMouseWheel(SDL_GetTicksNS(), AMETHYST_input_window, SDL_DEFAULT_MOUSE_ID,
                       x, y, SDL_MOUSEWHEEL_NORMAL);
}

__attribute__((visibility("default")))
void AMETHYST_SendWindowSize(int w, int h)
{
    if (!AMETHYST_HasInputWindow() || w <= 0 || h <= 0) {
        return;
    }
    SDL_SendWindowEvent(AMETHYST_input_window, SDL_EVENT_WINDOW_RESIZED, w, h);
    SDL_SendWindowEvent(AMETHYST_input_window, SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED, w, h);
}

#endif /* SDL_VIDEO_DRIVER_AMETHYST */

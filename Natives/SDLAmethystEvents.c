// Project-owned entry points compiled into SDL3. These use SDL's native event
// senders so queued events and SDL's keyboard/mouse state stay in sync.
#include "SDL_internal.h"
#include "events/SDL_keyboard_c.h"
#include "events/SDL_mouse_c.h"

SDL_DECLSPEC bool SDLCALL AMESDL_SendKey(Uint64 timestamp, int rawcode, SDL_Scancode scancode, bool down)
{
    return SDL_SendKeyboardKey(timestamp, SDL_GLOBAL_KEYBOARD_ID, rawcode, scancode, down);
}

SDL_DECLSPEC void SDLCALL AMESDL_SendKeyboardText(const char *text)
{
    SDL_SendKeyboardText(text);
}

SDL_DECLSPEC void SDLCALL AMESDL_SendMouseMotion(Uint64 timestamp, SDL_Window *window, bool relative, float x, float y)
{
    SDL_SendMouseMotion(timestamp, window, SDL_GLOBAL_MOUSE_ID, relative, x, y);
}

SDL_DECLSPEC void SDLCALL AMESDL_SendMouseButton(Uint64 timestamp, SDL_Window *window, Uint8 button, bool down)
{
    SDL_SendMouseButton(timestamp, window, SDL_GLOBAL_MOUSE_ID, button, down);
}

SDL_DECLSPEC void SDLCALL AMESDL_SendMouseWheel(Uint64 timestamp, SDL_Window *window, float x, float y, SDL_MouseWheelDirection direction)
{
    SDL_SendMouseWheel(timestamp, window, SDL_GLOBAL_MOUSE_ID, x, y, direction);
}

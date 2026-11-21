/*
  Amethyst iOS SDL3 video driver - events and clipboard.

  Events are injected by the Amethyst input bridge with SDL_PushEvent() from
  the host side, so the driver's pump is a no-op. The SDL core keeps keyboard
  and mouse state in sync from those pushed events.
*/
#include "SDL_internal.h"

#ifdef SDL_VIDEO_DRIVER_AMETHYST

#include "SDL_amethystvideo.h"

void AMETHYST_PumpEvents(SDL_VideoDevice *_this)
{
}

bool AMETHYST_SetClipboardText(SDL_VideoDevice *_this, const char *text)
{
    if (AMETHYST_host && AMETHYST_host->setClipboardText) {
        return AMETHYST_host->setClipboardText(text);
    }
    return false;
}

char *AMETHYST_GetClipboardText(SDL_VideoDevice *_this)
{
    if (AMETHYST_host && AMETHYST_host->getClipboardText) {
        const char *text = AMETHYST_host->getClipboardText();
        if (text) {
            return SDL_strdup(text);
        }
    }
    return NULL;
}

#endif /* SDL_VIDEO_DRIVER_AMETHYST */

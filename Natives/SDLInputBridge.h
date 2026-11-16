#pragma once

#import <UIKit/UIKit.h>
#include "jni.h"

@class SurfaceViewController;

// Installs the UIKit overlay observer used by SDL-based Minecraft versions.
void AMESDLRegisterSurfaceViewController(SurfaceViewController *controller);
void AMESDLHideWindows(void);

// These functions return YES when the event was consumed by an SDL window.
// A NO result means that the legacy GLFW input path should be used instead.
BOOL AMESDLSendChar(jchar codepoint);
BOOL AMESDLSendCursorPos(char event, CGFloat x, CGFloat y);
BOOL AMESDLSendKey(int key, int scancode, int action, int mods);
BOOL AMESDLSendMouseButton(int button, int action);
BOOL AMESDLSendScroll(CGFloat xoffset, CGFloat yoffset);

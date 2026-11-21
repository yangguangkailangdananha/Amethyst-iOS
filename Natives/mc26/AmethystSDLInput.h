#import <Foundation/Foundation.h>

// Forwards Amethyst input events (touch controls, keyboard, mouse, controller)
// to the bundled SDL3 runtime for Minecraft 26.x. No-ops for older versions.
void AmethystSDL_SendKey(int glfwKey, int action, int mods);
void AmethystSDL_SendChar(unsigned int codepoint);
void AmethystSDL_SendMouseButton(int glfwButton, int action);
void AmethystSDL_SendCursorPos(float x, float y, int relative);
void AmethystSDL_SendScroll(float dx, float dy);
void AmethystSDL_SendScreenSize(int width, int height);
BOOL AmethystSDL_InputActive(void);

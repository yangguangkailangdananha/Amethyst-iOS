# -*- coding: utf-8 -*-
"""Patch the official SDL3 source tree with Amethyst's iOS video driver.

Usage: python patch_sdl.py <sdl_source_dir> <driver_source_dir>

The patch is idempotent and limited to:
  * copying src/video/amethyst/*.c/h from the Amethyst repo
  * registering AMETHYST_bootstrap in src/video/SDL_video.c
  * adding the CMake option/source list and the build-config define
"""
import os
import shutil
import sys


def patch_file(path, old, new, marker):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if marker in text:
        print(f"  already patched: {os.path.basename(path)}")
        return
    if old not in text:
        raise SystemExit(f"anchor not found in {path}: {old[:80]!r}")
    text = text.replace(old, new, 1)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"  patched: {os.path.basename(path)}")


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    sdl, driver = sys.argv[1], sys.argv[2]
    dst = os.path.join(sdl, "src", "video", "amethyst")
    os.makedirs(dst, exist_ok=True)
    for name in sorted(os.listdir(driver)):
        if name.endswith((".c", ".h")):
            shutil.copyfile(os.path.join(driver, name), os.path.join(dst, name))
            print("  copied:", name)

    # 1) bootstrap registration
    patch_file(
        os.path.join(sdl, "src", "video", "SDL_video.c"),
        "static VideoBootStrap *bootstrap[] = {\n",
        "#ifdef SDL_VIDEO_DRIVER_AMETHYST\n"
        "extern VideoBootStrap AMETHYST_bootstrap;\n"
        "#endif\n\n"
        "static VideoBootStrap *bootstrap[] = {\n"
        "#ifdef SDL_VIDEO_DRIVER_AMETHYST\n"
        "    &AMETHYST_bootstrap,\n"
        "#endif\n",
        "AMETHYST_bootstrap",
    )

    # 2) LWJGL/Minecraft call SDL_Init without SDL_main; make SDL accept that.
    patch_file(
        os.path.join(sdl, "src", "SDL.c"),
        "    if (!SDL_MainIsReady) {\n"
        "        return SDL_SetError(\"Application didn't initialize properly, did you include SDL_main.h in the file containing your main() function?\");\n"
        "    }\n",
        "    if (!SDL_MainIsReady) {\n"
        "        SDL_SetMainReady();\n"
        "    }\n",
        "SDL_SetMainReady();",
    )

    # 3) CMake option
    patch_file(
        os.path.join(sdl, "CMakeLists.txt"),
        'set_option(SDL_OFFSCREEN           "Use offscreen video driver" ON)\n',
        'set_option(SDL_OFFSCREEN           "Use offscreen video driver" ON)\n'
        'set_option(SDL_AMETHYST            "Use Amethyst iOS video driver" OFF)\n',
        "SDL_AMETHYST",
    )

    # 3) CMake source list (after the offscreen block in the video section)
    patch_file(
        os.path.join(sdl, "CMakeLists.txt"),
        "    set(HAVE_OFFSCREEN TRUE)\n"
        "    set(HAVE_SDL_VIDEO TRUE)\n"
        "  endif()\n"
        "endif()\n"
        "\n"
        "sdl_glob_sources(${SDL3_SOURCE_DIR}/src/tray/*.c)\n",
        "    set(HAVE_OFFSCREEN TRUE)\n"
        "    set(HAVE_SDL_VIDEO TRUE)\n"
        "  endif()\n"
        "  if(SDL_AMETHYST)\n"
        "    set(SDL_VIDEO_DRIVER_AMETHYST 1)\n"
        "    sdl_glob_sources(\n"
        '      "${SDL3_SOURCE_DIR}/src/video/amethyst/*.c"\n'
        '      "${SDL3_SOURCE_DIR}/src/video/amethyst/*.h"\n'
        "    )\n"
        "    set(HAVE_SDL_VIDEO TRUE)\n"
        "  endif()\n"
        "endif()\n"
        "\n"
        "sdl_glob_sources(${SDL3_SOURCE_DIR}/src/tray/*.c)\n",
        "src/video/amethyst",
    )

    # 4) build config define
    patch_file(
        os.path.join(sdl, "include", "build_config", "SDL_build_config.h.cmake"),
        "#cmakedefine SDL_VIDEO_DRIVER_OFFSCREEN 1\n",
        "#cmakedefine SDL_VIDEO_DRIVER_OFFSCREEN 1\n"
        "#cmakedefine SDL_VIDEO_DRIVER_AMETHYST 1\n",
        "SDL_VIDEO_DRIVER_AMETHYST",
    )

    print("SDL patched for the Amethyst video driver")


if __name__ == "__main__":
    main()

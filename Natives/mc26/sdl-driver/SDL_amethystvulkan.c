/*
  Amethyst iOS SDL3 video driver - Vulkan support (MoltenVK).

  Mirrors SDL's UIKit Vulkan backend, but borrows the CAMetalLayer from the
  Amethyst game surface instead of creating a new UIView. This lets Minecraft
  26.x use its Vulkan renderer through MoltenVK (libMoltenVK.dylib), the same
  way the Android build uses the native Vulkan driver.
*/
#include "SDL_internal.h"

#ifdef SDL_VIDEO_DRIVER_AMETHYST

#ifdef SDL_VIDEO_VULKAN

#include "../SDL_vulkan_internal.h"
#include "SDL_amethystvideo.h"

bool AMETHYST_Vulkan_LoadLibrary(SDL_VideoDevice *_this, const char *path)
{
    VkExtensionProperties *extensions = NULL;
    Uint32 extensionCount = 0;
    bool hasSurfaceExtension = false;
    bool hasMetalSurfaceExtension = false;
    PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr = NULL;

    if (_this->vulkan_config.loader_handle) {
        return SDL_SetError("Vulkan loader is already loaded");
    }

    if (!path && AMETHYST_host && AMETHYST_host->getVulkanLibraryPath) {
        path = AMETHYST_host->getVulkanLibraryPath();
    }
    if (!path) {
        path = "libMoltenVK.dylib";
    }

    _this->vulkan_config.loader_handle = SDL_LoadObject(path);
    if (!_this->vulkan_config.loader_handle) {
        SDL_Log("[Amethyst] Vulkan loader FAILED: %s", path);
        return SDL_SetError("Failed to load Vulkan loader: %s", path);
    }
    SDL_Log("[Amethyst] Vulkan loader loaded: %s", path);
    SDL_strlcpy(_this->vulkan_config.loader_path, path,
                SDL_arraysize(_this->vulkan_config.loader_path));

    vkGetInstanceProcAddr = (PFN_vkGetInstanceProcAddr)SDL_LoadFunction(
        _this->vulkan_config.loader_handle, "vkGetInstanceProcAddr");
    if (!vkGetInstanceProcAddr) {
        goto fail;
    }

    _this->vulkan_config.vkGetInstanceProcAddr = (SDL_FunctionPointer)vkGetInstanceProcAddr;
    _this->vulkan_config.vkEnumerateInstanceExtensionProperties =
        (SDL_FunctionPointer)vkGetInstanceProcAddr(
            VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties");
    if (!_this->vulkan_config.vkEnumerateInstanceExtensionProperties) {
        SDL_SetError("No vkEnumerateInstanceExtensionProperties found");
        goto fail;
    }

    extensions = SDL_Vulkan_CreateInstanceExtensionsList(
        (PFN_vkEnumerateInstanceExtensionProperties)
            _this->vulkan_config.vkEnumerateInstanceExtensionProperties,
        &extensionCount);
    if (!extensions) {
        goto fail;
    }

    for (Uint32 i = 0; i < extensionCount; i++) {
        if (SDL_strcmp(VK_KHR_SURFACE_EXTENSION_NAME, extensions[i].extensionName) == 0) {
            hasSurfaceExtension = true;
        } else if (SDL_strcmp(VK_EXT_METAL_SURFACE_EXTENSION_NAME, extensions[i].extensionName) == 0) {
            hasMetalSurfaceExtension = true;
        }
    }
    SDL_free(extensions);

    if (!hasSurfaceExtension || !hasMetalSurfaceExtension) {
        SDL_SetError("MoltenVK does not expose VK_KHR_surface + VK_EXT_metal_surface");
        goto fail;
    }
    return true;

fail:
    if (_this->vulkan_config.loader_handle) {
        SDL_UnloadObject(_this->vulkan_config.loader_handle);
        _this->vulkan_config.loader_handle = NULL;
    }
    return false;
}

void AMETHYST_Vulkan_UnloadLibrary(SDL_VideoDevice *_this)
{
    if (_this->vulkan_config.loader_handle) {
        SDL_UnloadObject(_this->vulkan_config.loader_handle);
        _this->vulkan_config.loader_handle = NULL;
    }
}

char const *const *AMETHYST_Vulkan_GetInstanceExtensions(SDL_VideoDevice *_this, Uint32 *count)
{
    static const char *const extensions[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME
    };
    if (count) {
        *count = SDL_arraysize(extensions);
    }
    return extensions;
}

bool AMETHYST_Vulkan_CreateSurface(SDL_VideoDevice *_this, SDL_Window *window,
                                  VkInstance instance,
                                  const struct VkAllocationCallbacks *allocator,
                                  VkSurfaceKHR *surface)
{
    PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr =
        (PFN_vkGetInstanceProcAddr)_this->vulkan_config.vkGetInstanceProcAddr;
    PFN_vkCreateMetalSurfaceEXT vkCreateMetalSurfaceEXT;
    void *layer;
    VkResult result;
    VkMetalSurfaceCreateInfoEXT createInfo;

    if (!_this->vulkan_config.loader_handle) {
        return SDL_SetError("Vulkan is not loaded");
    }
    if (!AMETHYST_host || !AMETHYST_host->getMetalLayer) {
        return SDL_SetError("Amethyst host has no Metal layer");
    }

    vkCreateMetalSurfaceEXT = (PFN_vkCreateMetalSurfaceEXT)
        vkGetInstanceProcAddr(instance, "vkCreateMetalSurfaceEXT");
    if (!vkCreateMetalSurfaceEXT) {
        return SDL_SetError("vkCreateMetalSurfaceEXT is not available");
    }

    layer = AMETHYST_host->getMetalLayer();
    if (!layer) {
        return SDL_SetError("Amethyst surface has no CAMetalLayer");
    }

    SDL_zero(createInfo);
    createInfo.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    createInfo.pNext = NULL;
    createInfo.flags = 0;
    createInfo.pLayer = (const CAMetalLayer *)layer;

    result = vkCreateMetalSurfaceEXT(instance, &createInfo, allocator, surface);
    if (result != VK_SUCCESS) {
        SDL_Log("[Amethyst] vkCreateMetalSurfaceEXT failed: %d (layer=%p)", (int)result, layer);
        return SDL_SetError("vkCreateMetalSurfaceEXT failed: %d", (int)result);
    }
    SDL_Log("[Amethyst] Vulkan surface created: %p (layer=%p)", (void *)(uintptr_t)*surface, layer);
    return true;
}

void AMETHYST_Vulkan_DestroySurface(SDL_VideoDevice *_this, VkInstance instance,
                                   VkSurfaceKHR surface,
                                   const struct VkAllocationCallbacks *allocator)
{
    if (_this->vulkan_config.loader_handle) {
        SDL_Vulkan_DestroySurface_Internal(
            _this->vulkan_config.vkGetInstanceProcAddr, instance, surface, allocator);
    }
}

bool AMETHYST_Vulkan_GetPresentationSupport(SDL_VideoDevice *_this, VkInstance instance,
                                           VkPhysicalDevice physicalDevice,
                                           Uint32 queueFamilyIndex)
{
    // MoltenVK presents through Metal; every queue family is display capable.
    return true;
}

void AMETHYST_InstallVulkan(SDL_VideoDevice *device)
{
    device->Vulkan_LoadLibrary = AMETHYST_Vulkan_LoadLibrary;
    device->Vulkan_UnloadLibrary = AMETHYST_Vulkan_UnloadLibrary;
    device->Vulkan_GetInstanceExtensions = AMETHYST_Vulkan_GetInstanceExtensions;
    device->Vulkan_CreateSurface = AMETHYST_Vulkan_CreateSurface;
    device->Vulkan_DestroySurface = AMETHYST_Vulkan_DestroySurface;
    device->Vulkan_GetPresentationSupport = AMETHYST_Vulkan_GetPresentationSupport;
}

#endif /* SDL_VIDEO_VULKAN */
#endif /* SDL_VIDEO_DRIVER_AMETHYST */

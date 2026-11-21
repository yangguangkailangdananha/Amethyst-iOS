# Amethyst iOS 支持 Minecraft 26.x（SDL3）的可行方案调研

> 调研对象：官方 Minecraft **26.3**（2026-09-15 发布，当前 latest release；26.4-snapshot-7 为 latest snapshot）
> 分析数据：`D:\DeepSeek\research\amethyst\mc\client-26.3.jar`（官方客户端，41 MB）
> 结论文件：`research/amethyst/mc26_sdl_api.txt`、`mc26_lwjgl_gap.txt`

## 1. 结论（先说结果）

> **2026-11-11 更新：已选定路线 B（Android 同款原生 SDL3 方案）。** 本文档保留路线对比，并在 §7 给出 iOS 的实施计划。

**路线 B（原生 SDL3）：**

- 引入官方 **SDL3**（`release-3.4.20`）为 iOS arm64 构建 `libSDL3.dylib`。
- 引入官方 **LWJGL 3.4.3** Java 绑定（`lwjgl-3.4.3.jar`、`lwjgl-sdl-3.4.3.jar` 等），并为 iOS 构建对应的原生模块（`liblwjgl.dylib`、`liblwjgl_sdl.dylib`、`liblwjgl_opengl.dylib` …）。
- 窗口/事件层：参考 Amethyst-Android 的 `SDLSurface + SDLActivity.externalInitialize` 思路，为 iOS 编写/适配 SDL video 层，复用 Amethyst 的 `GameSurfaceView`、EGL 桥与输入桥；或让 SDL 先以自带 UIKit 窗口做 bring-up，再逐步接入。

**路线 A（纯 Java shim）** 作为低成本实验保留：只覆盖 37 个 SDL 类 / 147 个成员，但受 LWJGL `Struct`/`CallbackI` 继承体系限制（见下），不作为最终方案。

依据（本次实测/调研数据，非估算）：

- 官方 26.3 客户端只用到 **37 个 `org.lwjgl.sdl.*` 类、147 个成员**（`mc26_sdl_api.txt`）。
- 与当前内置 LWJGL **3.3.3** 对比，MC 26.3 引用的其它 `org.lwjgl.*` 仅缺 **5 个类 + 3 个成员**，且集中在 Vulkan/SPIRV-Cross/OpenAL SOFT 路径（`mc26_lwjgl_gap.txt`）。
- **但**：用 `javap` 检查官方 `lwjgl-sdl-3.4.3.jar` 发现，MC 的字节码是按 **LWJGL 的 `Struct`/`NativeResource`/`CallbackI` 继承体系**编译的，例如 `SDL_MessageBoxButtonData$Buffer.get(I)` 的返回类型是 `org.lwjgl.system.Struct`，`SDL_Event` 继承 `Struct` 并实现 `NativeResource`。纯 Java shim 必须复刻这些继承关系（或至少提供同签名方法），否则会在解析阶段抛 `NoSuchMethodError`/`IncompatibleClassChangeError`——这是路线 A 的主要技术风险。
- Android 端已经跑通路线 B：`Amethyst-Android` 含 `libs/SDL-release.aar`、`libs/lwjgl-3.4.1-natives-release.aar`、`assets/components/lwjgl3/3.4.1/lwjgl-sdl.jar`、`jni/include/SDL3`。

## 2. 现有 iOS 图形/输入栈回顾

### 2.1 其它项目是怎么做的（2026-11-11 调研）

| 项目 | 26.x 支持 | 做法 |
|---|---|---|
| **Amethyst-Android**（活跃，2026-11-08 仍在提交） | ✅ 已支持 | **路线 A（原生 SDL3）**：仓库内含 `app_pojavlauncher/libs/SDL-release.aar`（SDL3 Android 原生库 + `org.libsdl.app` Java 层）、`libs/lwjgl-3.4.1-natives-release.aar`、`assets/components/lwjgl3/3.4.1/lwjgl-sdl.jar`（官方 LWJGL SDL 绑定）、`src/main/jni/include/SDL3/*` 头文件 |
| PojavLauncher（Android，2025-09） | ❌ | 无任何 SDL 相关文件，仍是 GLFW |
| PojavLauncher_iOS / CelloSerenity 等 iOS fork | ❌ | `JavaApp/libs/lwjgl` 只有 GLFW 版，无 SDL |
| Amethyst-iOS 上游 | ❌ | issue #318/#332/#355 未解决；PR #329/#357 尝试后关闭 |

结论：Android 已经验证了“官方 `lwjgl-sdl` 绑定 + 原生 SDL3”这条路可行；iOS 端若要照搬，需要
**为 iOS 编译 SDL3（`libSDL3.dylib`）+ 用 PojavLauncherTeam/lwjgl3 fork 编译出 3.4.x 的 iOS 原生库（`liblwjgl_sdl.dylib` 等）**，
并适配 SDL3 的 iOS 窗口/事件生命周期（SDL3 会自己创建 `UIWindow/UIView`，与 Amethyst 现有 UIKit 桥冲突，需要重写窗口层）。
这正是本方案把路线 A 列为“高工作量”的原因。

### 2.2 本项目的现有栈

```
Minecraft (Java)
   ├─ 1.21.11 及更早： org.lwjgl.glfw.*  ── Java 实现（JavaApp/src/lwjgl/org/lwjgl/glfw/GLFW.java）
   │                                        └─ JNI → liblwjgl.dylib → UIKit 事件/GL 表面
   ├─ 26.x：            org.lwjgl.sdl.*  ← 当前不存在，直接 NoClassDefFoundError
   └─ 渲染：            MobileGlues / ANGLE(metalangle) / gl4es / Zink（GL 调用经 libgl4es_114.dylib 等）
```

关键点：`JavaApp/src/lwjgl/org/lwjgl/glfw/GLFW.java` 已经是**纯 Java 的 GLFW 兼容层**（1360 行），窗口创建、`glfwPollEvents`、键鼠回调、剪贴板都通过 `liblwjgl.dylib` 的 JNI 桥实现。SDL3 shim 可以直接调用这些 Java 方法，把 SDL 语义翻译成 GLFW 语义，从而完全复用现有原生代码。

> 参考数据：官方 `lwjgl-sdl-3.4.3.jar` 已下载到 `research/amethyst/lwjgl-sdl-3.4.3.jar`，用于提取 SDL3 常量/结构签名（`research/amethyst/sdl_constants.txt`），保证 shim 返回的 event type、window flag、GL 属性值与 MC 26.3 的期望一致。

## 3. 26.3 实际使用的 SDL API（按调用量排序，节选）

| 类 | 成员数 | 典型函数 |
|---|---|---|
| `SDLVideo` | 39 | `SDL_CreateWindow`、`SDL_GL_CreateContext`、`SDL_GL_MakeCurrent`、`SDL_GL_SwapWindow`、`SDL_GetWindowSizeInPixels`、`SDL_SetWindowFullscreen`… |
| `SDL_Event` | 12 | `SDL_PollEvent` 的参数载体（`type()`、`key()`、`motion()`、`wheel()`、`button()`、`text()`…） |
| `SDLKeyboard` | 8 | `SDL_GetKeyboardState`、`SDL_GetModState`、`SDL_StartTextInput`、`SDL_GetKeyFromScancode`… |
| `SDLMouse` | 7 | `SDL_GetMouseState`、`SDL_SetWindowRelativeMouseMode`、`SDL_WarpMouseInWindow`… |
| `SDLEvents` | 4 | `SDL_PollEvent`、`SDL_PumpEvents`、`SDL_FlushEvents`、`SDL_GetWindowFromEvent` |
| `SDLInit` | 3 | `SDL_Init`、`SDL_Quit`、`SDL_SetAppMetadataProperty` |
| 其余 31 个类 | 74 | 结构体字段访问（`SDL_DisplayMode`、`SDL_Rect`、`SDL_MouseMotionEvent`…）、剪贴板、消息框、定时、日志、Surface、Vulkan |

完整清单见 `research/amethyst/mc26_sdl_api.txt`（按类分组，含 JVM 描述符）。

## 4. Shim 设计

### 4.1 目录与构建

```
JavaApp/src/lwjgl/org/lwjgl/sdl/
    SDL.java                     // getLibrary() → 返回一个假 SharedLibrary
    SDLInit.java                 // SDL_Init/Quit
    SDLVideo.java                // 窗口 + GL 上下文
    SDLEvents.java / SDL_Event.java (+各事件结构)
    SDLKeyboard.java / SDLMouse.java / SDLClipboard.java
    SDLTimer.java / SDLMisc.java / SDLError.java / SDLHints.java
    SDLMessageBox*.java / SDLSurface.java / SDL_DisplayMode.java / SDL_Rect.java
    SDLVulkan.java               // 可选：Vulkan 不可用时返回 false
```

现有构建脚本 `JavaApp/Makefile` 会按 `src/lwjgl/**` 自动编译并打进 `lwjgl.jar`（`find $(SOURCEDIR) -name '*.java'`），因此**无需改构建系统**。

### 4.2 核心映射表

| SDL3 | 实现（调用现有 Java GLFW 层） |
|---|---|
| `SDL_Init(flags)` | `GLFW.glfwInit()`（现有实现已绑定 iOS 原生初始化） |
| `SDL_CreateWindow(title,w,h,flags)` | `GLFW.glfwCreateWindow(w,h,title,0,0)`，保存 window 句柄；同时注册 GLFW 回调用于生成 SDL 事件 |
| `SDL_GL_CreateContext(win)` | 返回同一个 window 句柄（iOS 的 GL 表面在窗口创建时已绑定） |
| `SDL_GL_MakeCurrent(win,ctx)` | `GLFW.glfwMakeContextCurrent(win)` |
| `SDL_GL_SwapWindow(win)` | `GLFW.glfwSwapBuffers(win)` |
| `SDL_GL_SetSwapInterval(v)` | `GLFW.glfwSwapInterval(v)` |
| `SDL_GL_SetAttribute/GetAttribute` | 记录到 Map，必要时映射 GLFW window hints（`GLFW_CONTEXT_VERSION_*` 等） |
| `SDL_GL_GetProcAddress(name)` | `GLFW.glfwGetProcAddress(name)`（若 Java 层未暴露，可返回 0，GL 绑定由 LWJGL 自身提供） |
| `SDL_PollEvent(out)` | 先 `GLFW.glfwPollEvents()`，再从 Java 事件队列取一条填入 `SDL_Event` |
| `SDL_GetKeyboardState()` | 由按键回调维护的 512 字节数组 |
| `SDL_GetModState()` | 由按键回调维护的修饰键位图 |
| `SDL_GetMouseState(x,y)` / `WarpMouseInWindow` | 复用 `glfwGetCursorPos` / `glfwSetCursorPos` |
| `SDL_SetWindowRelativeMouseMode` | `GLFW.glfwSetInputMode(GLFW_CURSOR, GLFW_CURSOR_DISABLED/NORMAL)` |
| 剪贴板 `SDL_Set/GetClipboardText` | 现有 `CallbackBridge.nativeClipboard`（GLFW 层已有实现） |
| `SDL_GetTicksNS` | `System.nanoTime()` |
| `SDL_ShowMessageBox` / `SDL_ShowSimpleMessageBox` | 打印到日志 + 现有 `showDialog`（可选） |
| `SDL_Vulkan_*` | 返回 false/0（Vulkan 渲染路径暂不支持；OpenGL 路径不受影响） |
| `SDL_CreateSurfaceFrom/SetWindowIcon` | 最小实现（窗口图标在 iOS 上无效） |

### 4.3 事件结构体

SDL 结构体在 shim 内用**纯 Java 字段**表示即可：MC 只会通过 `SDL_Event.key()/motion()/...` 等访问器读取，且 `SDL_PollEvent` 由 shim 填充，无需真实 native 内存布局。`malloc(MemoryStack)` 静态方法返回新对象，`close()` 置空。这样完全避开 `MemoryStack`/`Struct` 的本地内存细节。

### 4.4 与现有版本的隔离

- shim 类只在 MC 调用 `org.lwjgl.sdl.*` 时加载；对 1.21.11 及更早版本**没有任何影响**。
- 版本放行逻辑已存在：`MinecraftResourceUtils.unsupportedReasonForVersionJSON:` 在检测到 `org.lwjgl:lwjgl-sdl` 时拒绝启动。可在 shim 完成并验证后，把 26.x 的 `requiresSDL` 分支改为“检测到 shim 已内置则放行”。
- 建议在独立分支 `feature/mc26-sdl` 开发，main 分支保持现状可玩版本不变。

## 5. 风险与验证里程碑

| 风险 | 说明 | 缓解 |
|---|---|---|
| GL 版本/Profile 不匹配 | 26.x 可能请求 OpenGL 3.2+ core；ANGE/MobileGlues 能力需实测 | 先打印 `SDL_GL_SetAttribute` 请求值；必要时映射到现有 window hints |
| 事件语义差异 | SDL scancode/keycode 与 GLFW keycode 不同（`SDL_GetKeyFromScancode`、`SDL_GetKeyboardState` 索引） | 建立 SDL scancode ↔ GLFW key 映射表（可从 SDL3 头文件生成） |
| Vulkan 路径 | 26.x 默认可能检测 Vulkan；iOS 只能走 GL | `SDL_Vulkan_LoadLibrary` 返回 false，让 MC 回退 GL |
| 缺少 spvc/Vulkan 类 | 仅 Vulkan/着色器路径用到 | 提供空壳类（加载时安全），或走 GL 时不触发 |
| 无法真机验证（当前环境） | Windows 无法编译/运行 | 在 GitHub Actions 出包 + 真机冒烟测试；先验证“能进标题界面” |

阶段计划：
1. **P1（可编译）**：生成 37 个类/147 成员的骨架，保证 26.3 能完成类加载（无 NoClassDefFoundError）。
2. **P2（能建窗）**：实现 `SDL_Init/CreateWindow/GL_*`，确认标题界面能渲染。
3. **P3（能操作）**：实现事件/键盘/鼠标/剪贴板，确认可以点击菜单、进入世界。
4. **P4（回归）**：1.21.11 回归测试 + 放行 26.x 的版本检测。

## 6. 备选路线对比

| 路线 | 工作量 | 风险 | 结论 |
|---|---|---|---|
| A. 原生 SDL3 + 官方 lwjgl-sdl（Android 同款做法） | 中高：引入 `SDL3.xcframework`（官方 `SDL3-3.4.20.dmg` 含 iOS 切片）、为 iOS 编译 LWJGL 3.4.x 的 `liblwjgl_sdl.dylib`、适配 SDL3 的 iOS 窗口/事件 | 中：原生构建链与窗口层重写 | **阶段 2 生产路线**，有 Android 现成组件可参照 |
| **B. Java 层 SDL shim** | 纯 Java，约 150 个方法 + 映射表 | 中高：必须复刻 LWJGL `Struct`/`CallbackI` 继承与描述符，否则解析失败 | **阶段 1 验证路线**，先证明可行性 |
| C. 等待上游 | 0 | 上游目前无计划（issue #318/#332/#355 未解决） | 仅作兜底 |

### 6.1 阶段 1 原型（本次已开始）

- 已从官方 `lwjgl-sdl-3.4.3.jar` 提取 SDL3 常量（`research/amethyst/sdl_constants.txt`），保证事件类型/窗口标志/GL 属性数值与 MC 26.3 一致。
- 已在本地分支 `feature/mc26-sdl-shim` 建立 `JavaApp/src/lwjgl/org/lwjgl/sdl/` 的原型骨架（先覆盖事件类型、结构体、SDL_Init/Timer/Error/Platform/Hints 等无原生依赖的部分），并用 `javac` 做编译验证。
- 下一里程碑：补 `SDLVideo`/`SDLEvents`/`SDLKeyboard`/`SDLMouse`（映射到现有 `org.lwjgl.glfw.GLFW` Java 桥），验证 26.3 能否进入标题界面。

## 7. 路线 B 实施计划（已选定，2026-11-11）

### 7.1 参考实现：Amethyst-Android 的 SDL 集成（已核对源码）

| 关键点 | Android 实现 | iOS 对应 |
|---|---|---|
| 窗口/表面 | `MinecraftGLSurface.setupSDL()`：创建 `org.libsdl.app.SDLSurface`，调用 `SDL.initialize()`、`SDL.setContext((MainActivity) ctx)`、`SDLActivity.externalInitialize(surface, layout, nativeSurface)`，把 SDL 嵌入 Pojav 已有的 Surface | Amethyst 的 `GameSurfaceView`/`SurfaceViewController` + EGL 桥；SDL3 无 Android 式 external surface API，需要自定义 video driver 或修改 UIKit 后端 |
| 表面生命周期 | `SDLActivity.getSDLSurface().surfaceChanged/surfaceDestroyed/nativeResize(...)` 跟随宿主 surface | 由 `SurfaceViewController`/`GameSurfaceView` 的 resize/destroy 调 SDL 窗口尺寸与事件 |
| 输入 | `SDLActivity.handleKeyEvent(...)`、`SDLActivity.getMotionListener()` 把宿主输入转给 SDL；`CallbackBridge.notifyLauncher(NOTIF_TYPE_SDL, ACTION_INIT_LAUNCHER_INTEGRATION)` | 由 `input_bridge_v3.m` / 自定义 controls 产生 SDL 事件（或交给 SDL 的 UIKit 事件处理） |
| GL 加载 | `JREUtils` 设置 `SDL_OPENGL_LIBRARY`、`SDL_EGL_LIBRARY` 指向 Pojav 的渲染库（gl4es/ANGLE/MobileGlues） | iOS 需让 SDL 使用 Amethyst 的 EGL 上下文（AngLE/MobileGlues）；SDL 自带 UIKit 后端走 EAGL/GLES，无法直接复用 |
| LWJGL 组件 | `components/lwjgl3/<version>/`（`lwjgl.jar`、`lwjgl-<ver>-merged-modules.jar`、`lwjgl-sdl.jar` 等）+ `libs/lwjgl-3.4.1-natives-release.aar`；启动加 `-Dorg.lwjgl.librarypath=<natives>/<abi>` | 需要把 3.4.3 的 jar 与 iOS natives 放进 `Frameworks`/`libs`，并设置 `org.lwjgl.librarypath` |
| SDL 库 | `libs/SDL-release.aar`（含 `libSDL3.so` 与 SDL Java 层） | 官方 SDL3 源码为 iOS arm64 构建 `libSDL3.dylib`（已在 CI 中构建） |

> PojavLauncherTeam/lwjgl3 fork 现状（已核对）：`master` 为 **3.2.4**，`wip/rebase_3.3.3` 为 **3.3.3**，**没有 3.4.x / SDL 模块**。因此 iOS 的 LWJGL 3.4.x 原生模块必须基于官方 LWJGL 3.4.3 源码 + iOS 工具链自行构建（见 7.2）。

### 7.2 需要产出的组件（2026-11-12 实测更新）

| 组件 | 来源 | 状态 |
|---|---|---|
| `libSDL3.dylib`（iOS arm64） | 官方 SDL3 `release-3.4.20` 源码，CMake iOS 交叉编译 | **✅ 已产出**：`research/amethyst/sdl3-artifacts/extracted/libSDL3.dylib`，2,457,896 B，Mach-O arm64，`LC_BUILD_VERSION platform=iOS minos=14.0`；CI run `43050313422` 成功 |
| `lwjgl-3.4.3.jar`、`lwjgl-sdl-3.4.3.jar`、`lwjgl-opengl/stb/openal/freetype/shaderc/vma/tinyfd/nanovg/vulkan/spvc/jemalloc/lz4` | Maven Central（BSD-3） | **✅ 已下载**：`research/amethyst/jars343/` |
| 官方 LWJGL 3.4.3 macOS-arm64 natives | Maven `*-natives-macos-arm64.jar` | **✅ 已下载并转为 iOS 平台**：9 个 dylib（liblwjgl、opengl、stb、openal、freetype、shaderc、vma、tinyfd、nanovg）经 `vtool -set-build-version 2 14.0 18.0` + `install_name_tool` 改写后全部为 `platform=iOS minos=14.0`，依赖仅 libSystem/CoreFoundation/CoreGraphics/CoreText/AudioToolbox/AudioUnit/ApplicationServices；CI run `43057092247` 成功，产物 `research/amethyst/lwjgl343-ios/` |
| iOS 版 `liblwjgl.dylib`（核心） | 官方 3.4.3 原生库 + 平台修补 | **✅ 无需重编**：官方 `liblwjgl.dylib` 导出 **820 个 `Java_org_lwjgl_system_JNI_invoke*`** 符号（用 Mach-O export trie 解析验证），正好匹配 3.4.3 Java 的 `invoke*` 原生方法；平台改写后可加载 |
| launcher 版本选择 | 按 `version.json` 的 `org.lwjgl` 版本选择 3.4.3 jar + 原生库路径（参照 Android 的 `components/lwjgl3/<ver>`） | 待实现（feature 分支；见 7.4 类加载问题） |
| 窗口/事件桥 | 自定义 SDL video driver 或补丁 SDL3 UIKit 后端，复用 Amethyst surface/EGL/输入 | 设计阶段（见 7.4） |

**关键技术结论（javap 实测）：**

1. **LWJGL 3.4.3 的 SDL 绑定是纯 Java**：`SDLInit.SDL_Init(int)` 的字节码直接调用 `org.lwjgl.system.JNI.invokeZ(J)I`，`lwjgl-sdl` 的 natives jar 里只有自带的 `libSDL3.dylib`，**没有 `liblwjgl_sdl.dylib`**。因此 26.x 只需：`liblwjgl.dylib`（核心）+ `libSDL3.dylib`（iOS 版）+ 3.4.3 Java jar。
2. **核心 JNI 接口在 3.4.x 改名**：3.3.3 是 `JNI.call*`，3.4.3 是 `JNI.invoke*`（javap 对比，3.3.3 独有 `callZ/callI/...`，3.4.3 独有 `invokeZ/invokeI/...`）。**现有 iOS 版 3.3.3 `liblwjgl.dylib` 无法驱动 3.4.3 Java 绑定**，必须换 3.4.3 核心库。
3. **官方 macOS natives 可移植性**：`liblwjgl`/`liblwjgl_opengl`/`liblwjgl_stb`/`liblwjgl_vma`/`liblwjgl_tinyfd`/`liblwjgl_nanovg` 仅依赖 `libSystem`；`libfreetype` 依赖 CoreFoundation/CoreGraphics/CoreText；`libshaderc` 依赖 libc++/libSystem；`libopenal` 依赖 AudioToolbox/AudioUnit/ApplicationServices/CoreAudio。**前者可在 iOS 上运行，只需把 Mach-O `LC_BUILD_VERSION` 平台从 macOS(1) 改为 iOS(2)**。
4. **Amethyst 已有平台修补机制**：`Natives/dyld_patch_platform.m` 的 `PLPatchMachOPlatformForFile` 会把 `LC_BUILD_VERSION.platform` 改成当前平台并重写 macOS 的 `/Versions/X` 框架路径；但 `main_hook.m` 的 `hooked_dlopen` 只对 **HOME/TMPDIR 下的路径**执行修补（应用包内 `Frameworks/` 不在其中）。因此：
   - 方案 A（推荐）：在 CI 打包时用 `vtool -set-build-version 2 <minos> <sdk>` 把 3.4.3 原生库直接改成 iOS 平台，放入 `Frameworks` 即可；
   - 方案 B：把这些库放到 `AME_HOME` 下，由 `hooked_dlopen` 运行时修补，并设置 `java.library.path`/`org.lwjgl.librarypath` 指向该目录。
5. **Pojav 的 iOS 构建配方可复用**：`PojavLauncherTeam/lwjgl3` 的 `wip/rebase_3.3.3` 分支含 `ci_build_ios.bash` + `.github/workflows/build-ios.yml`（libffi→iOS、shaderc nightly、`ant -Dplatform.macos=true compile compile-native release`、`vtool` 修补 freetype）。若官方 macOS natives 在 iOS 上有兼容问题，可按此配方把 LWJGL 3.4.3 源码重编为 iOS 原生库。

### 7.3 里程碑（更新）

1. **B1 SDL3 原生库**：✅ 已完成（CI 产物已验证 arm64/iOS 平台）。
2. **B2 LWJGL 3.4.3 核心原生库**：✅ 官方 macOS `liblwjgl.dylib` 已平台改写为 iOS（`platform=iOS minos=14.0`），并用 export trie 验证其导出 820 个 `JNI_invoke*` 符号；与 3.3.3 的 1018 个 `JNI_call*` 符号互不冲突，双核心库共存方案可行（运行时加载待真机验证）。
3. **B3 Java 侧集成**：按版本加载 3.4.3 jar + 核心/SDL 原生库；26.3 能完成类加载并调用 `SDL_Init`/`SDL_CreateWindow`。
4. **B4 窗口/输入接入**：解决 SDL3 与 Amethyst 的窗口/线程/GL 上下文冲突（见 7.4），目标进入标题界面。
5. **B5 回归与放行**：1.21.11 回归 + 26.x 版本检测放行 + 文档。

### 7.4 关键风险（更新）

- **线程模型（新发现，最高优先级）**：SDL3 的 UIKit 后端要求所有窗口/事件操作在 **主线程**；Amethyst 的 `launchJVM` 在后台线程启动 JVM，MC 的 `SDL_Init`/`SDL_CreateWindow` 会在非主线程执行，直接调用 UIKit 会崩溃/断言。需要在 SDL 启动前切到主线程，或给 SDL UIKit 后端加主线程调度补丁。
- **GL 能力**：MC 26.x 需要 OpenGL 3.2+；iOS 系统 GLES 3.0 不足，必须让 SDL 走 Amethyst 的 ANGLE/MobileGlues EGL（而非 SDL 自带 EAGL）。SDL 的 `SDL_HINT_VIDEO_EXTERNAL_CONTEXT` 只能跳过上下文创建，swap/EGL 绑定仍需自定义 driver。
- **窗口集成**：SDL3 UIKit 后端自建 `UIWindow`，与 Amethyst 的 launcher/controls 层级冲突；优先自定义 video driver。
- **无法真机验证**：所有里程碑只能靠 CI 产物 + 日志验证，最终需真机冒烟。

### 7.5 类加载与“双 LWJGL 版本共存”方案（待实现）

Amethyst 的 JVM 启动方式（`Natives/JavaLauncher.m`）：

- `-cp "<bundle>/libs/*"` → `libs/lwjgl.jar`（3.3.3，含自研 GLFW/CallbackBridge）在**系统/父类加载器**中；
- `-Djava.system.class.loader=net.kdt.pojavlaunch.PojavClassLoader`，它是 **parent-first** 的 `URLClassLoader`，MC 的版本 jar 通过 `addURL` 追加；
- 因此 `org.lwjgl.*` 默认总是命中父加载器里的 3.3.3，26.x 的 3.4.3 绑定不会被加载。

要让 26.x 用 3.4.3、同时不破坏现有版本，方案：

| 方案 | 做法 | 风险 |
|---|---|---|
| **S1（推荐）双核心库 + 子优先加载** | 把 3.4.3 核心改名为 `liblwjgl343.dylib` 放入 `Frameworks/lwjgl343/`；启动时 `System.load` 两个 dylib（3.3.3 提供 GLFW/CallbackBridge 符号，3.4.3 提供 `JNI.invoke*`）；给 `PojavClassLoader` 增加“`org.lwjgl` 子优先”，但 `org.lwjgl.glfw` 继续用 3.3.3 自研桥；26.x 时把 3.4.3 jar 加入 | 需要验证两个 dylib 的 JNI 符号互不冲突；`org.lwjgl.system` 3.4.3 与自研 GLFW 的二进制兼容性 |
| S2 合并 jar | 以 3.4.3 为核心，把自研 `org.lwjgl.glfw` 源码重新编译进 3.4.3 的 `lwjgl.jar`，其余模块用 3.4.3 | 自研 GLFW 依赖 3.3.3 的 `system`/`Struct` 细节，重编译可能不兼容 |
| S3 独立 classloader | 为 MC 26.x 单独建 child-first classloader，加载全部 3.4.3 + SDL，launcher 仍用 3.3.3 | 两套 `org.lwjgl` 类在同一 JVM 中隔离成本高（JNI 库按 classloader 关联） |

S1 的关键证据：官方 3.4.3 `liblwjgl.dylib` 导出 **820 个 `Java_org_lwjgl_system_JNI_invoke*`**；现有 3.3.3 iOS `liblwjgl.dylib` 导出 **1018 个 `Java_org_lwjgl_system_JNI_call*`** 及 GLFW/CallbackBridge 符号。两者符号名不重叠，改名后可在同一进程共存。

### 7.6 下一步（按顺序）

1. 新建分支 `feature/mc26-native`，把 `research/amethyst/sdl3-artifacts/extracted/libSDL3.dylib`、`research/amethyst/lwjgl343-ios/*.dylib`、`jars343/*.jar` 纳入打包脚本（`Frameworks/lwjgl343/` 与 `libs343/`）。
2. 改 `JavaLauncher.m`：按 `MinecraftResourceUtils.requiredLWJGLVersionForVersionJSON:` 判断 3.4.x，追加 `-Dorg.lwjgl.librarypath` 与 3.4.3 jar；`System.load` 双核心库。
3. 改 `PojavClassLoader`：`org.lwjgl` 子优先（排除 `org.lwjgl.glfw`）。
4. 解决 SDL 主线程/窗口/EGL 适配（7.4），先做 bring-up（SDL 自建窗口）验证 26.3 能否出画面。
5. CI 出包 + 真机冒烟；1.21.11 回归。

## 8. 已有数据文件

- `research/amethyst/mc26_sdl_api.txt` — 26.3 引用的全部 SDL 类与成员（可直接据此生成骨架）。
- `research/amethyst/mc26_lwjgl_gap.txt` — 与内置 3.3.3 的差距清单（5 类 + 3 成员）。
- `tools/amethyst/analyze_mc26.py` / `analyze_lwjgl_gap.py` — 可重复运行的字节码分析脚本。

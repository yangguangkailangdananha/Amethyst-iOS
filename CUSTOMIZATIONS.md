# Local customizations (unofficial build)

This checkout is a **local, unmodified-upstream-plus-patches** fork of
[AngelAuraMC/Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS).
It is not pushed anywhere. Everything below is source-level work; the iOS
binaries still have to be produced on macOS (or via the GitHub Actions
workflow `Build unsigned iOS IPA`).

## 0. Simplified Chinese UI (zh-Hans)

* `Natives/resources/zh-Hans.lproj/Localizable.strings` now covers **all 335
  keys** of the English file (Crowdin translations kept, 101 new manual
  translations added for mods, runtime compatibility, runtime manager, ...).
* `Natives/resources/zh-Hans.lproj/InfoPlist.strings` localizes the local
  network / microphone permission descriptions.
* Hard-coded strings are localized through new keys: profile creation menu
  (Vanilla/Modpack...), version placeholder, Forge installer search/dialogs,
  custom-controls segmented control and placeholders, save-error dialog, and
  the mod error messages (CurseForge key, checksum, URL, unzip...).
* `zh-Hant` still has only the 149 upstream keys.

Chinese is used automatically when the device language is Simplified Chinese;
other languages still fall back to English.

## 1. Offline (local) accounts

* `MinecraftResourceDownloadTask.checkAccessWithDialog:` no longer blocks local
  accounts from downloading/installing Minecraft (the old code required an Xbox
  gamertag). Demo accounts behave as before.
* `LocalAuthenticator` now derives the **same offline UUID as vanilla**
  (`UUID.nameUUIDFromBytes("OfflinePlayer:<name>")`, MD5/v3, IETF variant) and
  migrates accounts that still have the all-zero UUID.
* `Tools.getMinecraftArgs` (Java) no longer leaves dangling `--xuid` /
  `--clientId` options when the account has no XUID/client id. Modern version
  JSONs pass both options, so without this fix the argument parser throws before
  the game window appears.
* `user_type` is only set to `msa` when the account really has an XUID.

Online-mode servers still verify sessions server-side; nothing can bypass that.

## 2. Mods

New sidebar entry **Mods** (`Natives/mods/`):

* `ModManager` — resolves the `mods` folder of the selected profile, lists,
  imports, enables/disables and deletes mods, and reads mod metadata from
  `fabric.mod.json`, `quilt.mod.json`, `META-INF/(neo)forge.mods.toml` and
  `mcmod.info`.
* Import from the device supports `.jar` and `.zip`/`.mrpack` archives (all
  `.jar` entries are extracted into `mods/`).
* `ModSiteAPI` + `ModBrowserViewController` — search and install from
  **Modrinth** (no key) and **CurseForge** (personal API key, asked on first
  use). Results are filtered by the profile's game version and mod loader
  (Fabric / Quilt / Forge / NeoForge), with SHA1 verification of downloads.
* Direct URLs can be installed as well, which covers sites without a public API.

## 3. Latest Minecraft versions

Fixed launcher-side blockers:

* Java **25** is now registered in the default runtime map (`java.java_homes`)
  and existing preference files are migrated when the bundled runtime exists.
* `getSelectedJavaHome` picks the smallest installed runtime `>= minVersion` and
  returns `nil` (showing the existing "requires Java N" dialog) instead of
  silently launching an older runtime.
* JNA is pinned to the bundled 5.13.0 build (see `java.allow_newer_jna`), because
  the shipped `libjnidispatch.dylib` and the patched `com.sun.jna.Platform` are
  built for it. Versions asking for 5.17.0 are logged.
* Versions that require LWJGL 3.4+/SDL3 are detected **before** downloading
  libraries and again before launching, with a readable explanation
  (`MinecraftResourceUtils.unsupportedReasonForVersionJSON:`), and a debug
  toggle `debug.allow_unsupported_versions` to bypass the check.

**Important:** Minecraft 26.3 replaced GLFW with SDL3 (`org.lwjgl.sdl`, no
`org.lwjgl.glfw` references in the client jar at all). 26.1/26.2 still use GLFW
but need LWJGL 3.4.1. The iOS input/window bridge in this project is GLFW based
and compiled against LWJGL 3.3.3, so:

* 26.1/26.2 → blocked until LWJGL 3.4.1 iOS natives are built and bundled.
* 26.3+ → blocked until an SDL3 backend and `libSDL3` are ported.

The newest playable release with this build is **1.21.11**. Both cases are
reported by `MinecraftResourceUtils.unsupportedReasonForVersionJSON:` with a
version specific explanation.

## 4. Building on GitHub Actions (unsigned IPA + optional TrollStore .tipa)

`.github/workflows/build-ios-unsigned.yml` builds the app on a GitHub-hosted
macOS runner and produces an **unsigned** `.ipa` (ldid ad-hoc signature with
`entitlements.sideload.xml`) plus, optionally, a TrollStore `.tipa`
(`entitlements.trollstore.xml`).

Requirements / behaviour:

* Runner label `macos-15-intel` — `macos-14` is rejected for this account and
  the arm64 (`macos-26`) queue is heavily constrained.
* Java 8 boot JDK is installed with `actions/setup-java`.
* The four iOS Java runtimes are extracted from an upstream Amethyst nightly
  IPA; pass a PAT as the `upstream_token` dispatch input (masked in the logs).
  `assets.angelauramc.dev` no longer resolves, so it is only a fallback.
* Only Java 8/17/21 were present in the upstream IPA, so the artifact ships
  without Java 25. `make` is invoked with `JRE_NO_DOWNLOAD=1` and simply skips
  missing runtimes.
* The TrollStore step is optional and `continue-on-error`: the unsigned IPA is
  always uploaded.

Optional Apple certificate signing (workflow inputs):

* `signing_cert_p12` — base64 of the `.p12` certificate
* `signing_cert_password`
* `signing_provisioning_profile` — base64 of a `.mobileprovision` for
  `org.angelauramc.amethyst`
* `signing_team_id` — Apple Developer Team ID

When these are provided the workflow imports them into a temporary keychain and
runs `gmake package ... TEAMID= SIGNING_TEAMID= PROVISIONING=`, producing
`Amethyst-signed-ios.ipa`. Without them the build falls back to the ad-hoc
(ldid) unsigned IPA. Note that the entitlements generated in `Makefile` include
`keychain-access-groups`; the provisioning profile must allow them.

Fixes that were needed to build this (2026) upstream tree with Xcode 16:

* `JavaLauncher.m`: include `<mach/mach.h>`/`<mach/mach_init.h>` (implicit
  declarations are errors in modern clang).
* `CMakeLists.txt`: downgrade legacy C diagnostics
  (`-Wno-error=implicit-function-declaration`, int-conversion, ...).
* `UIKit+hook.h`: resolve `_UISolariumEnabled` with `dlsym` (the symbol does not
  exist in the iPhoneOS 18.5 SDK) and declare `UIBarButtonItem.sharesBackground`
  for the old SDK.
* `Makefile`: `JRE_NO_DOWNLOAD` + conditional runtime packaging.
* Workflow: `ldid -S<path>` (path attached) for the TrollStore re-sign.

Locally on a Mac:

```bash
brew install make cmake ldid
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
BOOTJDK="$(/usr/libexec/java_home -v 1.8)/bin" \
  gmake -j$(sysctl -n hw.ncpu) package PLATFORM=2 JRE_NO_DOWNLOAD=1
# artifacts/org.angelauramc.amethyst-1.0-ios.ipa
BOOTJDK="$(/usr/libexec/java_home -v 1.8)/bin" \
  gmake -j$(sysctl -n hw.ncpu) package PLATFORM=2 TROLLSTORE_JIT_ENT=1 JRE_NO_DOWNLOAD=1
# artifacts/org.angelauramc.amethyst-1.0-ios-trollstore.tipa
```

Chinese documentation: `docs/` in the development workspace
(`D:\DeepSeek\docs\Amethyst-iOS-定制说明.md`).

package net.kdt.pojavlaunch;

import java.beans.Beans;
import java.io.*;
import java.lang.reflect.Field;
import java.util.*;
import java.util.concurrent.*;

import org.lwjgl.glfw.CallbackBridge;
import org.lwjgl.glfw.GLFW;

import net.kdt.pojavlaunch.uikit.*;
import net.kdt.pojavlaunch.utils.*;
import net.kdt.pojavlaunch.value.*;

public class PojavLauncher {
    private static float currProgress, maxProgress;

    public static void main(String[] args) throws Throwable {
        // Minecraft 26.x diagnostics: make sure any stderr and uncaught exception
        // ends up in the launcher log (latestlog) instead of being lost.
        if (System.getProperty("pojav.mc26.core") != null) {
            System.out.println("[MC26] launcher build: uncaught-file-v2");
            System.setErr(System.out);
            Thread.setDefaultUncaughtExceptionHandler((t, th) -> {
                System.out.println("[MC26] Uncaught exception in " + t.getName() + ": " + th);
                th.printStackTrace(System.out);
                System.exit(1);
            });
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                // Dump every thread stack: the thread that called System.exit(1)
                // is still visible with its Java frames here.
                StringBuilder sb = new StringBuilder();
                sb.append("[MC26] ---- shutdown thread stacks ----\n");
                for (java.util.Map.Entry<Thread, StackTraceElement[]> e : Thread.getAllStackTraces().entrySet()) {
                    sb.append("[MC26/thread] ").append(e.getKey().getName())
                            .append(" state=").append(e.getKey().getState()).append('\n');
                    for (StackTraceElement s : e.getValue()) {
                        sb.append("[MC26/thread]   at ").append(s).append('\n');
                    }
                }
                sb.append("[MC26] ---- end thread stacks ----\n");
                System.out.print(sb);
                try {
                    String home = System.getenv("AME_HOME");
                    java.io.File dir = new java.io.File(home != null ? home : System.getProperty("user.dir"));
                    java.nio.file.Files.write(new java.io.File(dir, "mc26-shutdown.txt").toPath(),
                            sb.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
                } catch (Throwable t) {
                    System.out.println("[MC26] shutdown dump write failed: " + t);
                }
            }, "mc26-shutdown-threads"));
        }
        // Skip calling to com.apple.eawt.Application.nativeInitializeApplicationDelegate()
        Beans.setDesignTime(true);
        try {
            // Some places use macOS-specific code, which is unavailable on iOS
            // In this case, try to get it to use Linux-specific code instead.
            com.apple.eawt.Application.getApplication();
            Class clazz = Class.forName("com.apple.eawt.Application");
            Field field = clazz.getDeclaredField("sApplication");
            field.setAccessible(true);
            field.set(null, null);
            sun.font.FontUtilities.isLinux = true;
            System.setProperty("java.util.prefs.PreferencesFactory", "java.util.prefs.FileSystemPreferencesFactory");
        } catch (Throwable th) {
            // Not on JRE8, ignore exception
            //Tools.showError(th);
        }

        Thread.currentThread().setUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {

            public void uncaughtException(Thread t, Throwable th) {
                // Always write to stdout and to a file: MC may replace System.out
                // / System.err later, which made the crash invisible in latestlog.
                java.io.StringWriter sw = new java.io.StringWriter();
                java.io.PrintWriter pw = new java.io.PrintWriter(sw);
                pw.println("[MC26] Uncaught exception in " + t.getName() + ": " + th);
                th.printStackTrace(pw);
                pw.flush();
                String text = sw.toString();
                System.out.print(text);
                System.out.flush();
                try {
                    String home = System.getenv("AME_HOME");
                    java.io.File dir = new java.io.File(home != null ? home : System.getProperty("user.dir"));
                    java.nio.file.Files.write(new java.io.File(dir, "mc26-uncaught.txt").toPath(),
                            text.getBytes(java.nio.charset.StandardCharsets.UTF_8));
                } catch (Throwable ignored) {
                }
                System.exit(1);
            }
        });

        try {
            // Try to initialize Caciocavallo17
            Class.forName("com.github.caciocavallosilano.cacio.ctc.CTCPreloadClassLoader");
        } catch (ClassNotFoundException e) {}

        if (args[0].equals("-jar")) {
            UIKit.callback_JavaGUIViewController_launchJarFile(args[1], Arrays.copyOfRange(args, 2, args.length));
        } else {
            launchMinecraft(args);
        }
    }

    public static void launchMinecraft(String[] args) throws Throwable {
        // Args for Spiral Knights
        System.setProperty("appdir", "./spiral");
        System.setProperty("resource_dir", "./spiral/rsrc");

        String sizeStr = System.getProperty("cacio.managed.screensize");
        System.setProperty("glfw.windowSize", sizeStr);

        // Setup Forge splash.properties
        File forgeSplashFile = new File(Tools.DIR_GAME_NEW, "config/splash.properties");
        if (System.getProperty("pojav.internal.keepForgeSplash") == null) {
            forgeSplashFile.getParentFile().mkdir();
            if (forgeSplashFile.exists()) {
                Tools.write(forgeSplashFile.getAbsolutePath(), Tools.read(forgeSplashFile.getAbsolutePath().replace("enabled=true", "enabled=false")));
            } else {
                Tools.write(forgeSplashFile.getAbsolutePath(), "enabled=false");
            }
        }

        System.setProperty("org.lwjgl.vulkan.libname", "libMoltenVK.dylib");

        MinecraftAccount account = MinecraftAccount.load(args[0]);
        JMinecraftVersionList.Version version = Tools.getVersionInfo(args[1]);
        System.out.println("Launching Minecraft " + version.id);
        String configPath;
        if (version.logging != null) {
            if (version.logging.client.file.id.equals("client-1.12.xml")) {
                configPath = Tools.DIR_BUNDLE + "/log4j-rce-patch-1.12.xml";
            } else if (version.logging.client.file.id.equals("client-1.7.xml")) {
                configPath = Tools.DIR_BUNDLE + "/log4j-rce-patch-1.7.xml";
            } else {
                configPath = Tools.DIR_GAME_NEW + "/" + version.logging.client.file.id;
            }
            System.setProperty("log4j.configurationFile", configPath);
        }

        Tools.launchMinecraft(account, version);
    }
}

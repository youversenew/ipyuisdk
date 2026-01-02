// =============================================================================
// FILE: lib/main.dart
// SYSTEM: IPYUI QUANTUM CLIENT (MAIN ENTRY)
// VERSION: 10.0.0-MASTER
// INTEGRATION: Kernel, Connection, DevTools, Universal Renderers
// =============================================================================

import 'dart:async';
import 'dart:io';

// --- FLUTTER CORE ---
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';

// --- UI SYSTEMS (Fluent aliased) ---
import 'package:fluent_ui/fluent_ui.dart' as fluent;

// --- PACKAGES ---
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

// --- INTERNAL MODULES ---
import 'utils.dart';
import 'kernel.dart';
import 'connection.dart';
import 'devtools.dart';
import 'performance.dart';

// --- RENDERERS ---
import 'renderers/material_renderer.dart';
import 'renderers/cupertino_renderer.dart';
import 'renderers/fluent_renderer.dart';

// =============================================================================
// 1. BOOTSTRAP (ISHGA TUSHIRISH)
// =============================================================================

void main() async {
  // Crash Guard: Ilova qulamasligi uchun himoya
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Desktop Oyna Sozlamalari
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 800),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden, // Custom Titlebar ishlatamiz
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }

    // 2. Tizim Kerneli va Aloqani ishga tushirish
    await IpyKernel.instance.boot();
    await ConnectionManager.instance.initialize(); // Cache yuklanadi

    // 3. Serverga Ulanish (Agar avtomatik ulanmasa)
    if (!IpyKernel.instance.isConnected) {
      ConnectionManager.instance.connect("ws://localhost:8000/ws");
    }

    runApp(const IpyRoot());
  }, (error, stack) {
    Logger.instance.add("FATAL CRASH: $error", LogType.error);
    debugPrint("🔥 KERNEL PANIC: $error");
  });
}

// =============================================================================
// 2. ROOT WIDGET (THEME & UI MODE MANAGER)
// =============================================================================

class IpyRoot extends StatelessWidget {
  const IpyRoot({super.key});

  @override
  Widget build(BuildContext context) {
    // Kernel o'zgarishlarini tinglaymiz (Real-time Config Update)
    return AnimatedBuilder(
      animation: IpyKernel.instance,
      builder: (context, _) {
        final config = IpyKernel.instance.config;
        final String mode = config['ui_mode'] ?? 'material';
        final Color seedColor =
            Utils.parseColor(config['seed_color']) ?? Colors.blue;
        final String fontName = config['font'] ?? 'Roboto';
        final ThemeMode themeMode =
            config['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light;

        // 🪟 1. FLUENT UI (Windows Style)
        if (mode == 'fluent') {
          final accent = fluent.AccentColor.swatch({
            'normal': seedColor,
            'dark': seedColor,
            'light': seedColor,
            'darker': seedColor,
            'lighter': seedColor,
            'darkest': seedColor,
          });

          return fluent.FluentApp(
            title: config['title'] ?? 'IPYUI Fluent',
            debugShowCheckedModeBanner: false,
            themeMode: themeMode == ThemeMode.dark
                ? fluent.ThemeMode.dark
                : fluent.ThemeMode.light,
            theme: fluent.FluentThemeData(
              accentColor: accent,
              brightness: Brightness.light,
              visualDensity: fluent.VisualDensity.standard,
              fontFamily: GoogleFonts.getFont(fontName).fontFamily,
            ),
            darkTheme: fluent.FluentThemeData(
              accentColor: accent,
              brightness: Brightness.dark,
              visualDensity: fluent.VisualDensity.standard,
              fontFamily: GoogleFonts.getFont(fontName).fontFamily,
            ),
            home: const IpyShell(),
          );
        }

        // 🍎 2. CUPERTINO (iOS Style)
        if (mode == 'cupertino') {
          return CupertinoApp(
            title: config['title'] ?? 'IPYUI iOS',
            debugShowCheckedModeBanner: false,
            theme: CupertinoThemeData(
              brightness: themeMode == ThemeMode.dark
                  ? Brightness.dark
                  : Brightness.light,
              primaryColor: seedColor,
              textTheme: CupertinoTextThemeData(
                textStyle: GoogleFonts.getFont(fontName),
              ),
            ),
            home: const IpyShell(),
          );
        }

        // 🤖 3. MATERIAL (Default / Android)
        return MaterialApp(
          title: config['title'] ?? 'IPYUI App',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: _buildMaterialTheme(Brightness.light, seedColor, fontName),
          darkTheme: _buildMaterialTheme(Brightness.dark, seedColor, fontName),
          home: const IpyShell(),
        );
      },
    );
  }

  ThemeData _buildMaterialTheme(
      Brightness brightness, Color seed, String font) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme:
          ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
      fontFamily: GoogleFonts.getFont(font).fontFamily,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F5),
    );
  }
}

// =============================================================================
// 3. APP SHELL (DEVTOOLS & WINDOW FRAME)
// =============================================================================

class IpyShell extends StatefulWidget {
  const IpyShell({super.key});
  @override
  State<IpyShell> createState() => _IpyShellState();
}

class _IpyShellState extends State<IpyShell> with WindowListener {
  final FocusNode _keyboardNode = FocusNode();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    // DevToolsni DartP orqali boshqarish uchun ulash
    DartP.instance.toggleDevTools = () {
      DevToolsManager.instance.toggle();
    };
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _keyboardNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // F12 Bosilganda DevTools ochilishi uchun Listener
    return RawKeyboardListener(
      focusNode: _keyboardNode,
      autofocus: true,
      onKey: (e) {
        if (e is RawKeyDownEvent && e.logicalKey == LogicalKeyboardKey.f12) {
          DevToolsManager.instance.toggle();
        }
      },
      // DEVTOOLS OVERLAY: Butun ilovani o'rab oladi
      child: DevToolsOverlay(
        child: AnimatedBuilder(
          animation: IpyKernel.instance,
          builder: (context, _) {
            // Scaffold turi UI Mode ga qarab o'zgarishi mumkin, lekin
            // biz Universal Renderer ichida boshqarganimiz ma'qul.
            // Bu yerda umumiy oyna ramkasini chizamiz.

            final config = IpyKernel.instance.config;
            final bool isNativeBar = config['title_bar'] == 'native';
            final Color bg = Theme.of(context).scaffoldBackgroundColor;

            return Scaffold(
              backgroundColor: bg,
              body: Stack(
                children: [
                  Column(
                    children: [
                      // 1. Custom Title Bar (Agar native bo'lmasa)
                      if (!isNativeBar) _buildCustomTitleBar(context),

                      // 2. Main Content (Renderer)
                      Expanded(
                        child: RepaintBoundary(
                          // Performance uchun chegara
                          child: IpyKernel.instance.uiTree != null
                              ? UniversalBridge(
                                  node: IpyKernel.instance.uiTree!,
                                  mode: config['ui_mode'])
                              : const ConnectionScreen(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCustomTitleBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = IpyKernel.instance.config;

    return Container(
      height: 35,
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0),
      child: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Row(
          children: [
            const SizedBox(width: 15),
            // Ikonka
            if (config['icon'] != null)
              Image.network(config['icon'], width: 16, height: 16)
            else
              const Icon(Icons.widgets, size: 16, color: Colors.grey),

            const SizedBox(width: 10),
            // Sarlavha
            Text(
              config['title'] ?? 'IPYUI',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87),
            ),
            const Spacer(),

            // Oyna Tugmalari (Windows/Linux uchun)
            if (!Platform.isMacOS) ...[
              _WindowBtn(Icons.remove, windowManager.minimize),
              _WindowBtn(Icons.crop_square, windowManager.maximize),
              _WindowBtn(Icons.close, windowManager.close, isDanger: true),
            ]
          ],
        ),
      ),
    );
  }
}

class _WindowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback cb;
  final bool isDanger;
  const _WindowBtn(this.icon, this.cb, {this.isDanger = false});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: cb,
      child: Container(
        width: 45,
        height: 35,
        alignment: Alignment.center,
        child:
            Icon(icon, size: 14, color: isDanger ? Colors.white : Colors.grey),
      ),
    );
  }
}

// =============================================================================
// 4. UNIVERSAL BRIDGE (RENDERER ROUTER)
// =============================================================================

class UniversalBridge extends StatelessWidget {
  final Map<String, dynamic> node;
  final String? mode;

  const UniversalBridge({super.key, required this.node, this.mode});

  @override
  Widget build(BuildContext context) {
    // --- LAZY LOADING CHECK ---
    // Agar widget "Lazy List" bo'lsa, Scroll hodisasini ushlaymiz
    if (node['type'] == 'listview' && node['props']?['lazy'] == true) {
      return NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (PerformanceManager.instance.shouldLoadMore(notification)) {
            // Python'ga signal: "Men oxiriga keldim, yana ma'lumot ber!"
            IpyKernel.instance.send(node['id'], 'scroll_end', null);
          }
          return false;
        },
        child: _routeRenderer(),
      );
    }

    return _routeRenderer();
  }

  Widget _routeRenderer() {
    // Kernelga to'g'ridan-to'g'ri bog'langan Event Sender
    final sender = IpyKernel.instance.send;

    if (mode == 'fluent') {
      return FluentRenderer.build(node, sender);
    } else if (mode == 'cupertino') {
      return CupertinoRenderer.build(node, sender);
    } else {
      return MaterialRenderer.build(node, sender);
    }
  }
}

// =============================================================================
// 5. CONNECTION SCREEN (LOADING)
// =============================================================================

class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({super.key});
  @override
  Widget build(BuildContext context) {
    // Agar Keshda eski UI bo'lsa, uni ko'rsatishimiz mumkin edi (Kernel ichida hal qilingan)
    // Bu ekran faqat Kesh bo'sh bo'lsa va Internet yo'q bo'lsa chiqadi.
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Lottie Animatsiya (Agar mavjud bo'lsa)
          Lottie.network(
            'https://assets9.lottiefiles.com/packages/lf20_b88nh30c.json',
            height: 150,
            errorBuilder: (c, e, s) => const CircularProgressIndicator(),
          ),
          const SizedBox(height: 20),
          const Text("Connecting to Kernel...",
              style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 10),
          TextButton(
              onPressed: () =>
                  ConnectionManager.instance.connect("ws://localhost:8000/ws"),
              child: const Text("Retry Connection"))
        ],
      ),
    );
  }
}

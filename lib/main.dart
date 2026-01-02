// =============================================================================
// FILE: lib/main.dart
// SYSTEM: IPYUI QUANTUM CLIENT (MAIN INTEGRATION)
// VERSION: 12.0.0-CONNECTED
// DESC: Connects Kernel, Connection, DevTools, and Renderers into one App.
// =============================================================================

import 'dart:async';
import 'dart:io';

// --- FLUTTER CORE ---
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';

// --- UI SYSTEMS (Aliased) ---
import 'package:fluent_ui/fluent_ui.dart' as fluent;

// --- PACKAGES ---
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

// --- INTERNAL MODULES (BIZ YOZGAN FAYLLAR) ---
import 'utils.dart'; // Parserlar
import 'kernel.dart'; // Orqa fon, Hardware, State
import 'connection.dart'; // WebSocket, Cache, Binary
import 'devtools.dart'; // F12, Inspector, Console
import 'performance.dart'; // Diffing, Lazy Loading

// --- RENDERERS ---
import 'renderers/material_renderer.dart';
import 'renderers/cupertino_renderer.dart';
import 'renderers/fluent_renderer.dart';

// =============================================================================
// 1. BOOTSTRAP (TIZIMNI YUKLASH)
// =============================================================================

void main() async {
  // Crash Guard: Ilova qulamasligi uchun global himoya
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
        // Standart holatda Tizim Ramkasi (Native)
        titleBarStyle: TitleBarStyle.normal,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }

    // 2. KERNELNI ISHGA TUSHIRISH (Hardware & State)
    await IpyKernel.instance.boot();

    // 3. ALOQANI ISHGA TUSHIRISH (Cache & Network)
    // Bu yerda Cache dagi eski UI yuklanadi (Offline Mode)
    await ConnectionManager.instance.initialize();

    // 4. SERVERGA ULANISH
    // Agar kesh bo'sh bo'lsa yoki yangilanish kerak bo'lsa
    if (!IpyKernel.instance.isConnected) {
      ConnectionManager.instance.connect("ws://localhost:8000/ws");
    }

    runApp(const IpyRoot());
  }, (error, stack) {
    // Xatolikni DevTools logiga va Konsolga yozamiz
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
    // IpyKernel o'zgarishlarini tinglaymiz (Config, Theme, UI Mode)
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
            title: config['title'] ?? 'IPYUI Client',
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
            title: config['title'] ?? 'IPYUI Client',
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
          title: config['title'] ?? 'IPYUI Client',
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
// 3. APP SHELL (DEVTOOLS, KEYBOARD & LAYOUT)
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

    // DartP (Script) orqali DevToolsni ochish/yopish imkoniyati
    // Bu Kernelga contextni bog'lashdan oldin kerak
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // IpyKernelga Contextni beramiz (Dialoglar chiqishi uchun)
      // IpyKernel.instance.setContext(context); // Agar kernelda bu metod bo'lsa
      // Hozirda Kernel global contextni ishlatmaydi, lekin biz DevToolsOverlay ni ishga tushirishimiz kerak.
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _keyboardNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. F12 ni tinglash uchun Listener
    return RawKeyboardListener(
      focusNode: _keyboardNode,
      autofocus: true,
      onKey: (e) {
        if (e is RawKeyDownEvent && e.logicalKey == LogicalKeyboardKey.f12) {
          DevToolsManager.instance.toggle();
        }
      },
      // 2. DEVTOOLS OVERLAY (Bizning `devtools.dart` dagi widget)
      // Bu butun ilovani o'rab turadi va F12 bosilganda ustidan chiqadi
      child: DevToolsOverlay(
        child: AnimatedBuilder(
          animation: IpyKernel.instance,
          builder: (context, _) {
            final config = IpyKernel.instance.config;
            final bool isNativeBar = config['title_bar'] != 'custom';

            // Background rangi (Theme ga qarab)
            final Color bg = Theme.of(context).scaffoldBackgroundColor;

            return Scaffold(
              backgroundColor: bg,
              body: Stack(
                children: [
                  Column(
                    children: [
                      // 3. CUSTOM TITLE BAR (Agar configda 'custom' bo'lsa)
                      if (!isNativeBar) _buildCustomTitleBar(context),

                      // 4. MAIN CONTENT AREA
                      Expanded(
                        // Performance Boundary (Tezlik uchun)
                        child: RepaintBoundary(
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
            // Ikonka (URL yoki Asset)
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

            // Oyna Tugmalari (Windows/Linux)
            if (!Platform.isMacOS) ...[
              _WinBtn(Icons.remove, windowManager.minimize),
              _WinBtn(Icons.check_box_outline_blank, windowManager.maximize),
              _WinBtn(Icons.close, windowManager.close, isDanger: true),
            ]
          ],
        ),
      ),
    );
  }
}

class _WinBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback cb;
  final bool isDanger;
  const _WinBtn(this.icon, this.cb, {this.isDanger = false});
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
// 4. UNIVERSAL BRIDGE (RENDERER ROUTER & LAZY LOADING)
// =============================================================================

class UniversalBridge extends StatelessWidget {
  final Map<String, dynamic> node;
  final String? mode;

  const UniversalBridge({super.key, required this.node, this.mode});

  @override
  Widget build(BuildContext context) {
    // --- LAZY LOADING DETECTOR ---
    // Agar "ListView" bo'lsa va "lazy: true" bo'lsa, scrollni kuzatamiz
    if ((node['type'] == 'listview' || node['type'] == 'ListView') &&
        node['props']?['lazy'] == true) {
      return NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // PerformanceManager (`performance.dart`) orqali tekshirish
          if (PerformanceManager.instance.shouldLoadMore(notification)) {
            // Kernel orqali Pythonga signal: "Yana ma'lumot yubor!"
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
    // Kernelning 'send' funksiyasini rendererlarga uzatamiz
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
// 5. CONNECTION SCREEN (LOADING & RETRY)
// =============================================================================

class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({super.key});
  @override
  Widget build(BuildContext context) {
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
          const Text("IPYUI QUANTUM ENGINE",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          const Text("Connecting to Kernel...",
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),

          // Qo'lda qayta ulanish tugmasi
          TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text("Retry Connection"),
            onPressed: () =>
                ConnectionManager.instance.connect("ws://localhost:8000/ws"),
          )
        ],
      ),
    );
  }
}

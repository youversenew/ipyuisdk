// =============================================================================
// FILE: lib/utils.dart
// MODULE: UTILITIES, DARTP ENGINE, LOGGING SYSTEM
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'package:url_launcher/url_launcher.dart';

// --- IMPORT: ICONS ---
import 'icons.dart'; // Oldingi icons.dart fayli

// =============================================================================
// 1. LOGGING SYSTEM (For DevTools)
// =============================================================================

enum LogType { info, error, network, system, cli }

class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogType type;

  LogEntry(this.message, this.type) : timestamp = DateTime.now();

  String get timeString =>
      "${timestamp.hour}:${timestamp.minute}:${timestamp.second}.${timestamp.millisecond}";

  Color get color {
    switch (type) {
      case LogType.error:
        return Colors.redAccent;
      case LogType.network:
        return Colors.blueAccent;
      case LogType.system:
        return Colors.green;
      case LogType.cli:
        return Colors.amber;
      default:
        return Colors.white;
    }
  }
}

class Logger {
  static final Logger instance = Logger._internal();
  Logger._internal();

  final List<LogEntry> logs = [];
  final StreamController<List<LogEntry>> _controller =
      StreamController.broadcast();

  Stream<List<LogEntry>> get stream => _controller.stream;

  void add(String message, [LogType type = LogType.info]) {
    logs.add(LogEntry(message, type));
    if (logs.length > 1000) logs.removeAt(0); // Limit memory
    _controller.add(logs);
    // Print to native console as well
    print("[${type.name.toUpperCase()}] $message");
  }

  void clear() {
    logs.clear();
    _controller.add(logs);
  }

  String export() {
    return logs
        .map((l) => "[${l.timeString}] [${l.type.name}] ${l.message}")
        .join('\n');
  }
}

// =============================================================================
// 2. DARTP ENGINE (Dynamic Interpreter)
// =============================================================================

class DartP {
  static final DartP instance = DartP._internal();
  DartP._internal();

  BuildContext? _context;

  // DevTools Actions
  Function()? toggleDevTools;
  Function(ThemeMode)? changeTheme;
  Function(String)? changeTitleBar;

  void setContext(BuildContext ctx) => _context = ctx;

  void execute(String code) async {
    final cmd = code.trim();
    Logger.instance.add("DartP Exec: $cmd", LogType.system);

    try {
      // --- NAVIGATION ---
      if (cmd == "Navigator.pop()") {
        if (_context != null && Navigator.canPop(_context!))
          Navigator.pop(_context!);
      }

      // --- WINDOW CONTROL ---
      else if (cmd == "Window.minimize()")
        windowManager.minimize();
      else if (cmd == "Window.maximize()")
        windowManager.maximize();
      else if (cmd == "Window.restore()")
        windowManager.restore();
      else if (cmd == "Window.close()")
        windowManager.close();
      else if (cmd == "Window.center()")
        windowManager.center();

      // --- DEV TOOLS ---
      else if (cmd == "DevTools.toggle()")
        toggleDevTools?.call();
      else if (cmd == "DevTools.clearLogs()")
        Logger.instance.clear();

      // --- THEME ---
      else if (cmd == "Theme.dark()")
        changeTheme?.call(ThemeMode.dark);
      else if (cmd == "Theme.light()")
        changeTheme?.call(ThemeMode.light);
      else if (cmd == "Theme.system()")
        changeTheme?.call(ThemeMode.system);

      // --- SYSTEM ---
      else if (cmd.startsWith("Launch(")) {
        final url = _extractArg(cmd);
        if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
      } else if (cmd.startsWith("Print(")) {
        Logger.instance.add(_extractArg(cmd), LogType.info);
      } else {
        Logger.instance.add("Unknown DartP Command: $cmd", LogType.error);
      }
    } catch (e) {
      Logger.instance.add("DartP Error: $e", LogType.error);
    }
  }

  String _extractArg(String command) {
    final start = command.indexOf("('");
    final end = command.lastIndexOf("')");
    if (start != -1 && end != -1) {
      return command.substring(start + 2, end);
    }
    return "";
  }
}

// =============================================================================
// 3. UTILS & PARSERS
// =============================================================================

class Utils {
  // --- COLOR ---
  static Color? parseColor(dynamic val) {
    if (val is String) {
      if (val.startsWith('#'))
        return Color(
            int.parse(val.replaceAll('#', ''), radix: 16) + 0xFF000000);
      switch (val) {
        case 'white':
          return Colors.white;
        case 'black':
          return Colors.black;
        case 'blue':
          return Colors.blue;
        case 'red':
          return Colors.red;
        case 'green':
          return Colors.green;
        case 'grey':
          return Colors.grey;
        case 'transparent':
          return Colors.transparent;
        case 'orange':
          return Colors.orange;
        case 'purple':
          return Colors.purple;
        case 'teal':
          return Colors.teal;
        case 'amber':
          return Colors.amber;
      }
    }
    return null;
  }

  // --- EDGE INSETS ---
  static EdgeInsets parsePadding(dynamic v) {
    if (v is List && v.length == 4)
      return EdgeInsets.fromLTRB(
          v[0].toDouble(), v[1].toDouble(), v[2].toDouble(), v[3].toDouble());
    if (v is List && v.length == 2)
      return EdgeInsets.symmetric(
          horizontal: v[0].toDouble(), vertical: v[1].toDouble());
    if (v is num) return EdgeInsets.all(v.toDouble());
    return EdgeInsets.zero;
  }

  // --- ALIGNMENT ---
  static Alignment? parseAlign(String? v) {
    switch (v) {
      case 'center':
        return Alignment.center;
      case 'top_left':
        return Alignment.topLeft;
      case 'top_right':
        return Alignment.topRight;
      case 'bottom_left':
        return Alignment.bottomLeft;
      case 'bottom_right':
        return Alignment.bottomRight;
      case 'top_center':
        return Alignment.topCenter;
      case 'bottom_center':
        return Alignment.bottomCenter;
    }
    return null;
  }

  static MainAxisAlignment parseMainAlign(String? v) {
    switch (v) {
      case 'center':
        return MainAxisAlignment.center;
      case 'end':
        return MainAxisAlignment.end;
      case 'space_between':
        return MainAxisAlignment.spaceBetween;
      case 'space_around':
        return MainAxisAlignment.spaceAround;
      case 'space_evenly':
        return MainAxisAlignment.spaceEvenly;
      default:
        return MainAxisAlignment.start;
    }
  }

  static CrossAxisAlignment parseCrossAlign(String? v) {
    switch (v) {
      case 'center':
        return CrossAxisAlignment.center;
      case 'end':
        return CrossAxisAlignment.end;
      case 'stretch':
        return CrossAxisAlignment.stretch;
      default:
        return CrossAxisAlignment.start;
    }
  }

  // --- TEXT STYLE ---
  static TextStyle parseTextStyle(Map props) {
    return GoogleFonts.getFont(
      props['font'] ?? 'Roboto',
      fontSize: props['size']?.toDouble() ?? 14,
      color: parseColor(props['color']),
      fontWeight: props['bold'] == true ? FontWeight.bold : FontWeight.normal,
      fontStyle: props['italic'] == true ? FontStyle.italic : FontStyle.normal,
      decoration: props['underline'] == true
          ? TextDecoration.underline
          : TextDecoration.none,
      letterSpacing: props['letter_spacing']?.toDouble(),
    );
  }

  // --- ICON (USING ICONS.DART) ---
  static IconData parseIcon(String? name) {
    return IconMap.fromName(name); // icons.dart dagi metodni chaqiramiz
  }

  // --- SHAPES & BORDERS ---
  static OutlinedBorder? parseShape(dynamic val) {
    if (val is Map) {
      if (val['type'] == 'RoundedRectangleBorder') {
        return RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(val['radius']?.toDouble() ?? 0));
      }
      if (val['type'] == 'CircleBorder') return const CircleBorder();
      if (val['type'] == 'StadiumBorder') return const StadiumBorder();
      if (val['type'] == 'BeveledRectangleBorder') {
        return BeveledRectangleBorder(
            borderRadius:
                BorderRadius.circular(val['radius']?.toDouble() ?? 0));
      }
    }
    return null;
  }

  static BoxFit parseBoxFit(String? v) {
    switch (v) {
      case 'contain':
        return BoxFit.contain;
      case 'fill':
        return BoxFit.fill;
      case 'fitWidth':
        return BoxFit.fitWidth;
      case 'fitHeight':
        return BoxFit.fitHeight;
      default:
        return BoxFit.cover;
    }
  }

  static Gradient? parseGradient(dynamic val) {
    if (val is Map && val['colors'] is List) {
      return LinearGradient(
        colors: (val['colors'] as List).map((c) => parseColor(c)!).toList(),
        begin: parseAlign(val['begin']) ?? Alignment.topLeft,
        end: parseAlign(val['end']) ?? Alignment.bottomRight,
      );
    }
    return null;
  }
}

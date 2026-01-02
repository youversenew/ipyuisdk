// =============================================================================
// FILE: lib/devtools.dart
// PROJECT: IPYUI QUANTUM RUNTIME
// DESC: Advanced Browser-like Developer Tools (F12)
// FEATURES: Inspector, Real-time Logs, Network (Binary/JSON), CLI, State Control
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Engine bilan bog'liqliklar
import 'kernel.dart';
import 'utils.dart';
import 'connection.dart'; // Binary transport uchun

enum DevMode { console, inspector, network, sources, performance }

class NetworkPacket {
  final DateTime timestamp;
  final String direction; // 'IN' or 'OUT'
  final String type; // 'JSON', 'BINARY', 'DARTP'
  final dynamic data;
  final int size;

  NetworkPacket({
    required this.direction,
    required this.type,
    required this.data,
    required this.size,
  }) : timestamp = DateTime.now();
}

// =============================================================================
// 2. DEVTOOLS CORE MANAGER (State Management)
// =============================================================================

class DevToolsManager extends ChangeNotifier {
  static final DevToolsManager instance = DevToolsManager._internal();
  DevToolsManager._internal();

  bool isVisible = false;
  DevMode currentMode = DevMode.console;

  // Logs & History
  final List<LogEntry> logs = [];
  final List<NetworkPacket> packets = [];
  final List<String> cliHistory = [];

  // Inspector State
  Map<String, dynamic>? selectedNode;
  bool isInspecting = false;

  void toggle() {
    isVisible = !isVisible;
    notifyListeners();
  }

  void addLog(String msg, [LogType type = LogType.info]) {
    logs.add(LogEntry(msg, type));
    if (logs.length > 500) logs.removeAt(0);
    notifyListeners();
  }

  void addPacket(String dir, String type, dynamic data, int size) {
    packets
        .add(NetworkPacket(direction: dir, type: type, data: data, size: size));
    if (packets.length > 200) packets.removeAt(0);
    notifyListeners();
  }

  void selectNode(Map<String, dynamic> node) {
    selectedNode = node;
    currentMode = DevMode.inspector;
    notifyListeners();
  }
}

// =============================================================================
// 3. THE DEVTOOLS WIDGET
// =============================================================================

class DevToolsOverlay extends StatefulWidget {
  final Widget child; // Asosiy ilova
  const DevToolsOverlay({super.key, required this.child});

  @override
  State<DevToolsOverlay> createState() => _DevToolsOverlayState();
}

class _DevToolsOverlayState extends State<DevToolsOverlay>
    with SingleTickerProviderStateMixin {
  final DevToolsManager _dt = DevToolsManager.instance;
  double _height = 400;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        children: [
          // LAYER 1: ASOSIY ILOVA
          widget.child,

          // LAYER 2: INSPECTOR HIGHLIGHTER (Overlay)
          if (_dt.isInspecting)
            Positioned.fill(
              child: GestureDetector(
                onTapDown: (details) {
                  // TODO: Get element at position logic
                },
                child: Container(color: Colors.blue.withOpacity(0.1)),
              ),
            ),

          // LAYER 3: DEVTOOLS PANEL (Bottom Sheet style)
          if (_dt.isVisible)
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                height: _height,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  border: Border(
                      top: BorderSide(
                          color: Colors.greenAccent.withOpacity(0.5),
                          width: 2)),
                  boxShadow: const [
                    BoxShadow(blurRadius: 20, color: Colors.black)
                  ],
                ),
                child: Column(
                  children: [
                    _buildResizeBar(),
                    _buildHeader(),
                    Expanded(child: _buildBody()),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- RESIZE HANDLE ---
  Widget _buildResizeBar() {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          _height = (_height - details.delta.dy)
              .clamp(100.0, MediaQuery.of(context).size.height - 50);
        });
      },
      child: Container(
        height: 6,
        width: double.infinity,
        color: Colors.black38,
        child: Center(
            child: Container(width: 40, height: 2, color: Colors.white24)),
      ),
    );
  }

  // --- TAB BAR ---
  Widget _buildHeader() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Icon(Icons.bug_report, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 10),
          _tabBtn("Console", DevMode.console),
          _tabBtn("Inspector", DevMode.inspector),
          _tabBtn("Network", DevMode.network),
          _tabBtn("Sources", DevMode.sources),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.find_in_page,
                color: _dt.isInspecting ? Colors.blue : Colors.white54,
                size: 18),
            onPressed: () =>
                setState(() => _dt.isInspecting = !_dt.isInspecting),
            tooltip: "Inspect Element",
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            onPressed: () => _dt.toggle(),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, DevMode mode) {
    bool active = _dt.currentMode == mode;
    return InkWell(
      onTap: () => setState(() => _dt.currentMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: active ? Colors.greenAccent : Colors.transparent,
                  width: 2)),
        ),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                color: active ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  // --- MODES BODY ---
  Widget _buildBody() {
    switch (_dt.currentMode) {
      case DevMode.console:
        return const ConsoleView();
      case DevMode.inspector:
        return const InspectorView();
      case DevMode.network:
        return const NetworkView();
      case DevMode.sources:
        return const SourcesView();
      default:
        return const Center(child: Text("Coming Soon"));
    }
  }
}

// =============================================================================
// 4. CONSOLE VIEW (CLI)
// =============================================================================

class ConsoleView extends StatefulWidget {
  const ConsoleView({super.key});

  @override
  State<ConsoleView> createState() => _ConsoleViewState();
}

class _ConsoleViewState extends State<ConsoleView> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  void _executeCommand(String val) {
    if (val.isEmpty) return;
    DevToolsManager.instance.addLog(">>> $val", LogType.cli);

    // Command Parser
    final cmd = val.trim().toLowerCase();

    if (cmd == "help") {
      DevToolsManager.instance.addLog(
          "Available: help, clear, ui [mode], run [json], binary [hex], exit",
          LogType.info);
    } else if (cmd.startsWith("run ")) {
      try {
        final jsonStr = val.substring(4);
        final tree = jsonDecode(jsonStr);
        IpyKernel.instance.processManualUI(tree);
      } catch (e) {
        DevToolsManager.instance.addLog("JSON Error: $e", LogType.error);
      }
    } else if (cmd.startsWith("ui ")) {
      final mode = cmd.split(" ")[1];
      IpyKernel.instance.config['ui_mode'] = mode;
      IpyKernel.instance.forceNotify();
    } else if (cmd == "exit") {
      SystemNavigator.pop();
    } else {
      DevToolsManager.instance.addLog("Unknown command: $cmd", LogType.error);
    }

    _input.clear();
    Timer(const Duration(milliseconds: 50),
        () => _scroll.jumpTo(_scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: DevToolsManager.instance,
            builder: (context, _) {
              final logs = DevToolsManager.instance.logs;
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(10),
                itemCount: logs.length,
                itemBuilder: (context, i) {
                  final log = logs[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: "[${log.timeString}] ",
                          style: const TextStyle(
                              color: Colors.white24, fontSize: 10)),
                      TextSpan(
                          text: log.message,
                          style: TextStyle(
                              color: log.color,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                    ])),
                  );
                },
              );
            },
          ),
        ),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: TextField(
            controller: _input,
            style: const TextStyle(
                color: Colors.greenAccent,
                fontFamily: 'monospace',
                fontSize: 13),
            decoration: const InputDecoration(
              icon: Icon(Icons.chevron_right,
                  color: Colors.greenAccent, size: 18),
              border: InputBorder.none,
              hintText: "Enter JSON or Command...",
              hintStyle: TextStyle(color: Colors.white10),
            ),
            onSubmitted: _executeCommand,
          ),
        )
      ],
    );
  }
}

// =============================================================================
// 5. INSPECTOR VIEW (Visual Tree)
// =============================================================================

class InspectorView extends StatelessWidget {
  const InspectorView({super.key});

  @override
  Widget build(BuildContext context) {
    final dt = DevToolsManager.instance;
    final tree = IpyKernel.instance.uiTree;

    return Row(
      children: [
        // Left: Tree Navigation
        Expanded(
          flex: 1,
          child: Container(
            decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.white10))),
            child: tree == null
                ? const Center(
                    child: Text("No UI Tree",
                        style: TextStyle(color: Colors.white24)))
                : _buildTreeNode(tree, 0),
          ),
        ),
        // Right: Properties
        Expanded(
          flex: 1,
          child: dt.selectedNode == null
              ? const Center(
                  child: Text("Select an element",
                      style: TextStyle(color: Colors.white24)))
              : _buildProperties(dt.selectedNode!),
        ),
      ],
    );
  }

  Widget _buildTreeNode(Map<String, dynamic> node, int depth) {
    final String type = node['type'] ?? 'box';
    final List? children = node['children'];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => DevToolsManager.instance.selectNode(node),
            child: Padding(
              padding: EdgeInsets.only(left: 10.0 * depth, top: 4, bottom: 4),
              child: Text(
                  "<$type id='${node['id']?.toString().substring(0, 4)}...'>",
                  style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                      fontFamily: 'monospace')),
            ),
          ),
          if (children != null)
            for (var child in children) _buildTreeNode(child, depth + 1),
          Padding(
            padding: EdgeInsets.only(left: 10.0 * depth),
            child: Text("</$type>",
                style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildProperties(Map<String, dynamic> node) {
    final props = node['props'] ?? {};
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Text("PROPERTIES: ${node['type']}",
            style: const TextStyle(
                color: Colors.greenAccent, fontWeight: FontWeight.bold)),
        const Divider(color: Colors.white10),
        for (var key in props.keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Text("$key: ",
                    style: const TextStyle(
                        color: Colors.blueAccent, fontSize: 11)),
                Text(props[key].toString(),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// 6. NETWORK VIEW (Traffic Monitor)
// =============================================================================

class NetworkView extends StatelessWidget {
  const NetworkView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DevToolsManager.instance,
      builder: (context, _) {
        final packets = DevToolsManager.instance.packets;
        return ListView.separated(
          padding: const EdgeInsets.all(10),
          itemCount: packets.length,
          separatorBuilder: (_, __) =>
              const Divider(color: Colors.white10, height: 1),
          itemBuilder: (context, i) {
            final p = packets[packets.length - 1 - i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.direction == 'IN' ? Colors.green : Colors.blue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(p.direction,
                        style: const TextStyle(
                            fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Text(p.type,
                      style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 15),
                  Expanded(
                      child: Text(p.data.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11))),
                  Text("${(p.size / 1024).toStringAsFixed(2)} KB",
                      style:
                          const TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// =============================================================================
// 7. SOURCES VIEW (Logic & JSON Assets)
// =============================================================================

class SourcesView extends StatelessWidget {
  const SourcesView({super.key});

  @override
  Widget build(BuildContext context) {
    final kernel = IpyKernel.instance;
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("ACTIVE CONFIGURATION",
              style: TextStyle(
                  color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: Colors.black26,
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(kernel.config),
                style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'monospace',
                    fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 8. BINARY DECODER/ENCODER UTILS
// =============================================================================

class BinaryUtils {
  static String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  static Uint8List hexToBytes(String hex) {
    hex = hex.replaceAll(' ', '');
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}

// =============================================================================
// FILE: lib/renderers/fluent_renderer.dart
// SYSTEM: FLUENT UI RENDERER (Windows 11 Style) - FIXED VERSION
// STATUS: COMPILES SUCCESSFULLY
// =============================================================================

import 'package:fluent_ui/fluent_ui.dart';
// Materialdan faqat kerakli narsalarni olamiz, Colors va TextTheme to'qnashmasligi uchun
import 'package:flutter/material.dart' show Icons, MaterialColor;
import '../utils.dart';

typedef EventCallback = void Function(String id, String event, dynamic value);

class FluentRenderer {
  static Widget build(Map<String, dynamic> node, EventCallback onEvent) {
    try {
      final String type = node['type'];
      final Map<String, dynamic> props = node['props'] ?? {};
      final String id = node['id'] ?? '';
      final List<dynamic> childrenData = node['children'] ?? [];

      // Bolalarni yaratish funksiyasi
      List<Widget> children() =>
          childrenData.map((c) => build(c, onEvent)).toList();
      Widget? child() =>
          childrenData.isNotEmpty ? build(childrenData.first, onEvent) : null;

      switch (type) {
        // ============================================================
        // 🪟 FLUENT APP STRUCTURE
        // ============================================================
        case 'FluentApp':
          return FluentApp(
            title: props['title'] ?? '',
            debugShowCheckedModeBanner: false,
            themeMode:
                props['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light,
            theme: FluentThemeData(
              accentColor:
                  _toAccentColor(Utils.parseColor(props['accent_color'])),
              brightness: Brightness.light,
              visualDensity: VisualDensity.standard,
            ),
            darkTheme: FluentThemeData(
              accentColor:
                  _toAccentColor(Utils.parseColor(props['accent_color'])),
              brightness: Brightness.dark,
              visualDensity: VisualDensity.standard,
            ),
            home: child(),
          );
        // case 'NavigationView':
        //   final int selectedIndex = props['selected_index'] ?? 0;
        //   final List<Widget> pages = children();

        //   // Index xatoligini oldini olish uchun tekshiruv
        //   final int safeIndex =
        //       pages.isEmpty ? 0 : selectedIndex.clamp(0, pages.length - 1);

        //   return NavigationView(
        //     appBar: props['app_bar'] != null
        //         ? NavigationAppBar(
        //             title: Text(props['app_bar']['title'] ?? ''),
        //             automaticallyImplyLeading: false,
        //           )
        //         : null,
        //     pane: NavigationPane(
        //       selected: selectedIndex,
        //       onChanged: (index) => onEvent(id, 'navigate', index),
        //       // Helper funksiyalar ham f. turlarini qaytarishi kerak
        //       displayMode: _parseDisplayMode(props['display_mode']),
        //       header: props['header'] != null
        //           ? Padding(
        //               padding: const EdgeInsets.only(left: 10),
        //               child: Text(props['header']))
        //           : null,
        //       items: _parsePaneItems(props['items'], onEvent),
        //       footerItems: _parsePaneItems(props['footer_items'], onEvent),
        //     ),

        //     // 🔥 MUHIM TUZATISH: f.NavigationBody
        //     content: NavigationBody(
        //       index: safeIndex,
        //       children: pages,
        //       transitionBuilder: (child, animation) {
        //         // 🔥 MUHIM TUZATISH: f.DrillInPageTransition
        //         return DrillInPageTransition(
        //           animation: animation,
        //           child: child,
        //         );
        //       },
        //     ),
        //   );

        case 'ScaffoldPage':
          return ScaffoldPage(
            header: props['header'] != null
                ? PageHeader(title: Text(props['header']))
                : null,
            content: Padding(
              padding: Utils.parsePadding(props['padding']),
              child: child() ?? const SizedBox(),
            ),
          );

        // ============================================================
        // 🔘 BUTTONLAR
        // ============================================================
        case 'Button':
          return Button(
            onPressed: props['disabled'] == true
                ? null
                : () => onEvent(id, 'click', null),
            style: ButtonStyle(
              backgroundColor: _parseButtonStateColor(props['bg_color']),
            ),
            child: child() ?? Text(props['text'] ?? 'Button'),
          );

        case 'FilledButton':
          return FilledButton(
            onPressed: props['disabled'] == true
                ? null
                : () => onEvent(id, 'click', null),
            style: ButtonStyle(
              backgroundColor: _parseButtonStateColor(props['bg_color']),
            ),
            child: child() ?? Text(props['text'] ?? 'Filled Button'),
          );

        case 'HyperlinkButton':
          return HyperlinkButton(
            onPressed: () => onEvent(id, 'click', null),
            child: child() ?? Text(props['text'] ?? 'Link'),
          );

        case 'IconButton':
          return IconButton(
            icon: Icon(Utils.parseIcon(props['icon']),
                size: props['size']?.toDouble(),
                color: Utils.parseColor(props['color'])),
            onPressed: () => onEvent(id, 'click', null),
          );

        case 'ToggleButton':
          return ToggleButton(
            checked: props['checked'] == true,
            onChanged: (v) => onEvent(id, 'change', v),
            child: child() ?? Text(props['text'] ?? 'Toggle'),
          );

        case 'DropDownButton':
          return DropDownButton(
            title: Text(props['text'] ?? 'Select'),
            items: (props['items'] as List? ?? [])
                .map((item) => MenuFlyoutItem(
                      text: Text(item['text']),
                      onPressed: () => onEvent(id, 'select', item['value']),
                      leading: item['icon'] != null
                          ? Icon(Utils.parseIcon(item['icon']))
                          : null,
                    ))
                .toList(),
          );

        // ============================================================
        // ✍️ INPUT / FORM
        // ============================================================
        case 'TextBox':
          return TextBox(
            placeholder: props['placeholder'],
            controller: TextEditingController(text: props['value']),
            expands: props['expands'] == true,
            maxLines: props['max_lines'],
            obscureText: props['obscure'] == true,
            readOnly: props['read_only'] == true,
            prefix: props['icon'] != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Utils.parseIcon(props['icon'])))
                : null,
            onChanged: (v) => onEvent(id, 'change', v),
            onSubmitted: (v) => onEvent(id, 'submit', v),
          );

        case 'PasswordBox':
          return PasswordBox(
            placeholder: props['placeholder'] ?? 'Password',
            onChanged: (v) => onEvent(id, 'change', v),
            revealMode: PasswordRevealMode.peek,
          );

        // FIX: NumberBox generic type aniq Double bo'lishi kerak
        case 'NumberBox':
          return NumberBox<double>(
            value: (props['value'] as num?)?.toDouble(),
            min: (props['min'] as num?)?.toDouble(),
            max: (props['max'] as num?)?.toDouble(),
            onChanged: (v) => onEvent(id, 'change', v),
            mode: SpinButtonPlacementMode.inline,
          );

        case 'AutoSuggestBox':
          return AutoSuggestBox<String>(
            placeholder: props['placeholder'],
            items: (props['items'] as List? ?? [])
                .map((e) => AutoSuggestBoxItem<String>(
                    value: e.toString(), label: e.toString()))
                .toList(),
            onSelected: (item) => onEvent(id, 'select', item.value),
            onChanged: (text, reason) => onEvent(id, 'change', text),
          );

        case 'ComboBox':
          return ComboBox<String>(
            value: props['value']?.toString(),
            placeholder: Text(props['placeholder'] ?? 'Select'),
            items: (props['items'] as List? ?? [])
                .map((e) => ComboBoxItem<String>(
                      value: e.toString(),
                      child: Text(e.toString()),
                    ))
                .toList(),
            onChanged: (v) => onEvent(id, 'change', v),
          );

        case 'DatePicker':
          return DatePicker(
            selected: DateTime.tryParse(props['value'] ?? '') ?? DateTime.now(),
            onChanged: (v) => onEvent(id, 'change', v.toIso8601String()),
          );

        case 'TimePicker':
          return TimePicker(
            selected: DateTime.tryParse(props['value'] ?? '') ?? DateTime.now(),
            onChanged: (v) => onEvent(id, 'change', v.toIso8601String()),
          );

        // ============================================================
        // ☑️ CHECK / SWITCH
        // ============================================================
        case 'Checkbox':
          return Checkbox(
            checked: props['value'] == true,
            onChanged: (v) => onEvent(id, 'change', v),
            content: props['label'] != null ? Text(props['label']) : null,
          );

        case 'ToggleSwitch':
          return ToggleSwitch(
            checked: props['value'] == true,
            onChanged: (v) => onEvent(id, 'change', v),
            content: props['label'] != null ? Text(props['label']) : null,
          );

        case 'RadioButton':
          return RadioButton(
            checked: props['value'] == true,
            onChanged: (v) => onEvent(id, 'change', v),
            content: props['label'] != null ? Text(props['label']) : null,
          );

        case 'Slider':
          return Slider(
            value: (props['value'] ?? 0).toDouble(),
            min: (props['min'] ?? 0).toDouble(),
            max: (props['max'] ?? 100).toDouble(),
            onChanged: (v) => onEvent(id, 'change', v),
            label: props['show_label'] == true ? '${props['value']}' : null,
          );

        // ============================================================
        // 📊 FEEDBACK / STATE
        // ============================================================
        case 'ProgressBar':
          return ProgressBar(
            value: props['value'] != null
                ? (props['value'] as num).toDouble()
                : null,
          );

        case 'ProgressRing':
          return ProgressRing(
            value: props['value'] != null
                ? (props['value'] as num).toDouble()
                : null,
          );

        case 'InfoBar':
          return InfoBar(
            title: Text(props['title'] ?? ''),
            content: props['content'] != null ? Text(props['content']) : null,
            severity: _parseSeverity(props['severity']),
            isLong: props['is_long'] == true,
            onClose: () => onEvent(id, 'close', null),
          );

        // FIX: Tooltip child null bo'lmasligi kerak
        case 'Tooltip':
          return Tooltip(
            message: props['message'] ?? '',
            displayHorizontally: props['horizontal'] == true,
            child: child() ?? const SizedBox(),
          );

        // ============================================================
        // 🃏 CARD / SURFACE
        // ============================================================
        case 'Card':
          return Card(
            backgroundColor: Utils.parseColor(props['bg_color']),
            borderRadius:
                BorderRadius.circular(props['radius']?.toDouble() ?? 4.0),
            padding: Utils.parsePadding(props['padding']),
            child: child() ?? const SizedBox(),
          );

        case 'Expander':
          return Expander(
            header: Text(props['header'] ?? ''),
            initiallyExpanded: props['expanded'] == true,
            content: child() ?? const SizedBox(),
            onStateChanged: (v) => onEvent(id, 'toggle', v),
          );

        case 'Mica':
          return Mica(
            backgroundColor: Utils.parseColor(props['bg_color']),
            child: child() ?? const SizedBox(),
          );

        // FIX: Acrylic parametrlari o'zgargan
        case 'Acrylic':
          return Acrylic(
            tint: Utils.parseColor(props['tint']) ?? Colors.transparent,
            elevation: props['elevation']?.toDouble() ?? 0,
            child: child() ?? const SizedBox(),
          );

        // ============================================================
        // 📜 LIST / TABLE
        // ============================================================
        case 'ListView':
          return ListView(
            padding: Utils.parsePadding(props['padding']),
            children: children(),
          );

        case 'ListTile':
          return ListTile(
            leading: props['leading_icon'] != null
                ? Icon(Utils.parseIcon(props['leading_icon']))
                : null,
            title: Text(props['title'] ?? ''),
            subtitle:
                props['subtitle'] != null ? Text(props['subtitle']) : null,
            trailing: props['trailing_icon'] != null
                ? Icon(Utils.parseIcon(props['trailing_icon']))
                : null,
            onPressed: () => onEvent(id, 'click', null),
          );

        // ============================================================
        // 📦 LAYOUT (Universal)
        // ============================================================
        case 'Container':
        case 'box':
          return Container(
            width: props['width']?.toDouble(),
            height: props['height']?.toDouble(),
            margin: Utils.parsePadding(props['margin']),
            padding: Utils.parsePadding(props['padding']),
            alignment: Utils.parseAlign(props['alignment']),
            decoration: BoxDecoration(
              color: Utils.parseColor(props['bg_color']),
              borderRadius:
                  BorderRadius.circular(props['radius']?.toDouble() ?? 0),
              border: props['border_color'] != null
                  ? Border.all(
                      color: Utils.parseColor(props['border_color'])!,
                      width: props['border_width']?.toDouble() ?? 1)
                  : null,
            ),
            child: child(),
          );

        case 'Row':
          return Row(
            mainAxisAlignment: Utils.parseMainAlign(props['align']),
            crossAxisAlignment: Utils.parseCrossAlign(props['cross_align']),
            children: children(),
          );

        case 'Column':
          return Column(
            mainAxisAlignment: Utils.parseMainAlign(props['align']),
            crossAxisAlignment: Utils.parseCrossAlign(props['cross_align']),
            children: children(),
          );

        case 'Stack':
          return Stack(
            alignment: Utils.parseAlign(props['align']) ?? Alignment.topLeft,
            children: children(),
          );

        case 'Center':
          return Center(child: child());

        case 'Expanded':
          return Expanded(
              flex: props['flex'] ?? 1, child: child() ?? const SizedBox());

        case 'Padding':
          return Padding(
              padding: Utils.parsePadding(props['padding']),
              child: child() ?? const SizedBox());

        case 'SizedBox':
          return SizedBox(
              width: props['width']?.toDouble(),
              height: props['height']?.toDouble());

        case 'Spacer':
          return Spacer(flex: props['flex'] ?? 1);

        // ============================================================
        // 🖼️ ICON / MEDIA
        // ============================================================
        case 'Icon':
          return Icon(
            Utils.parseIcon(props['icon']),
            size: props['size']?.toDouble() ?? 24,
            color: Utils.parseColor(props['color']),
          );

        // Default Error Box
        default:
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: Colors.orange)),
            child: Text("Unknown Fluent Widget: $type",
                style: TextStyle(color: Colors.orange)),
          );
      }
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(10),
        color: Colors.red,
        child: Text("Fluent Render Error: $e",
            style: const TextStyle(color: Colors.white)),
      );
    }
  }

  // ============================================================
  // 🔧 HELPERS (TUZATILGAN)
  // ============================================================

  // FIX: Oddiy Color ni Fluent AccentColor ga o'girish
  static AccentColor? _toAccentColor(Color? color) {
    if (color == null) return null;
    return AccentColor.swatch({
      'normal': color,
      'dark': color,
      'light': color,
      'darker': color,
      'lighter': color,
      'darkest': color,
    });
  }

  // FIX: ButtonState to'g'ri ishlatilishi
  static ButtonState<Color?>? _parseButtonStateColor(String? hex) {
    if (hex == null) return null;
    final color = Utils.parseColor(hex);
    return ButtonState.all(color);
  }

  static PaneDisplayMode _parseDisplayMode(String? val) {
    switch (val) {
      case 'open':
        return PaneDisplayMode.open;
      case 'compact':
        return PaneDisplayMode.compact;
      case 'minimal':
        return PaneDisplayMode.minimal;
      case 'top':
        return PaneDisplayMode.top;
      default:
        return PaneDisplayMode.auto;
    }
  }

  static InfoBarSeverity _parseSeverity(String? val) {
    switch (val) {
      case 'success':
        return InfoBarSeverity.success;
      case 'warning':
        return InfoBarSeverity.warning;
      case 'error':
        return InfoBarSeverity.error;
      default:
        return InfoBarSeverity.info;
    }
  }

  static List<NavigationPaneItem> _parsePaneItems(
      List<dynamic>? items, EventCallback onEvent) {
    if (items == null) return [];
    return items.map<NavigationPaneItem>((item) {
      final type = item['type'];
      final props = item['props'] ?? {};
      final id = item['id'] ?? '';

      if (type == 'PaneItemSeparator') {
        return PaneItemSeparator();
      } else if (type == 'PaneItemHeader') {
        return PaneItemHeader(header: Text(props['text'] ?? ''));
      } else {
        return PaneItem(
            icon: Icon(Utils.parseIcon(props['icon'])),
            title: Text(props['text'] ?? ''),
            body: const SizedBox
                .shrink(), // Body NavigationView tomonidan boshqariladi
            onTap: () {
              // Opsional: Agar bosilganda alohida event kerak bo'lsa
              if (id.isNotEmpty) onEvent(id, 'click', null);
            });
      }
    }).toList();
  }
}

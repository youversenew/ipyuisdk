import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // Ba'zi umumiy turlar uchun (Colors, Icons fallback)
import '../utils.dart'; // Utils sinfini ulash

typedef EventCallback = void Function(String id, String event, dynamic value);

class CupertinoRenderer {
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
        // 🍏 APP STRUCTURE
        // ============================================================
        case 'CupertinoApp':
          return CupertinoApp(
            title: props['title'] ?? '',
            debugShowCheckedModeBanner: false,
            theme: CupertinoThemeData(
              primaryColor: Utils.parseColor(props['primary_color']),
              brightness:
                  props['theme'] == 'dark' ? Brightness.dark : Brightness.light,
            ),
            home: child(),
          );

        case 'CupertinoPageScaffold':
          return CupertinoPageScaffold(
            navigationBar: props['navigation_bar'] != null
                ? build(props['navigation_bar'], onEvent)
                    as ObstructingPreferredSizeWidget
                : null,
            backgroundColor: Utils.parseColor(props['bg_color']),
            child: SafeArea(
              top: props['safe_area_top'] ?? true,
              bottom: props['safe_area_bottom'] ?? true,
              child: child() ?? const SizedBox(),
            ),
          );

        case 'CupertinoTabScaffold':
          // Murakkab struktura, bu yerda soddalashtirilgan
          return CupertinoTabScaffold(
            tabBar: build(props['tab_bar'], onEvent) as CupertinoTabBar,
            tabBuilder: (context, index) {
              // Real loyihada bu yerda indexga qarab view tanlanadi
              // Python "views": [child1, child2] yuborishi kerak
              if (props['views'] != null &&
                  index < (props['views'] as List).length) {
                return build(props['views'][index], onEvent);
              }
              return Center(child: Text("Tab $index"));
            },
          );

        // ============================================================
        // 🧭 NAVIGATION
        // ============================================================
        case 'CupertinoNavigationBar':
          return CupertinoNavigationBar(
            middle: props['title'] != null ? Text(props['title']) : null,
            leading: props['leading'] != null
                ? build(props['leading'], onEvent)
                : null,
            trailing: props['trailing'] != null
                ? build(props['trailing'], onEvent)
                : null,
            backgroundColor: Utils.parseColor(props['bg_color']),
          );

        case 'CupertinoSliverNavigationBar':
          return CupertinoSliverNavigationBar(
            largeTitle: Text(props['title'] ?? ''),
            leading: props['leading'] != null
                ? build(props['leading'], onEvent)
                : null,
            trailing: props['trailing'] != null
                ? build(props['trailing'], onEvent)
                : null,
            backgroundColor: Utils.parseColor(props['bg_color']),
          );

        case 'CupertinoTabBar':
          return CupertinoTabBar(
            onTap: (index) => onEvent(id, 'tab_change', index),
            currentIndex: props['current_index'] ?? 0,
            backgroundColor: Utils.parseColor(props['bg_color']),
            items: (props['items'] as List)
                .map((item) => BottomNavigationBarItem(
                      icon: Icon(_parseCupertinoIcon(item['icon'])),
                      label: item['label'],
                    ))
                .toList(),
          );

        // ============================================================
        // 🔘 BUTTONS
        // ============================================================
        case 'CupertinoButton':
          return CupertinoButton(
            onPressed: props['disabled'] == true
                ? null
                : () => onEvent(id, 'click', null),
            color: Utils.parseColor(props[
                'bg_color']), // Agar null bo'lsa, oddiy text button bo'ladi
            padding: Utils.parsePadding(props['padding']),
            borderRadius:
                BorderRadius.circular(props['radius']?.toDouble() ?? 8.0),
            child: child() ?? Text(props['text'] ?? 'Button'),
          );

        case 'CupertinoButton.filled':
          return CupertinoButton.filled(
            onPressed: props['disabled'] == true
                ? null
                : () => onEvent(id, 'click', null),
            padding: Utils.parsePadding(props['padding']),
            borderRadius:
                BorderRadius.circular(props['radius']?.toDouble() ?? 8.0),
            child: child() ?? Text(props['text'] ?? 'Button'),
          );

        case 'CupertinoContextMenu':
          return CupertinoContextMenu(
            actions: (props['actions'] as List)
                .map((a) => CupertinoContextMenuAction(
                      onPressed: () {
                        onEvent(id, 'action', a['value']);
                        // Navigator.pop(context); // Context yo'qligi uchun DartP ishlatiladi
                      },
                      isDestructiveAction: a['destructive'] == true,
                      trailingIcon: _parseCupertinoIcon(a['icon']),
                      child: Text(a['text']),
                    ))
                .toList(),
            child: child()!,
          );

        // ============================================================
        // ✍️ INPUT / FORM
        // ============================================================
        case 'CupertinoTextField':
          return CupertinoTextField(
            placeholder: props['placeholder'],
            obscureText: props['obscure'] == true,
            padding: Utils.parsePadding(props['padding']) == EdgeInsets.zero
                ? const EdgeInsets.all(12)
                : Utils.parsePadding(props['padding']),
            prefix: props['prefix_icon'] != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Icon(_parseCupertinoIcon(props['prefix_icon'])))
                : null,
            suffix: props['suffix_icon'] != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(_parseCupertinoIcon(props['suffix_icon'])))
                : null,
            decoration: BoxDecoration(
              color: Utils.parseColor(props['bg_color']) ??
                  CupertinoColors.tertiarySystemFill,
              borderRadius:
                  BorderRadius.circular(props['radius']?.toDouble() ?? 8),
            ),
            onChanged: (v) => onEvent(id, 'change', v),
            onSubmitted: (v) => onEvent(id, 'submit', v),
          );

        case 'CupertinoSearchTextField':
          return CupertinoSearchTextField(
            placeholder: props['placeholder'] ?? 'Search',
            backgroundColor: Utils.parseColor(props['bg_color']),
            onChanged: (v) => onEvent(id, 'search', v),
            onSubmitted: (v) => onEvent(id, 'submit', v),
          );

        case 'CupertinoFormSection':
          return CupertinoFormSection.insetGrouped(
            header: props['header'] != null ? Text(props['header']) : null,
            footer: props['footer'] != null ? Text(props['footer']) : null,
            children: children(),
          );

        case 'CupertinoFormRow':
          return CupertinoFormRow(
            prefix: props['label'] != null ? Text(props['label']) : null,
            helper: props['helper'] != null ? Text(props['helper']) : null,
            error: props['error'] != null ? Text(props['error']) : null,
            child: child()!,
          );

        // ============================================================
        // 🎚️ SWITCH / CONTROL
        // ============================================================
        case 'CupertinoSwitch':
          return CupertinoSwitch(
            value: props['value'] == true,
            activeColor: Utils.parseColor(props['active_color']) ??
                CupertinoColors.activeGreen,
            onChanged: (v) => onEvent(id, 'change', v),
          );

        case 'CupertinoSlider':
          return CupertinoSlider(
            value: (props['value'] ?? 0).toDouble(),
            min: (props['min'] ?? 0).toDouble(),
            max: (props['max'] ?? 100).toDouble(),
            activeColor: Utils.parseColor(props['active_color']) ??
                CupertinoColors.activeBlue,
            onChanged: (v) => onEvent(id, 'change', v),
          );

        case 'CupertinoSegmentedControl':
          // Children map bo'lishi kerak: {0: Text("A"), 1: Text("B")}
          // Pythondan list keladi: [{"value": "a", "label": "A"}, ...]

          // FIX: Map kalitini aniq 'Object' deb belgilaymiz (dynamic emas)
          final Map<Object, Widget> segments = {};

          if (props['items'] != null) {
            for (var item in props['items']) {
              // Null tekshiruv va Object ga cast qilish
              if (item['value'] != null) {
                segments[item['value'] as Object] = Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(item['label']?.toString() ?? ''),
                );
              }
            }
          }

          // FIX: Generik turni <Object> deb aniq yozamiz
          return CupertinoSegmentedControl<Object>(
            groupValue: props['group_value'] as Object?,
            children: segments,
            onValueChanged: (Object v) => onEvent(id, 'change', v),
          );
        // ============================================================
        // 🛞 PICKERLAR
        // ============================================================
        case 'CupertinoDatePicker':
          return SizedBox(
            height: 200,
            child: CupertinoDatePicker(
              mode: props['mode'] == 'date'
                  ? CupertinoDatePickerMode.date
                  : (props['mode'] == 'time'
                      ? CupertinoDatePickerMode.time
                      : CupertinoDatePickerMode.dateAndTime),
              onDateTimeChanged: (dt) =>
                  onEvent(id, 'change', dt.toIso8601String()),
            ),
          );

        case 'CupertinoTimerPicker':
          return SizedBox(
            height: 200,
            child: CupertinoTimerPicker(
              onTimerDurationChanged: (duration) =>
                  onEvent(id, 'change', duration.inSeconds),
            ),
          );

        // ============================================================
        // 🪟 DIALOG / OVERLAY (Widget sifatida)
        // ============================================================
        case 'CupertinoAlertDialog':
          return CupertinoAlertDialog(
            title: Text(props['title'] ?? ''),
            content: Text(props['content'] ?? ''),
            actions: (props['actions'] as List? ?? [])
                .map((a) => CupertinoDialogAction(
                      onPressed: () => onEvent(id, 'action', a['value']),
                      isDestructiveAction: a['destructive'] == true,
                      isDefaultAction: a['default'] == true,
                      child: Text(a['text']),
                    ))
                .toList(),
          );

        case 'CupertinoActionSheet':
          return CupertinoActionSheet(
            title: props['title'] != null ? Text(props['title']) : null,
            message: props['message'] != null ? Text(props['message']) : null,
            actions: (props['actions'] as List? ?? [])
                .map((a) => CupertinoActionSheetAction(
                      onPressed: () => onEvent(id, 'action', a['value']),
                      isDestructiveAction: a['destructive'] == true,
                      child: Text(a['text']),
                    ))
                .toList(),
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => onEvent(id, 'cancel', null),
              child: const Text('Cancel'),
            ),
          );

        // ============================================================
        // 🖼️ MEDIA & DISPLAY
        // ============================================================
        case 'CupertinoActivityIndicator':
          return CupertinoActivityIndicator(
            radius: (props['radius'] ?? 10).toDouble(),
            color: Utils.parseColor(props['color']),
          );

        case 'Icon': // Cupertino Style Icon
          return Icon(
            _parseCupertinoIcon(props['icon']),
            size: props['size']?.toDouble() ?? 24,
            color: Utils.parseColor(props['color']),
          );

        // ============================================================
        // 📦 LAYOUT (Material bilan umumiy, lekin bu yerda takrorlash kerak)
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

        case 'Expanded':
          return Expanded(
              flex: props['flex'] ?? 1, child: child() ?? const SizedBox());

        case 'Padding':
          return Padding(
              padding: Utils.parsePadding(props['padding']), child: child());

        case 'Center':
          return Center(child: child());

        case 'SizedBox':
          return SizedBox(
              width: props['width']?.toDouble(),
              height: props['height']?.toDouble(),
              child: child());

        case 'Spacer':
          return Spacer(flex: props['flex'] ?? 1);

        case 'SafeArea':
          return SafeArea(child: child() ?? const SizedBox());

        case 'SingleChildScrollView':
          return SingleChildScrollView(
            scrollDirection: props['direction'] == 'horizontal'
                ? Axis.horizontal
                : Axis.vertical,
            child: child(),
          );

        case 'ListView':
          return ListView(
            padding: Utils.parsePadding(props['padding']),
            children: children(),
          );

        // Default Error
        default:
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                border: Border.all(color: CupertinoColors.systemRed)),
            child: Text("Unknown Cupertino Widget: $type",
                style: const TextStyle(
                    color: CupertinoColors.systemRed, fontSize: 10)),
          );
      }
    } catch (e) {
      return Container(
        color: CupertinoColors.systemRed,
        padding: const EdgeInsets.all(10),
        child: Text("Render Error: $e",
            style: const TextStyle(color: Colors.white)),
      );
    }
  }

  // --- CUPERTINO ICON PARSER ---
  // iOS ga xos ikonkalarni map qilish
  static IconData _parseCupertinoIcon(String? name) {
    switch (name) {
      case 'home':
        return CupertinoIcons.home;
      case 'settings':
        return CupertinoIcons.settings;
      case 'person':
        return CupertinoIcons.person;
      case 'person_solid':
        return CupertinoIcons.person_solid;
      case 'add':
        return CupertinoIcons.add;
      case 'add_circled':
        return CupertinoIcons.add_circled;
      case 'delete':
        return CupertinoIcons.delete;
      case 'trash':
        return CupertinoIcons.trash;
      case 'edit':
        return CupertinoIcons.pencil;
      case 'search':
        return CupertinoIcons.search;
      case 'back':
        return CupertinoIcons.back;
      case 'forward':
        return CupertinoIcons.forward;
      case 'check':
        return CupertinoIcons.check_mark;
      case 'close':
        return CupertinoIcons.clear;
      case 'info':
        return CupertinoIcons.info;
      case 'share':
        return CupertinoIcons.share;
      case 'camera':
        return CupertinoIcons.camera;
      case 'photo':
        return CupertinoIcons.photo;
      case 'time':
        return CupertinoIcons.time;
      case 'calendar':
        return CupertinoIcons.calendar;
      case 'bell':
        return CupertinoIcons.bell;
      case 'heart':
        return CupertinoIcons.heart;
      case 'heart_fill':
        return CupertinoIcons.heart_fill;
      case 'star':
        return CupertinoIcons.star_fill;
      case 'wifi':
        return CupertinoIcons.wifi;
      case 'battery':
        return CupertinoIcons.battery_100;
      case 'folder':
        return CupertinoIcons.folder;
      case 'doc':
        return CupertinoIcons.doc;
      case 'mic':
        return CupertinoIcons.mic;
      case 'phone':
        return CupertinoIcons.phone;
      case 'mail':
        return CupertinoIcons.mail;
      case 'location':
        return CupertinoIcons.location;
      case 'lock':
        return CupertinoIcons.lock;
      case 'eye':
        return CupertinoIcons.eye;
      case 'eye_slash':
        return CupertinoIcons.eye_slash;
      default:
        return CupertinoIcons.question;
    }
  }
}

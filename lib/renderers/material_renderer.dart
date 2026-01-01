import 'package:flutter/material.dart';
import '../utils.dart'; // Utilsni ulaymiz

// Event yuborish uchun callback turi
typedef EventCallback = void Function(String id, String event, dynamic value);

class MaterialRenderer {
  // Asosiy Quruvchi (Factory)
  static Widget build(Map<String, dynamic> node, EventCallback onEvent) {
    try {
      final String type = node['type'];
      final Map<String, dynamic> props = node['props'] ?? {};
      final String id = node['id'] ?? '';
      final List<dynamic> childrenData = node['children'] ?? [];

      // Bolalarni rekursiv yaratish
      List<Widget> children() =>
          childrenData.map((c) => build(c, onEvent)).toList();
      Widget? child() =>
          childrenData.isNotEmpty ? build(childrenData.first, onEvent) : null;

      switch (type) {
        // ============================================================
        // 🔘 BUTTONS
        // ============================================================
        case 'ElevatedButton':
          return ElevatedButton(
            onPressed: props['disabled'] == true
                ? null
                : () => onEvent(id, 'click', null),
            style: ElevatedButton.styleFrom(
              backgroundColor: Utils.parseColor(props['bg_color']),
              foregroundColor: Utils.parseColor(props['color']),
              elevation: props['elevation']?.toDouble(),
              padding: Utils.parsePadding(props['padding']),
              shape: Utils.parseShape(props['shape']),
            ),
            child: child() ?? Text(props['text'] ?? ''),
          );

        case 'TextButton':
          return TextButton(
            onPressed: () => onEvent(id, 'click', null),
            style: TextButton.styleFrom(
                foregroundColor: Utils.parseColor(props['color'])),
            child: child() ?? Text(props['text'] ?? ''),
          );

        case 'OutlinedButton':
          return OutlinedButton(
            onPressed: () => onEvent(id, 'click', null),
            style: OutlinedButton.styleFrom(
              foregroundColor: Utils.parseColor(props['color']),
              side: BorderSide(
                  color:
                      Utils.parseColor(props['border_color']) ?? Colors.blue),
            ),
            child: child() ?? Text(props['text'] ?? ''),
          );

        case 'IconButton':
          return IconButton(
            icon: Icon(Utils.parseIcon(props['icon']),
                color: Utils.parseColor(props['color']),
                size: props['size']?.toDouble()),
            onPressed: () => onEvent(id, 'click', null),
            tooltip: props['tooltip'],
          );

        case 'FloatingActionButton':
          return FloatingActionButton(
            backgroundColor: Utils.parseColor(props['bg_color']),
            onPressed: () => onEvent(id, 'click', null),
            child: Icon(Utils.parseIcon(props['icon'])),
          );

        case 'PopupMenuButton':
          // Items python dan "items": [{"value": 1, "text": "A"}] kabi kelishi kerak
          return PopupMenuButton(
            onSelected: (val) => onEvent(id, 'select', val),
            itemBuilder: (ctx) => (props['items'] as List)
                .map((item) => PopupMenuItem(
                      value: item['value'],
                      child: Text(item['text']),
                    ))
                .toList(),
            icon: Icon(Utils.parseIcon(props['icon'] ?? 'more_vert')),
          );

        // ============================================================
        // ✍️ INPUT / FORM
        // ============================================================
        case 'TextField':
        case 'TextFormField': // Hozircha bir xil ishlaydi
          return Padding(
            padding: Utils.parsePadding(props['margin']),
            child: TextField(
              controller: TextEditingController(
                  text: props['value']), // State management kerak aslida
              obscureText: props['obscure'] == true,
              keyboardType: props['keyboard_type'] == 'number'
                  ? TextInputType.number
                  : TextInputType.text,
              maxLines: props['max_lines'] ?? 1,
              decoration: InputDecoration(
                labelText: props['label'],
                hintText: props['placeholder'],
                prefixIcon: props['prefix_icon'] != null
                    ? Icon(Utils.parseIcon(props['prefix_icon']))
                    : null,
                suffixIcon: props['suffix_icon'] != null
                    ? Icon(Utils.parseIcon(props['suffix_icon']))
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                        props['radius']?.toDouble() ?? 4)),
                filled: props['filled'] == true,
                fillColor: Utils.parseColor(props['bg_color']),
              ),
              onChanged: (v) => onEvent(id, 'change', v),
              onSubmitted: (v) => onEvent(id, 'submit', v),
            ),
          );

        case 'Checkbox':
          return Checkbox(
            value: props['value'] == true,
            activeColor: Utils.parseColor(props['active_color']),
            onChanged: (v) => onEvent(id, 'change', v),
          );

        case 'CheckboxListTile':
          return CheckboxListTile(
            value: props['value'] == true,
            title: Text(props['title'] ?? ''),
            subtitle:
                props['subtitle'] != null ? Text(props['subtitle']) : null,
            activeColor: Utils.parseColor(props['active_color']),
            onChanged: (v) => onEvent(id, 'change', v),
          );

        case 'Switch':
          return Switch(
            value: props['value'] == true,
            activeColor: Utils.parseColor(props['active_color']),
            onChanged: (v) => onEvent(id, 'change', v),
          );

        case 'SwitchListTile':
          return SwitchListTile(
            value: props['value'] == true,
            title: Text(props['title'] ?? ''),
            onChanged: (v) => onEvent(id, 'change', v),
          );

        case 'Radio':
          return Radio(
            value: props['value'],
            groupValue: props['group_value'],
            onChanged: (v) => onEvent(id, 'change', v),
          );

        case 'Slider':
          return Slider(
            value: (props['value'] ?? 0).toDouble(),
            min: (props['min'] ?? 0).toDouble(),
            max: (props['max'] ?? 100).toDouble(),
            activeColor: Utils.parseColor(props['active_color']),
            onChanged: (v) => onEvent(id, 'change', v),
          );

        // ============================================================
        // 📦 LAYOUT
        // ============================================================
        case 'Container':
        case 'box': // Universal Box
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
              boxShadow: props['shadow'] == true
                  ? [
                      const BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 4))
                    ]
                  : null,
            ),
            child: child(),
          );

        case 'Row':
          return Row(
            mainAxisAlignment: Utils.parseMainAlign(props['align']),
            crossAxisAlignment: Utils.parseCrossAlign(props['cross_align']),
            mainAxisSize: props['main_size'] == 'min'
                ? MainAxisSize.min
                : MainAxisSize.max,
            children: children(),
          );

        case 'Column':
          return Column(
            mainAxisAlignment: Utils.parseMainAlign(props['align']),
            crossAxisAlignment: Utils.parseCrossAlign(props['cross_align']),
            mainAxisSize: props['main_size'] == 'min'
                ? MainAxisSize.min
                : MainAxisSize.max,
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

        case 'Flexible':
          return Flexible(
              flex: props['flex'] ?? 1, child: child() ?? const SizedBox());

        case 'Padding':
          return Padding(
              padding: Utils.parsePadding(props['padding']), child: child());

        case 'Center':
          return Center(child: child());

        case 'Align':
          return Align(
              alignment:
                  Utils.parseAlign(props['alignment']) ?? Alignment.center,
              child: child());

        case 'SizedBox':
          return SizedBox(
              width: props['width']?.toDouble(),
              height: props['height']?.toDouble(),
              child: child());

        case 'Spacer':
          return Spacer(flex: props['flex'] ?? 1);

        case 'Wrap':
          return Wrap(
            spacing: props['spacing']?.toDouble() ?? 0,
            runSpacing: props['run_spacing']?.toDouble() ?? 0,
            alignment: WrapAlignment.start,
            children: children(),
          );

        case 'AspectRatio':
          return AspectRatio(
              aspectRatio: (props['ratio'] ?? 1).toDouble(), child: child());

        // ============================================================
        // 📜 SCROLL / LIST
        // ============================================================
        case 'ListView':
          return ListView(
            padding: Utils.parsePadding(props['padding']),
            scrollDirection: props['direction'] == 'horizontal'
                ? Axis.horizontal
                : Axis.vertical,
            shrinkWrap: props['shrink'] == true,
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
            onTap: () => onEvent(id, 'click', null),
            tileColor: Utils.parseColor(props['bg_color']),
          );

        case 'GridView':
          return GridView.count(
            crossAxisCount: props['cols'] ?? 2,
            childAspectRatio: (props['ratio'] ?? 1.0).toDouble(),
            padding: Utils.parsePadding(props['padding']),
            shrinkWrap: props['shrink'] == true,
            children: children(),
          );

        case 'SingleChildScrollView':
          return SingleChildScrollView(
            scrollDirection: props['direction'] == 'horizontal'
                ? Axis.horizontal
                : Axis.vertical,
            padding: Utils.parsePadding(props['padding']),
            child: child(),
          );

        // ============================================================
        // 🧭 NAVIGATION & STRUCTURE (Partial - usually defined in main shell)
        // ============================================================
        case 'Scaffold':
          // Scaffoldni ichma-ich ishlatib bo'lmaydi, lekin kerak bo'lsa:
          return Scaffold(
            appBar: props['app_bar'] != null
                ? AppBar(title: Text(props['app_bar']['title'] ?? ''))
                : null,
            body: child(),
            backgroundColor: Utils.parseColor(props['bg_color']),
            floatingActionButton:
                props['fab'] != null ? build(props['fab'], onEvent) : null,
          );

        case 'AppBar':
          return AppBar(
            title: Text(props['title'] ?? ''),
            centerTitle: props['center'] == true,
            backgroundColor: Utils.parseColor(props['bg_color']),
            elevation: props['elevation']?.toDouble(),
          );

        case 'Divider':
          return Divider(
            height: props['height']?.toDouble(),
            thickness: props['thickness']?.toDouble(),
            color: Utils.parseColor(props['color']),
          );

        case 'VerticalDivider':
          return VerticalDivider(
            width: props['width']?.toDouble(),
            thickness: props['thickness']?.toDouble(),
            color: Utils.parseColor(props['color']),
          );

        // ============================================================
        // 🖼️ MEDIA
        // ============================================================
        case 'Icon':
          return Icon(
            Utils.parseIcon(props['icon']),
            size: props['size']?.toDouble() ?? 24,
            color: Utils.parseColor(props['color']),
          );

        case 'Image':
        case 'Image.network':
          final src = props['src'] ?? '';
          return Image.network(
            src,
            width: props['width']?.toDouble(),
            height: props['height']?.toDouble(),
            fit: Utils.parseBoxFit(props['fit']),
          );

        case 'CircleAvatar':
          return CircleAvatar(
            radius: props['radius']?.toDouble(),
            backgroundColor: Utils.parseColor(props['bg_color']),
            backgroundImage:
                props['src'] != null ? NetworkImage(props['src']) : null,
            child: props['src'] == null ? child() : null,
          );

        // ============================================================
        // 🃏 CARD & SURFACE
        // ============================================================
        case 'Card':
          return Card(
            color: Utils.parseColor(props['bg_color']),
            elevation: props['elevation']?.toDouble(),
            margin: Utils.parsePadding(props['margin']),
            shape: Utils.parseShape(props['shape']),
            child: Padding(
              padding: Utils.parsePadding(props['padding']),
              child: child(),
            ),
          );

        case 'InkWell':
          return InkWell(
            onTap: () => onEvent(id, 'click', null),
            child: child(),
          );

        // ============================================================
        // 🎨 TEXT & STYLE
        // ============================================================
        case 'Text':
          return Text(
            props['value']?.toString() ?? '',
            style: Utils.parseTextStyle(props),
            textAlign:
                props['align'] == 'center' ? TextAlign.center : TextAlign.start,
            maxLines: props['max_lines'],
            overflow: props['max_lines'] != null ? TextOverflow.ellipsis : null,
          );

        case 'SelectableText':
          return SelectableText(
            props['value']?.toString() ?? '',
            style: Utils.parseTextStyle(props),
          );

        // ============================================================
        // ⏳ STATE / FEEDBACK
        // ============================================================
        case 'CircularProgressIndicator':
          return CircularProgressIndicator(
            value: props['value']?.toDouble(), // Null bo'lsa aylanib turadi
            color: Utils.parseColor(props['color']),
          );

        case 'LinearProgressIndicator':
          return LinearProgressIndicator(
            value: props['value']?.toDouble(),
            color: Utils.parseColor(props['color']),
            backgroundColor: Utils.parseColor(props['bg_color']),
          );

        // Default: Error Box
        default:
          return Container(
            padding: const EdgeInsets.all(10),
            color: Colors.red.withOpacity(0.2),
            child: Text("Unknown Widget: $type",
                style: const TextStyle(color: Colors.red)),
          );
      }
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(border: Border.all(color: Colors.red)),
        child: Text("Error: $e",
            style: const TextStyle(fontSize: 10, color: Colors.red)),
      );
    }
  }
}

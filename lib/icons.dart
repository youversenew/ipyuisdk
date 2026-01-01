import 'package:flutter/material.dart';

class IconMap {
  /// String nomidan IconData qaytaradi.
  /// Topilmasa [Icons.help_outline] qaytadi.
  static IconData fromName(String? name) {
    if (name == null) return Icons.help_outline;
    return _icons[name] ?? Icons.help_outline;
  }

  static final Map<String, IconData> _icons = {
    // 🧭 NAVIGATION / UI
    'home': Icons.home,
    'menu': Icons.menu,
    'arrow_back': Icons.arrow_back,
    'arrow_forward': Icons.arrow_forward,
    'close': Icons.close,
    'more_vert': Icons.more_vert,
    'more_horiz': Icons.more_horiz,
    'search': Icons.search,
    'settings': Icons.settings,
    'apps': Icons.apps,
    'dashboard': Icons.dashboard,
    'refresh': Icons.refresh,
    'fullscreen': Icons.fullscreen,
    'logout': Icons.logout,
    'login': Icons.login,

    // 👤 USER / PROFILE
    'person': Icons.person,
    'person_outline': Icons.person_outline,
    'account_circle': Icons.account_circle,
    'group': Icons.group,
    'edit': Icons.edit,
    'delete': Icons.delete,
    'verified': Icons.verified,
    'admin_panel_settings': Icons.admin_panel_settings,
    'badge': Icons.badge,
    'security': Icons.security,

    // 💬 CHAT / SOCIAL
    'chat': Icons.chat,
    'message': Icons.message,
    'send': Icons.send,
    'reply': Icons.reply,
    'share': Icons.share,
    'thumb_up': Icons.thumb_up,
    'thumb_down': Icons.thumb_down,
    'favorite': Icons.favorite,
    'favorite_border': Icons.favorite_border,
    'notifications': Icons.notifications,

    // 📁 FILE / DATA
    'folder': Icons.folder,
    'folder_open': Icons.folder_open,
    'file_copy': Icons.file_copy,
    'cloud': Icons.cloud,
    'cloud_upload': Icons.cloud_upload,
    'cloud_download': Icons.cloud_download,
    'download': Icons.download,
    'upload': Icons.upload,
    'save': Icons.save,
    'storage': Icons.storage,
    'database':
        Icons.storage, // Materialda 'database' 'storage' bilan bir xil ma'noda
    'backup': Icons.backup,
    'archive': Icons.archive,
    'attach_file': Icons.attach_file,
    'link': Icons.link,

    // 🛒 E-COMMERCE / MONEY
    'shopping_cart': Icons.shopping_cart,
    'shopping_bag': Icons.shopping_bag,
    'payment': Icons.payment,
    'credit_card': Icons.credit_card,
    'wallet': Icons.wallet,
    'qr_code': Icons.qr_code,
    'receipt': Icons.receipt,
    'price_check': Icons.price_check,
    'sell': Icons.sell,
    'local_offer': Icons.local_offer,

    // 📍 LOCATION / MAP
    'location_on': Icons.location_on,
    'location_off': Icons.location_off,
    'map': Icons.map,
    'navigation': Icons.navigation,
    'near_me': Icons.near_me,
    'pin_drop': Icons.pin_drop,
    'place': Icons.place,
    'my_location': Icons.my_location,

    // 🎵 MEDIA / CONTENT
    'play_arrow': Icons.play_arrow,
    'pause': Icons.pause,
    'stop': Icons.stop,
    'volume_up': Icons.volume_up,
    'volume_off': Icons.volume_off,
    'music_note': Icons.music_note,
    'videocam': Icons.videocam,
    'camera_alt': Icons.camera_alt,
    'photo': Icons.photo,
    'image': Icons.image,

    // ⚙️ SYSTEM / STATUS
    'info': Icons.info,
    'help': Icons.help,
    'warning': Icons.warning,
    'error': Icons.error,
    'check': Icons.check,
    'check_circle': Icons.check_circle,
    'cancel': Icons.cancel,
    'visibility': Icons.visibility,
    'visibility_off': Icons.visibility_off,
    'lock': Icons.lock,
    'lock_open': Icons.lock_open,
    'sync': Icons.sync,

    // 📊 EXTRA (REAL DEV ICONS)
    'analytics': Icons.analytics,
    'bar_chart': Icons.bar_chart,
    'pie_chart': Icons.pie_chart,
    'timeline': Icons.timeline,
    'code': Icons.code,
    'terminal': Icons.terminal,
    'bug_report': Icons.bug_report,
    'build': Icons.build,
    'extension': Icons.extension,
    'api': Icons.api,
  };
}

// =============================================================================
// FILE: lib/performance.dart
// MODULE: PERFORMANCE ENGINE & DIFFING ALGORITHM
// DESC: Handles Virtual DOM-like indexing, Patching, and Lazy Loading logic
// =============================================================================

import 'dart:async';
import 'package:flutter/widgets.dart';

class PerformanceManager {
  // Singleton
  static final PerformanceManager instance = PerformanceManager._internal();
  PerformanceManager._internal();

  // 1. NODE INDEX (Tezkor qidiruv tizimi)
  // ID -> Node (Map) ga havola. Bu bizga daraxtni qayta kavlamasdan,
  // to'g'ridan-to'g'ri elementni topishga yordam beradi.
  final Map<String, Map<String, dynamic>> _nodeIndex = {};

  /// Butun daraxtni indekslaydi (Dastlabki yuklashda ishlatiladi)
  void indexTree(Map<String, dynamic> root) {
    _nodeIndex.clear();
    _traverseAndIndex(root);
    print(
        "⚡ Performance: Indexed ${_nodeIndex.length} nodes for rapid access.");
  }

  void _traverseAndIndex(Map<String, dynamic> node) {
    // Agar ID bo'lsa, uni xotiraga olamiz
    if (node.containsKey('id') && node['id'] != null) {
      _nodeIndex[node['id']] = node;
    }
    // Bolalarini ham aylanamiz
    if (node.containsKey('children') && node['children'] is List) {
      for (var child in node['children']) {
        if (child is Map<String, dynamic>) {
          _traverseAndIndex(child);
        }
      }
    }
  }

  // 2. DIFFING & PATCHING (Jarrohlik amaliyoti)
  /// Butun UI ni o'zgartirmasdan, faqat bitta elementni yangilaydi
  bool applyPatch(String id, Map<String, dynamic> updates) {
    if (!_nodeIndex.containsKey(id)) {
      print("⚠️ Patch Failed: Node ID '$id' not found in index.");
      return false;
    }

    final node = _nodeIndex[id]!;

    // Props (Xususiyatlar) ni yangilash
    if (updates.containsKey('props')) {
      final newProps = updates['props'] as Map<String, dynamic>;
      // Mavjud props bilan birlashtiramiz (Merge)
      node['props'] = {...?node['props'], ...newProps};
    }

    // Children (Bolalar) ni yangilash (Agar kerak bo'lsa)
    if (updates.containsKey('children')) {
      node['children'] = updates['children'];
      // Yangi bolalarni ham indekslash kerak
      for (var child in node['children']) {
        _traverseAndIndex(child);
      }
    }

    return true; // Muvaffaqiyatli
  }

  // 3. LAZY LOADING LOGIC (Scroll Controller)
  // Scroll oxiriga yetganda signal berish uchun
  bool shouldLoadMore(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      if (notification.metrics.extentAfter < 200) {
        // Oxiriga 200px qolganda
        return true;
      }
    }
    return false;
  }
}

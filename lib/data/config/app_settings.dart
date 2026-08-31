import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/network_config.dart';
import 'app_theme.dart';

/// Lightweight persisted application settings (theme, backend toggle, saved
/// network config, auto-connect, ...).
///
/// Uses `shared_preferences` so the app remembers the user's choices across
/// launches. Values are kept in memory and flushed on change.
class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const String _kThemeMode = 'themeMode';
  static const String _kSeedColor = 'seedColor';
  static const String _kDeveloperMockBackend = 'developerMockBackend';
  static const String _kAutoStart = 'autoStart';
  static const String _kSavedConfig = 'savedConfig';
  static const String _kEnableMagicDns = 'enableMagicDns';

  SharedPreferences? _prefs;

  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = AppTheme.defaultSeed;
  bool _devMockBackend = false;
  bool _autoStart = false;
  bool _enableMagicDns = false;
  NetworkConfig? _savedConfig;

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  bool get darkMode => _themeMode == ThemeMode.dark;
  bool get developerMockBackend => _devMockBackend;
  bool get autoStart => _autoStart;
  bool get enableMagicDns => _enableMagicDns;
  NetworkConfig? get savedConfig => _savedConfig;

  /// Load persisted settings. Call once during app startup.
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _themeMode = _fromName(_prefs?.getString(_kThemeMode)) ?? ThemeMode.system;
    _seedColor = _decodeColor(_prefs?.getString(_kSeedColor)) ??
        AppTheme.defaultSeed;
    _devMockBackend = _prefs?.getBool(_kDeveloperMockBackend) ?? false;
    _autoStart = _prefs?.getBool(_kAutoStart) ?? false;
    _enableMagicDns = _prefs?.getBool(_kEnableMagicDns) ?? false;

    final saved = _prefs?.getString(_kSavedConfig);
    if (saved != null) {
      try {
        _savedConfig =
            NetworkConfig.fromJson(jsonDecode(saved) as Map<String, dynamic>);
      } catch (_) {
        _savedConfig = null;
      }
    }
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs?.setString(_kThemeMode, mode.name);
  }

  void setSeedColor(Color color) {
    _seedColor = color;
    _prefs?.setString(_kSeedColor, _encodeColor(color));
  }

  void setDeveloperMockBackend(bool value) {
    _devMockBackend = value;
    _prefs?.setBool(_kDeveloperMockBackend, value);
  }

  void setAutoStart(bool value) {
    _autoStart = value;
    _prefs?.setBool(_kAutoStart, value);
  }

  void setEnableMagicDns(bool value) {
    _enableMagicDns = value;
    _prefs?.setBool(_kEnableMagicDns, value);
  }

  void setSavedConfig(NetworkConfig config) {
    _savedConfig = config;
    _prefs?.setString(_kSavedConfig, jsonEncode(config.toJson()));
  }

  /// The config to prefill the forms / auto-connect with.
  NetworkConfig get effectiveConfig {
    final saved = _savedConfig;
    if (saved != null) {
      if (_enableMagicDns && !saved.extraFlags.containsKey('accept_dns')) {
        return saved.copyWith(extraFlags: {
          ...saved.extraFlags,
          'accept_dns': true,
        });
      }
      return saved;
    }
    return NetworkConfig.defaults();
  }

  ThemeMode? _fromName(String? name) {
    return ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  /// Encode a [Color] as a single ARGB int using the component accessors
  /// (`.a/.r/.g/.b` return 0..1 doubles).
  String _encodeColor(Color c) {
    final int a = (c.a * 255).round() & 0xFF;
    final int r = (c.r * 255).round() & 0xFF;
    final int g = (c.g * 255).round() & 0xFF;
    final int b = (c.b * 255).round() & 0xFF;
    return jsonEncode([
      (a << 24) | (r << 16) | (g << 8) | b,
    ]);
  }

  Color? _decodeColor(String? encoded) {
    if (encoded == null) return null;
    try {
      final list = (jsonDecode(encoded) as List).cast<int>();
      if (list.length == 1) return Color(list[0]);
      return Color.fromARGB(list[3], list[0], list[1], list[2]);
    } catch (_) {
      return null;
    }
  }
}

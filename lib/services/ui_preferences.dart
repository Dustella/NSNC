import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accent colour families offered in Settings.
enum NsncAccent {
  miuix('MIUIX 蓝', Color(0xFF3482FF)),
  netease('网易红', Color(0xFFD33A31)),
  ocean('海湾青', Color(0xFF00897B)),
  forest('松林绿', Color(0xFF3F8F4F)),
  violet('暮光紫', Color(0xFF7E57C2)),
  amber('琥珀橙', Color(0xFFE08A1E)),
  wallpaper('跟随壁纸', Color(0xFF6750A4));

  const NsncAccent(this.label, this.color);

  final String label;

  /// Seed colour; for [wallpaper] only a fallback until the platform answers.
  final Color color;
}

/// How collections (playlists, charts, radios) are laid out.
enum CollectionLayout { list, grid }

/// Optional modules on the Discover page, in display order.
enum HomeSection {
  quickAccess('快捷入口'),
  daily('每日推荐'),
  playlists('推荐歌单'),
  newSongs('新歌速递'),
  charts('排行榜'),
  radios('精选电台');

  const HomeSection(this.label);
  final String label;
}

enum PlayerBackground {
  blurredCover('模糊封面'),
  gradient('封面取色渐变'),
  plain('纯色');

  const PlayerBackground(this.label);
  final String label;
}

enum CoverCorner {
  small('小', 4),
  medium('中', 10),
  large('大', 18);

  const CoverCorner(this.label, this.radius);
  final String label;
  final double radius;
}

enum PaletteStyle {
  hyperos('HyperOS 中性', null),
  tonalSpot('Monet 柔和', MiuixThemePaletteStyle.tonalSpot),
  vibrant('Monet 鲜艳', MiuixThemePaletteStyle.vibrant),
  expressive('Monet 表现力', MiuixThemePaletteStyle.expressive);

  const PaletteStyle(this.label, this.miuix);
  final String label;

  /// Monet style, or null for the neutral MIUIX surfaces with accent primary.
  final MiuixThemePaletteStyle? miuix;
}

/// Layout surfaces that remember their own list/card choice.
abstract final class LayoutSurface {
  static const homePlaylists = 'home.playlists';
  static const libraryPlaylists = 'library.playlists';
  static const charts = 'charts';
  static const radios = 'radios';
  static const search = 'search.collections';
}

/// Persisted appearance choices exposed on the Settings page.
class UiPreferences extends ChangeNotifier {
  UiPreferences._(this._prefs) {
    _load();
  }

  static Future<UiPreferences> open() async =>
      UiPreferences._(await SharedPreferences.getInstance());

  /// In-memory instance for tests.
  @visibleForTesting
  factory UiPreferences.forTesting(SharedPreferences prefs) =>
      UiPreferences._(prefs);

  static const _prefix = 'ui_pref_v1.';
  static const maxRecentSearches = 12;

  final SharedPreferences _prefs;

  ThemeMode _themeMode = ThemeMode.system;
  NsncAccent _accent = NsncAccent.netease;
  PaletteStyle _palette = PaletteStyle.hyperos;
  CollectionLayout _defaultLayout = CollectionLayout.grid;
  final Map<String, CollectionLayout> _layouts = {};
  Set<HomeSection> _homeSections = HomeSection.values.toSet();
  PlayerBackground _playerBackground = PlayerBackground.blurredCover;
  CoverCorner _coverCorner = CoverCorner.medium;
  double _lyricScale = 1.0;
  bool _showTranslation = true;
  List<String> _recentSearches = const [];

  ThemeMode get themeMode => _themeMode;
  NsncAccent get accent => _accent;
  PaletteStyle get palette => _palette;
  CollectionLayout get defaultLayout => _defaultLayout;
  PlayerBackground get playerBackground => _playerBackground;
  CoverCorner get coverCorner => _coverCorner;
  double get coverRadius => _coverCorner.radius;
  double get lyricScale => _lyricScale;
  bool get showTranslation => _showTranslation;
  List<String> get recentSearches => _recentSearches;

  bool showsSection(HomeSection section) => _homeSections.contains(section);

  CollectionLayout layoutFor(String surface) =>
      _layouts[surface] ?? _defaultLayout;

  void _load() {
    T pick<T extends Enum>(List<T> values, String key, T fallback) {
      final name = _prefs.getString('$_prefix$key');
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    _themeMode = pick(ThemeMode.values, 'themeMode', _themeMode);
    _accent = pick(NsncAccent.values, 'accent', _accent);
    _palette = pick(PaletteStyle.values, 'palette', _palette);
    _defaultLayout = pick(
      CollectionLayout.values,
      'defaultLayout',
      _defaultLayout,
    );
    _playerBackground = pick(
      PlayerBackground.values,
      'playerBackground',
      _playerBackground,
    );
    _coverCorner = pick(CoverCorner.values, 'coverCorner', _coverCorner);
    _lyricScale = (_prefs.getDouble('${_prefix}lyricScale') ?? _lyricScale)
        .clamp(0.8, 1.6);
    _showTranslation =
        _prefs.getBool('${_prefix}showTranslation') ?? _showTranslation;
    final hidden = _prefs.getStringList('${_prefix}hiddenSections') ?? const [];
    _homeSections = HomeSection.values
        .where((s) => !hidden.contains(s.name))
        .toSet();
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith('${_prefix}layout.')) continue;
      final surface = key.substring('${_prefix}layout.'.length);
      final value = _prefs.getString(key);
      for (final layout in CollectionLayout.values) {
        if (layout.name == value) _layouts[surface] = layout;
      }
    }
    _recentSearches = List.unmodifiable(
      _prefs.getStringList('${_prefix}recentSearches') ?? const <String>[],
    );
  }

  Future<void> _setEnum(String key, Enum value) =>
      _prefs.setString('$_prefix$key', value.name);

  Future<void> setThemeMode(ThemeMode value) async {
    _themeMode = value;
    notifyListeners();
    await _setEnum('themeMode', value);
  }

  Future<void> setAccent(NsncAccent value) async {
    _accent = value;
    notifyListeners();
    await _setEnum('accent', value);
  }

  Future<void> setPalette(PaletteStyle value) async {
    _palette = value;
    notifyListeners();
    await _setEnum('palette', value);
  }

  Future<void> setDefaultLayout(CollectionLayout value) async {
    _defaultLayout = value;
    _layouts.clear();
    notifyListeners();
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith('${_prefix}layout.')) await _prefs.remove(key);
    }
    await _setEnum('defaultLayout', value);
  }

  Future<void> setLayout(String surface, CollectionLayout value) async {
    _layouts[surface] = value;
    notifyListeners();
    await _setEnum('layout.$surface', value);
  }

  Future<void> setSection(HomeSection section, bool visible) async {
    final next = {..._homeSections};
    visible ? next.add(section) : next.remove(section);
    _homeSections = next;
    notifyListeners();
    await _prefs.setStringList('${_prefix}hiddenSections', [
      for (final s in HomeSection.values)
        if (!next.contains(s)) s.name,
    ]);
  }

  Future<void> setPlayerBackground(PlayerBackground value) async {
    _playerBackground = value;
    notifyListeners();
    await _setEnum('playerBackground', value);
  }

  Future<void> setCoverCorner(CoverCorner value) async {
    _coverCorner = value;
    notifyListeners();
    await _setEnum('coverCorner', value);
  }

  Future<void> setLyricScale(double value) async {
    _lyricScale = value.clamp(0.8, 1.6);
    notifyListeners();
    await _prefs.setDouble('${_prefix}lyricScale', _lyricScale);
  }

  Future<void> setShowTranslation(bool value) async {
    _showTranslation = value;
    notifyListeners();
    await _prefs.setBool('${_prefix}showTranslation', value);
  }

  Future<void> addRecentSearch(String keywords) async {
    final value = keywords.trim();
    if (value.isEmpty) return;
    _recentSearches = List.unmodifiable(
      [
        value,
        ..._recentSearches.where((s) => s != value),
      ].take(maxRecentSearches),
    );
    notifyListeners();
    await _prefs.setStringList(
      '${_prefix}recentSearches',
      _recentSearches.toList(),
    );
  }

  Future<void> clearRecentSearches() async {
    _recentSearches = const [];
    notifyListeners();
    await _prefs.remove('${_prefix}recentSearches');
  }
}

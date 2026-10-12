/// A date as written in a Loom file: ISO when exact (`1950-05-17`, `1987-11`,
/// `1972`), otherwise GEDCOM's grammar (`ABT 1961`, `BET 1880 AND 1885`).
class LoomDate {
  LoomDate(this.raw);

  final String raw;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];
  static final _iso = RegExp(r'^(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?$');
  static final _gedcomDay = RegExp(r'(?:(\d{1,2}) )?(?:([A-Z]{3}) )?(\d{4})');

  /// The first year mentioned, or null if there is none.
  int? get year {
    final m = RegExp(r'\d{4}').firstMatch(raw);
    return m == null ? null : int.parse(m[0]!);
  }

  /// A number that orders dates: yyyymmdd of the earliest point mentioned.
  /// Undated values sort last.
  int get sortKey {
    final iso = _iso.firstMatch(raw);
    if (iso != null) {
      return int.parse(iso[1]!) * 10000 +
          int.parse(iso[2] ?? '0') * 100 +
          int.parse(iso[3] ?? '0');
    }
    final g = _gedcomDay.firstMatch(raw);
    if (g == null) return 99999999;
    final month = g[2] == null ? 0 : _monthNumber(g[2]!);
    return int.parse(g[3]!) * 10000 + month * 100 + int.parse(g[1] ?? '0');
  }

  /// The date in words: `17 May 1950`, `about 1961`, `1946–1987`.
  String get display {
    final iso = _iso.firstMatch(raw);
    if (iso != null) {
      return [
        if (iso[3] != null) int.parse(iso[3]!).toString(),
        if (iso[2] != null) _months[int.parse(iso[2]!) - 1],
        iso[1]!,
      ].join(' ');
    }
    final between = RegExp(r'^BET (.+) AND (.+)$').firstMatch(raw);
    if (between != null) {
      return '${_words(between[1]!)}–${_words(between[2]!)}';
    }
    const qualifiers = {
      'ABT': 'about',
      'CAL': 'about',
      'EST': 'about',
      'BEF': 'before',
      'AFT': 'after',
      'FROM': 'from',
      'TO': 'until',
    };
    final parts = raw.split(' ');
    final q = qualifiers[parts.first];
    return q == null ? _words(raw) : '$q ${_words(parts.skip(1).join(' '))}';
  }

  static int _monthNumber(String abbreviation) =>
      _months.indexWhere((m) => m.toUpperCase() == abbreviation) + 1;

  /// `7 AUG 1941` -> `7 Aug 1941`.
  static String _words(String gedcom) => gedcom.replaceAllMapped(
      RegExp(r'[A-Z]{3}'),
      (m) => _monthNumber(m[0]!) == 0 ? m[0]! : _months[_monthNumber(m[0]!) - 1]);

  @override
  String toString() => raw;
}

/// A date as someone typed it: "14 March 1887", "about 1925", "spring 1925",
/// "the 1880s", "1946 to 1987". The text is kept exactly as typed; what it
/// means is worked out from it, for sorting and for showing how it was read.
class TreeDate {
  TreeDate._(
    this.raw, {
    this.start,
    this.end,
    this.qualifier,
    this.ambiguous = false,
  });

  /// Reads [text], which may be in any of the forms people commonly write.
  /// Text that is not a date gives a [TreeDate] that is not [understood].
  factory TreeDate.parse(String text) => _parse(text.trim());

  /// The date exactly as typed.
  final String raw;

  /// The earliest point the date refers to, when understood.
  final DayMonthYear? start;

  /// For a range or a period, its other end.
  final DayMonthYear? end;

  /// `about`, `before`, `after`, `between` (a range of uncertainty), `from`
  /// (a period), or `baptized`.
  final String? qualifier;

  /// True when the text could mean two different dates, such as 3/4/1887.
  final bool ambiguous;

  bool get understood => start != null;

  /// The first year mentioned, or null if not understood.
  int? get year => start?.year;

  /// A number that orders dates by their earliest point; dates not
  /// understood sort last.
  int get sortKey => start?.key ?? 99999999;

  /// The date as shown on a page: as typed.
  String get display => raw;

  /// How the date was read, in words: "about 1925", "between 1880 and 1889".
  String get meaning {
    if (!understood) return 'not read as a date';
    final s = start!.words;
    final range = end == null ? s : '$s and ${end!.words}';
    return switch (qualifier) {
          'about' => 'about $s',
          'before' => 'before $s',
          'after' => 'after $s',
          'between' => 'between $range',
          'from' => end == null ? 'from $s' : '$s to ${end!.words}',
          'baptized' => 'baptized $s',
          _ => s,
        } +
        (ambiguous ? ' (could also be read the other way round)' : '');
  }

  @override
  String toString() => raw;

  static const months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', //
    'August', 'September', 'October', 'November', 'December',
  ];

  static int? monthNumber(String word) {
    final w = word.toLowerCase().replaceAll('.', '');
    if (w.length < 3) return null;
    for (var i = 0; i < months.length; i++) {
      final m = months[i].toLowerCase();
      if (m.startsWith(w) && (w.length >= 3)) return i + 1;
    }
    if (w == 'sept') return 9;
    return null;
  }

  /// Whether [text] looks like an attempt at a date, read or not: a year,
  /// with nothing else but date words, numbers and punctuation. Such text is
  /// never taken for a place, as "1861 or 1862" or "c1861" might otherwise
  /// be. "1861 Main Street" is not a date.
  static bool looksLike(String text) {
    final t = text.toLowerCase();
    if (!RegExp(r'\d{3,4}').hasMatch(t)) return false;
    final words = RegExp(r'[a-z]+').allMatches(t).map((m) => m[0]!);
    return words.every(
      (w) =>
          _dateWords.contains(w) ||
          monthNumber(w) != null ||
          RegExp(r'^(st|nd|rd|th|s)$').hasMatch(w),
    );
  }

  static const _dateWords = {
    'about', 'abt', 'approx', 'approximately', 'around', 'c', 'ca', 'circa', //
    'est', 'estimated', 'cal', 'before', 'bef', 'after', 'aft', 'between',
    'bet', 'and', 'or', 'from', 'to', 'until', 'the', 'of', 'spring', 'summer',
    'autumn', 'fall', 'winter', 'early', 'late', 'mid', 'bapt', 'baptized',
    'baptised', 'chr', 'probably', 'perhaps',
  };

  static TreeDate _parse(String raw) {
    var text = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceFirst(RegExp(r'^the '), '');
    if (text.isEmpty) return TreeDate._(raw);

    // A question mark after a date, "1861?" or "1861 (?)", marks it as
    // uncertain: read as "about".
    if (text.endsWith('?') || text.endsWith('?)')) {
      final rest = text.replaceFirst(RegExp(r'\s*\(?\?\)?$'), '');
      if (rest.isEmpty) return TreeDate._(raw);
      final inner = _parse(rest);
      if (!inner.understood) return TreeDate._(raw);
      return TreeDate._(
        raw,
        start: inner.start,
        end: inner.end,
        qualifier: inner.qualifier ?? 'about',
        ambiguous: inner.ambiguous,
      );
    }

    // Qualifiers in front.
    const prefixes = {
      'about': 'about', 'abt': 'about', 'approx': 'about', //
      'approximately': 'about', 'around': 'about', 'c': 'about', 'ca': 'about',
      'circa': 'about', 'est': 'about', 'estimated': 'about', 'cal': 'about',
      'before': 'before', 'bef': 'before', 'after': 'after', 'aft': 'after',
      'bapt': 'baptized', 'baptized': 'baptized', 'baptised': 'baptized',
      'chr': 'baptized',
    };
    final first = RegExp(r'^([a-z]+)\.? (.*)$').firstMatch(text);
    if (first != null && prefixes.containsKey(first[1])) {
      final inner = _single(first[2]!);
      if (inner == null) return TreeDate._(raw);
      return TreeDate._(
        raw,
        start: inner.$1,
        qualifier: prefixes[first[1]],
        ambiguous: inner.$2,
      );
    }

    // Ranges and periods: "between A and B", "from A to B", "A to B", "A-B".
    final between = RegExp(
      r'^(?:between|bet\.?) (.+) and (.+)$',
    ).firstMatch(text);
    final from = RegExp(
      r'^(?:from )?(.+?) (?:to|until|-|–|—) (.+)$',
    ).firstMatch(text);
    final dash = RegExp(r'^(\d{4}) ?[-–—] ?(\d{4})$').firstMatch(text);
    final pair = between ?? from ?? dash;
    if (pair != null) {
      final b = _single(pair[2]!);
      var a = _single(pair[1]!);
      // "February to July 1934": the first part borrows the year.
      if (a == null && b != null) {
        final m = monthNumber(pair[1]!.trim());
        if (m != null) a = (DayMonthYear(b.$1.year, m), false);
      }
      if (a != null && b != null) {
        return TreeDate._(
          raw,
          start: a.$1,
          end: b.$1,
          qualifier: between != null ? 'between' : 'from',
          ambiguous: a.$2 || b.$2,
        );
      }
    }

    // Decades: "1880s".
    final decade = RegExp(r"^(\d{3})0'?s$").firstMatch(text);
    if (decade != null) {
      final y = int.parse(decade[1]!) * 10;
      return TreeDate._(
        raw,
        start: DayMonthYear(y),
        end: DayMonthYear(y + 9),
        qualifier: 'between',
      );
    }

    // Seasons: "spring 1925".
    const seasons = {
      'spring': 4,
      'summer': 7,
      'autumn': 10,
      'fall': 10,
      'winter': 1,
    };
    final season = RegExp(
      r'^(spring|summer|autumn|fall|winter)(?: of)? (\d{4})$',
    ).firstMatch(text);
    if (season != null) {
      return TreeDate._(
        raw,
        start: DayMonthYear(int.parse(season[2]!), seasons[season[1]]),
        qualifier: 'about',
      );
    }

    final single = _single(text);
    if (single == null) return TreeDate._(raw);
    return TreeDate._(raw, start: single.$1, ambiguous: single.$2);
  }

  /// One date without qualifiers, and whether it is ambiguous.
  static (DayMonthYear, bool)? _single(String input) {
    final t = input.trim().replaceAll(',', '').replaceAll(RegExp(r'\s+'), ' ');
    // 1887, 1887-03, 1887-03-14
    final iso = RegExp(
      r'^(\d{4})(?:-(\d{1,2}))?(?:-(\d{1,2}))?$',
    ).firstMatch(t);
    if (iso != null) {
      return _valid(
        int.parse(iso[1]!),
        iso[2] == null ? null : int.parse(iso[2]!),
        iso[3] == null ? null : int.parse(iso[3]!),
      );
    }
    // 3/14/1887, 14.3.1887, 3-14-1887
    final numeric = RegExp(
      r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$',
    ).firstMatch(t);
    if (numeric != null) {
      final a = int.parse(numeric[1]!), b = int.parse(numeric[2]!);
      final y = int.parse(numeric[3]!);
      // Read as month/day, as written in the US, unless that cannot be right.
      final asMonthDay = a <= 12 && b <= 31;
      final r = asMonthDay ? _valid(y, a, b) : _valid(y, b, a);
      if (r == null) return null;
      return (r.$1, a <= 12 && b <= 12 && a != b);
    }
    final words = t.split(' ');
    // 14 March 1887, 14 MAR 1887
    if (words.length == 3 && int.tryParse(words[0]) != null) {
      final m = monthNumber(words[1]);
      final y = int.tryParse(words[2]);
      if (m != null && y != null) return _valid(y, m, int.parse(words[0]));
    }
    // March 14 1887
    if (words.length == 3 && int.tryParse(words[1]) != null) {
      final m = monthNumber(words[0]);
      final y = int.tryParse(words[2]);
      if (m != null && y != null) return _valid(y, m, int.parse(words[1]));
    }
    // March 1887
    if (words.length == 2) {
      final m = monthNumber(words[0]);
      final y = int.tryParse(words[1]);
      if (m != null && y != null) return _valid(y, m, null);
    }
    return null;
  }

  static (DayMonthYear, bool)? _valid(int y, int? m, int? d) {
    if (y < 100 || y > 2999) return null;
    if (m != null && (m < 1 || m > 12)) return null;
    if (d != null && (d < 1 || d > 31)) return null;
    return (DayMonthYear(y, m, d), false);
  }
}

/// A calendar date that may know only its year, or its year and month.
class DayMonthYear {
  const DayMonthYear(this.year, [this.month, this.day]);

  final int year;
  final int? month;
  final int? day;

  int get key => year * 10000 + (month ?? 0) * 100 + (day ?? 0);

  /// "14 March 1887", "March 1887", "1887".
  String get words => [
    if (day != null) '$day',
    if (month != null) TreeDate.months[month! - 1],
    '$year',
  ].join(' ');
}

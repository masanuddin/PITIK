// Utilitas waktu WIB (UTC+7).
// Kontrak firmware: tanggal & jam di Firebase memakai WIB, sedangkan
// `timestamp` / `ts` / `epoch` / `last_feed_ts` adalah epoch detik UTC.
// lib/utils/wib_time.dart

abstract final class WibTime {
  static const Duration offset = Duration(hours: 7);

  /// Konversi ke "jam dinding" WIB. Hasilnya DateTime ber-flag UTC yang
  /// field year/month/day/hour/minute-nya sudah bernilai WIB — sengaja,
  /// supaya tidak terpengaruh zona waktu HP.
  static DateTime fromUtc(DateTime time) => time.toUtc().add(offset);

  /// Epoch detik UTC → jam dinding WIB.
  static DateTime fromEpoch(int epochSeconds) => fromUtc(
        DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000, isUtc: true),
      );

  /// Jam dinding WIB → epoch detik UTC.
  static int toEpoch(DateTime wib) =>
      DateTime.utc(wib.year, wib.month, wib.day, wib.hour, wib.minute,
                  wib.second)
              .subtract(offset)
              .millisecondsSinceEpoch ~/
          1000;

  /// Kunci tanggal `/history/{YYYY-MM-DD}`.
  static String dateKey(DateTime wib) =>
      '${wib.year.toString().padLeft(4, '0')}-${_two(wib.month)}-${_two(wib.day)}';

  static String hhmm(DateTime wib) => '${_two(wib.hour)}:${_two(wib.minute)}';

  static String hhmmss(DateTime wib) => '${hhmm(wib)}:${_two(wib.second)}';

  /// Jam dari field `hour` / `minute` firmware; `-1` = belum dapat NTP.
  static String clock(int hour, int minute) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return '--:--';
    return '${_two(hour)}:${_two(minute)}';
  }

  /// Epoch detik UTC → "HH:MM" WIB; `0`/negatif = belum ada waktu NTP.
  static String epochToHhmm(int? epochSeconds) {
    if (epochSeconds == null || epochSeconds <= 0) return '--:--';
    return hhmm(fromEpoch(epochSeconds));
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  /// Waktu sebuah epoch untuk teks "update terakhir":
  /// "HH:MM:SS WIB" bila hari yang sama (WIB) dengan [nowEpoch],
  /// selain itu "d Mmm HH:MM WIB".
  static String describeEpoch(int epochSeconds, int nowEpoch) {
    final t = fromEpoch(epochSeconds);
    if (dateKey(t) == dateKey(fromEpoch(nowEpoch))) return '${hhmmss(t)} WIB';
    return '${t.day} ${_months[t.month - 1]} ${hhmm(t)} WIB';
  }

  /// Tanggal singkat dari kunci "YYYY-MM-DD" (sudah WIB): "4 Okt".
  /// Kunci tidak valid → dikembalikan apa adanya.
  static String shortDate(String dateKey) {
    final d = DateTime.tryParse(dateKey);
    if (d == null) return dateKey;
    return '${d.day} ${_months[d.month - 1]}';
  }

  /// Tanggal + jam WIB tanpa detik, selalu dengan tanggal: "4 Okt 16:20 WIB".
  /// `0`/negatif/null (belum NTP) → null.
  static String? dayMonthTime(int? epochSeconds) {
    if (epochSeconds == null || epochSeconds <= 0) return null;
    final t = fromEpoch(epochSeconds);
    return '${t.day} ${_months[t.month - 1]} ${hhmm(t)} WIB';
  }

  /// Umur dalam bahasa sehari-hari: "baru saja", "12 detik lalu", "3 menit lalu",
  /// "2 jam lalu", "5 hari lalu".
  static String ago(int seconds) {
    if (seconds < 5) return 'baru saja';
    if (seconds < 60) return '$seconds detik lalu';
    if (seconds < 3600) return '${seconds ~/ 60} menit lalu';
    if (seconds < 86400) return '${seconds ~/ 3600} jam lalu';
    return '${seconds ~/ 86400} hari lalu';
  }

  /// Durasi (mis. `uptime_s`): "45 detik", "12 menit", "3 jam 5 menit",
  /// "2 hari 4 jam".
  static String durationText(int seconds) {
    if (seconds < 60) return '${seconds < 0 ? 0 : seconds} detik';
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return h > 0 ? '$d hari $h jam' : '$d hari';
    if (h > 0) return m > 0 ? '$h jam $m menit' : '$h jam';
    return '$m menit';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

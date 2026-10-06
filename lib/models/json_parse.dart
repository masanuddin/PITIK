// Helper parsing nilai mentah Firebase RTDB.
// RTDB bisa mengembalikan int untuk float bulat (72.0 → 72), jadi semua
// field dibaca secara toleran. Nilai yang tidak bisa dibaca → null.
// lib/models/json_parse.dart

double? asDouble(Object? v) {
  final d = switch (v) {
    num n => n.toDouble(),
    String s => double.tryParse(s),
    _ => null,
  };
  return (d != null && d.isFinite) ? d : null;
}

int? asInt(Object? v) => switch (v) {
      int n => n,
      num n when n.isFinite => n.toInt(),
      String s => int.tryParse(s) ?? asDouble(s)?.toInt(),
      _ => null,
    };

bool? asBool(Object? v) => switch (v) {
      bool b => b,
      num n => n != 0,
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };

String? asString(Object? v) => v?.toString();

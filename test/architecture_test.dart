// Tes arsitektur: menjaga aturan CLAUDE.md §5 dengan memeriksa kode sumber.
//   - Semua akses Firebase RTDB hanya lewat PitikRepository.
//   - App hanya menulis ke /controls (tidak ke /sensor_data, /history, /control_log).
//   - Field lama yang sudah tidak dikirim firmware tidak dibaca lagi.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _repositoryPath = 'lib/services/pitik_repository.dart';

String _norm(String path) => path.replaceAll('\\', '/');

List<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  test('hanya PitikRepository yang mengimpor firebase_database', () {
    final offenders = [
      for (final f in _libDartFiles())
        if (_norm(f.path) != _repositoryPath &&
            f.readAsStringSync().contains('package:firebase_database'))
          _norm(f.path),
    ];
    expect(offenders, isEmpty,
        reason: 'Akses RTDB harus lewat services/pitik_repository.dart');
  });

  test('PitikRepository hanya menulis ke /controls', () {
    final src = File(_repositoryPath).readAsStringSync();
    expect(src, contains("controlsPath = 'controls'"));

    final writes = RegExp(
      r'([\w.]+)\.(set|update|push|remove|setWithPriority|runTransaction)\(',
    ).allMatches(src).toList();
    expect(writes, isNotEmpty);
    for (final m in writes) {
      expect(m.group(1), '_controlsRef',
          reason: 'Penulisan di luar /controls: ${m.group(0)}');
    }
  });

  test('field lama (online / ammonia / amonia / a) tidak dibaca', () {
    final legacyKey = RegExp(r"""\[\s*['"](online|ammonia|amonia|a)['"]\s*\]""");
    final offenders = [
      for (final f in _libDartFiles())
        for (final m in legacyKey.allMatches(f.readAsStringSync()))
          '${_norm(f.path)}: ${m.group(0)}',
    ];
    expect(offenders, isEmpty);
  });
}

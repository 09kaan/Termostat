/// A conditional plan from one genuine controller report, not proof of a reset.
class ConnectivityRecovery {
  const ConnectivityRecovery._(this.phase, this.fastUsed, this.slowUsed,
      this.remainingMs, this.reportedAt);
  final String phase;
  final int fastUsed, slowUsed, remainingMs, reportedAt;

  static ConnectivityRecovery? parse(dynamic raw, int? reportedAt) {
    if (raw is! Map ||
        reportedAt == null ||
        raw['protocol'] != 1 ||
        raw['fastLimit'] != 3 ||
        raw['slowLimit'] != 5) {
      return null;
    }
    int? integer(dynamic v) =>
        v is num && v.isFinite && v == v.roundToDouble() ? v.toInt() : null;
    final fast = integer(raw['fastUsed']), slow = integer(raw['slowUsed']);
    final wait = integer(raw['waitMs']),
        remaining = integer(raw['remainingMs']);
    if (fast == null ||
        slow == null ||
        remaining == null ||
        wait == null ||
        fast < 0 ||
        fast > 3 ||
        slow < 0 ||
        slow > 5 ||
        remaining < 0 ||
        remaining > wait) {
      return null;
    }
    final phase = raw['phase'];
    final valid = phase == 'fast' && fast < 3 && slow == 0 && wait == 300000 ||
        phase == 'slow' && fast == 3 && slow < 5 && wait == 1800000 ||
        phase == 'stopped' && fast == 3 && slow == 5 && wait == 0;
    if (!valid) {
      return null;
    }
    return ConnectivityRecovery._(
        phase as String, fast, slow, remaining, reportedAt);
  }

  String describe({required bool phoneConnected, required int? now}) {
    if (!phoneConnected) {
      return 'Uygulama bağlantısı yok; ESP32 reset zamanı doğrulanamıyor.';
    }
    if (now == null || now < reportedAt - 5000) {
      return 'Sunucu saati doğrulanamadı; reset geri sayımı gösterilemiyor.';
    }
    if (phase == 'stopped') {
      return 'Son cihaz raporuna göre bağlantı resetleri durduruldu: '
          '3 hızlı + 5 yavaş deneme kullanıldı. Bağlantı denemeleri sürer; watchdog ayrıdır.';
    }
    final left = remainingMs - (now - reportedAt).clamp(0, 0x7fffffffffffffff);
    final attempt = phase == 'fast'
        ? 'Hızlı deneme ${fastUsed + 1}/3'
        : '30 dk aralıklı deneme ${slowUsed + 1}/5';
    if (left <= 0) {
      return 'Son cihaz raporuna göre tahmini süre doldu. '
          'Resetin gerçekleştiği doğrulanamadı; yeni rapor bekleniyor. $attempt.';
    }
    final seconds = (left / 1000).ceil();
    return 'İletişim geri gelmezse yaklaşık ${seconds ~/ 60} dk ${seconds % 60} sn '
        'sonra reset planlanıyor. $attempt. Son cihaz raporuna göre tahminidir; '
        'resetin gerçekleştiği doğrulanamaz.';
  }
}

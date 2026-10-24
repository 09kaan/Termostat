/// Presentation of an absolute WiZ request, never an optimistic bulb state.
/// The bridge TTL/protocol is unchanged. Fresh matching device state can settle
/// a lost command response; rejection and expiry remain explicit failures.
class WizCommandFeedback {
  const WizCommandFeedback({
    this.pending = false,
    this.retryable = false,
    this.message,
    this.params = const {},
  });
  final bool pending, retryable;
  final String? message;
  final Map<String, dynamic> params;
  static const responseWindowMs = 12000;
  static const keys = {'state', 'dimming', 'temp', 'r', 'g', 'b'};

  static Map<String, dynamic> safeParams(dynamic raw) {
    if (raw is! Map || raw.isEmpty || raw.keys.any((k) => !keys.contains(k)))
      return {};
    final p = Map<String, dynamic>.from(raw);
    if (p.containsKey('state') && p['state'] is! bool) return {};
    for (final k in p.keys.where((k) => k != 'state')) {
      final v = p[k];
      if (v is! num || !v.isFinite || v != v.roundToDouble()) return {};
      if (k == 'dimming' && (v < 10 || v > 100)) return {};
      if (k == 'temp' && (v < 2200 || v > 6500)) return {};
      if ({'r', 'g', 'b'}.contains(k) && (v < 0 || v > 255)) return {};
    }
    if (p.keys.any({'r', 'g', 'b'}.contains) &&
        !{'r', 'g', 'b'}.every(p.containsKey)) return {};
    return p;
  }

  static WizCommandFeedback evaluate({
    required Map<String, dynamic> command,
    required Map<String, dynamic> report,
    required int now,
    required bool reportIsCurrent,
    bool writing = false,
    int? writeStartedAt,
    int? responseStartedAt,
  }) {
    final params = safeParams(command['params']);
    final hasCommand =
        command['id'] is String && (command['id'] as String).isNotEmpty;
    final ack = hasCommand && report['lastCommandId'] == command['id'];
    final status = report['commandStatus'];
    // An SDK write can remain queued offline. Never issue another while that
    // uncancellable write is outstanding, even after the response UI deadline.
    if (writing) {
      final slow = writeStartedAt != null && now - writeStartedAt >= 8000;
      return WizCommandFeedback(
        pending: true,
        message: slow
            ? 'Firebase onayı gecikti · bağlantıyı kontrol et'
            : 'Firebase gönderimi onaylanıyor…',
      );
    }
    if (!hasCommand) return const WizCommandFeedback();
    if (ack && status == 'applied') return const WizCommandFeedback();
    if (ack && const {'rejected', 'expired'}.contains(status)) {
      return WizCommandFeedback(
        retryable: params.isNotEmpty,
        params: params,
        message: status == 'rejected'
            ? 'ESP komutu reddetti'
            : 'Komutun süresi doldu',
      );
    }
    final stamp = command['issuedAt'] is num
        ? command['issuedAt']
        : command['requestedAt'];
    final reportedAt = report['reportedAt'];
    // A complete, fresh post-command report can confirm the requested values
    // even when older bridge software omits lastCommandId. Missing fields and
    // pre-command reports are NEVER confirmation.
    if (reportIsCurrent &&
        stamp is num &&
        reportedAt is num &&
        reportedAt >= stamp &&
        params.isNotEmpty &&
        params.entries.every(
          (e) => report.containsKey(e.key) && report[e.key] == e.value,
        )) {
      return const WizCommandFeedback();
    }
    final responseStamp = responseStartedAt ?? stamp;
    final age =
        responseStamp is num ? now - responseStamp.toInt() : responseWindowMs;
    if (age >= -5000 && age < responseWindowMs) {
      return WizCommandFeedback(
        pending: true,
        message:
            'Ampul yanıtı bekleniyor · ${(age.clamp(0, responseWindowMs) / 1000).floor()} sn',
      );
    }
    return WizCommandFeedback(
      retryable: params.isNotEmpty,
      params: params,
      message: ack && status == 'no_response'
          ? 'Ampul komuta yanıt vermedi'
          : 'Yanıt doğrulanamadı',
    );
  }
}

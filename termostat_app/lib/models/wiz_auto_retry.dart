import 'wiz_command_feedback.dart';

/// One foreground retry of a request created by this app session. Never arm
/// this from historical database snapshots or another phone's commands.
class WizAutoRetry {
  WizAutoRetry({
    required this.commandId,
    required Map<String, dynamic> params,
    required this.ip,
  }) : params = Map.unmodifiable(params);
  String commandId;
  final Map<String, dynamic> params;
  final String ip;
  bool consumed = false;
  int? responseStartedAt;
  static const latestRetryAgeMs = 30000;

  bool _sameParams(dynamic raw) {
    final values = WizCommandFeedback.safeParams(raw);
    return values.isNotEmpty &&
        values.length == params.length &&
        params.entries.every((e) => values[e.key] == e.value);
  }

  bool _currentAndUnexpired(Map<String, dynamic> command, int now) {
    final stamp = command['issuedAt'];
    final ttl = command['ttlMs'];
    if (command['id'] != commandId ||
        !_sameParams(command['params']) ||
        stamp is! num ||
        !stamp.isFinite ||
        ttl is! num ||
        !ttl.isFinite) return false;
    final age = now - stamp;
    return age >= WizCommandFeedback.responseWindowMs &&
        age <= latestRetryAgeMs &&
        age < ttl;
  }

  bool eligible({
    required Map<String, dynamic> command,
    required Map<String, dynamic> report,
    required int now,
    required bool reportIsCurrent,
  }) =>
      !consumed &&
      stillNeedsRetry(
          command: command,
          report: report,
          now: now,
          reportIsCurrent: reportIsCurrent);

  // Recheck inside the transaction: a rejection or valid report may arrive
  // after eligibility was checked but before the conditional write executes.
  bool stillNeedsRetry(
      {required Map<String, dynamic> command,
      required Map<String, dynamic> report,
      required int now,
      required bool reportIsCurrent}) {
    if (!_currentAndUnexpired(command, now)) return false;
    if (report['lastCommandId'] == commandId &&
        const {
          'rejected',
          'expired',
          'applied',
        }.contains(report['commandStatus'])) return false;
    return WizCommandFeedback.evaluate(
      command: command,
      report: report,
      now: now,
      reportIsCurrent: reportIsCurrent,
    ).retryable;
  }

  /// Used INSIDE a Firebase transaction. A concurrent/newer command wins.
  /// Keep the ORIGINAL timestamp and TTL: an offline transaction must not
  /// turn an old intent into a fresh command when connectivity returns.
  Map<String, dynamic>? replacement(
    Map<String, dynamic> current, {
    required String newId,
    required int now,
  }) {
    if (!_currentAndUnexpired(current, now) ||
        newId == commandId ||
        newId.isEmpty) return null;
    return {...current, 'id': newId};
  }
}

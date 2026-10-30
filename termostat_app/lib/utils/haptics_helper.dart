import 'package:flutter/services.dart';

class HapticsHelper {
  /// Sıcaklık artırıp azaltırken (0.5 derece adımlarda) tatlı bir tık hissi verir.
  static void temperatureStep({bool enabled = true}) {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  /// Mod değiştirirken (Açık / Kapalı / Manuel) daha belirgin mekanik his verir.
  static void modeToggle({bool enabled = true}) {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// Kritik aksiyonlarda veya PC açma gibi işlemlerde.
  static void heavyAction({bool enabled = true}) {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
  }
}

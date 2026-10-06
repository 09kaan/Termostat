import WidgetKit
import SwiftUI

struct ThermostatEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let notice: String?
    static var preview: ThermostatEntry {
        ThermostatEntry(date: Date(), snapshot: WidgetSnapshot(
            temperature: 22.4, humidity: 48, targetTemperature: 23,
            mode: "on", isHeating: true,
            observedAtMilliseconds: Date().addingTimeInterval(-60).timeIntervalSince1970 * 1000
        ), notice: nil)
    }
}

struct ThermostatProvider: TimelineProvider {
    func placeholder(in context: Context) -> ThermostatEntry { .preview }
    func getSnapshot(in context: Context, completion: @escaping (ThermostatEntry) -> Void) {
        if context.isPreview { completion(.preview); return }
        completion(ThermostatEntry(date: Date(), snapshot: WidgetSnapshotStore.read(), notice: nil))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ThermostatEntry>) -> Void) {
        Task {
            let entry: ThermostatEntry
            do {
                let snapshot = try await WidgetDataLoader.refresh()
                entry = ThermostatEntry(date: Date(), snapshot: snapshot, notice: nil)
            } catch {
                let commandError = error as? ThermostatCommandError
                let notice: String
                let snapshot: WidgetSnapshot?
                if commandError == .signInRequired {
                    WidgetSnapshotStore.clear(reloadTimeline: false)
                    notice = "Uygulamada giriş yap"
                    snapshot = nil
                } else if commandError == .sharedAuthenticationUnavailable || commandError == .missingConfiguration {
                    notice = "Widget kurulumu gerekli"
                    snapshot = WidgetSnapshotStore.read()
                } else if commandError == .authorizationDenied {
                    notice = "Erişim doğrulanamadı"
                    snapshot = WidgetSnapshotStore.read()
                } else {
                    notice = "Son kayıt gösteriliyor"
                    snapshot = WidgetSnapshotStore.read()
                }
                entry = ThermostatEntry(date: Date(), snapshot: snapshot, notice: notice)
            }
            // iOS decides the actual refresh time; this is not a live sensor stream.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}

@available(iOS 17.0, *)
struct ThermostatWidgetEntryView: View {
    let entry: ThermostatEntry
    var compact: Bool = false
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var medium: Bool { family == .systemMedium }
    private var ink: Color { scheme == .dark ? Color(red: 0.96, green: 0.96, blue: 0.93) : Color(red: 0.13, green: 0.15, blue: 0.12) }
    private var muted: Color { scheme == .dark ? Color(red: 0.70, green: 0.73, blue: 0.68) : Color(red: 0.45, green: 0.48, blue: 0.43) }
    private var surface: Color { scheme == .dark ? Color(red: 0.21, green: 0.24, blue: 0.22) : .white }
    private var button: Color { scheme == .dark ? Color(red: 0.27, green: 0.31, blue: 0.27) : Color(red: 0.94, green: 0.95, blue: 0.93) }
    private var accent: Color { scheme == .dark ? Color(red: 0.95, green: 0.74, blue: 0.46) : Color(red: 0.65, green: 0.36, blue: 0.13) }
    private var warm: Color { scheme == .dark ? Color(red: 0.32, green: 0.27, blue: 0.22) : Color(red: 0.98, green: 0.94, blue: 0.89) }
    private var controlsEnabled: Bool { snapshot?.mode != nil && entry.notice == nil }
    private func number(_ value: Double?, decimals: Int = 0) -> String {
        guard let value = value, value.isFinite else { return "—" }
        return value.formatted(.number.locale(Locale(identifier: "tr_TR")).precision(.fractionLength(decimals)))
    }
    private var status: String {
        if snapshot?.hasPendingCommand == true { return "Komut gönderildi" }
        if snapshot?.isStale != false { return "Eski veri" }
        if snapshot?.mode == "off" { return "Kapalı" }
        if snapshot?.isHeating == true { return "Isıtıyor" }
        if snapshot?.mode == "on" { return "Isıtma açık" }
        return "Durum bilinmiyor"
    }
    private var statusIcon: String {
        snapshot?.isHeating == true ? "flame" : "power"
    }
    var body: some View {
        Group {
            if snapshot == nil { emptyView }
            else if medium { mediumView }
            else { smallView }
        }
        .foregroundStyle(ink)
        .padding(compact ? 8 : 12)
        .containerBackground(for: .widget) { surface }
        .widgetURL(URL(string: "termostat://"))
    }
    private var brand: some View {
        HStack(spacing: 6) {
            Image(systemName: "house").foregroundStyle(accent)
            Text("Ev").fontWeight(.semibold)
        }.font(.system(size: 13))
    }
    private var temperature: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(number(snapshot?.temperature, decimals: 1))
                .font(.system(size: medium ? (compact ? 30 : 36) : (compact ? 36 : 42), weight: .medium, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
            Text("°C").font(.system(size: 16)).foregroundStyle(muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Oda sıcaklığı, \(number(snapshot?.temperature, decimals: 1)) derece")
    }
    private var metrics: some View {
        HStack(spacing: 8) {
            Label(status, systemImage: statusIcon).foregroundStyle(accent)
            Spacer(minLength: 2)
            Label("%\(number(snapshot?.humidity))", systemImage: "drop").foregroundStyle(muted)
        }.font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.75)
    }
    @ViewBuilder private var freshness: some View {
        if let notice = entry.notice {
            Text(notice).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7)
        } else if let date = snapshot?.observedDate {
            HStack(spacing: 3) {
                Text("Kontrol:")
                Text(date, style: .relative)
            }.foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
        } else {
            Text("Henüz veri yok").foregroundStyle(muted)
        }
    }
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 3) {
            brand
            Spacer(minLength: 1)
            temperature
            HStack(spacing: 4) {
                Text("Hedef").foregroundStyle(muted)
                Text("\(number(snapshot?.targetTemperature, decimals: snapshot?.targetTemperature?.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1))°C").fontWeight(.semibold)
            }.font(.system(size: 12))
            Spacer(minLength: 2)
            Divider().overlay(muted.opacity(0.15))
            metrics
            freshness.font(.system(size: 10))
        }
    }
    private var mediumView: some View {
        VStack(spacing: 6) {
            HStack {
                brand
                Spacer()
                freshness.font(.system(size: 10))
            }
            HStack(spacing: 13) {
                VStack(alignment: .leading, spacing: 3) {
                    temperature
                    metrics
                }.frame(maxWidth: .infinity)
                Rectangle().fill(muted.opacity(0.2)).frame(width: 1, height: 44)
                VStack(spacing: 4) {
                    Text("Hedef sıcaklık").font(.system(size: 10)).foregroundStyle(muted)
                    HStack(spacing: 6) {
                        stepper(-0.5)
                        Text("\(number(snapshot?.targetTemperature, decimals: snapshot?.targetTemperature?.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1))°")
                            .font(.system(size: 25, weight: .medium, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                        stepper(0.5)
                    }
                }.frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                Button(intent: HeatingOnIntent()) {
                    Label(snapshot?.mode == "on" ? "Açık" : "Aç", systemImage: "power")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(accent)
                .background(warm, in: RoundedRectangle(cornerRadius: 10))
                .disabled(!controlsEnabled)
                Button(intent: HeatingOffIntent()) {
                    Label("Kapat", systemImage: "power")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(button, in: RoundedRectangle(cornerRadius: 10))
                .disabled(!controlsEnabled)
            }.font(.system(size: 12, weight: .semibold))
        }
    }
    private func stepper(_ delta: Double) -> some View {
        let target = snapshot?.targetTemperature
        let bounded = target.map { delta > 0 ? $0 < 30 : $0 > 10 } ?? false
        return Button(intent: AdjustWidgetTemperatureIntent(delta: delta)) {
            Image(systemName: delta > 0 ? "plus" : "minus")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .background(button, in: Circle())
        .disabled(!controlsEnabled || !bounded)
        .opacity(controlsEnabled && bounded ? 1 : 0.4)
        .accessibilityLabel(delta > 0 ? "Sıcaklığı yarım derece artır" : "Sıcaklığı yarım derece azalt")
    }
    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            brand
            Spacer(minLength: 0)
            Text("Veri yok").font(.system(size: 24, weight: .medium))
            Text(entry.notice ?? "Uygulamayı açıp giriş yap.")
                .font(.system(size: 12)).foregroundStyle(muted)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

@main
struct ThermostatWidget: Widget {
    let kind = WidgetSnapshotStore.widgetKind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ThermostatProvider()) { entry in
            GeometryReader { geometry in
                ThermostatWidgetEntryView(entry: entry, compact: geometry.size.height < 160)
            }
        }
        .configurationDisplayName("Termostat")
        .description("Sıcaklığı gör, ısıtmayı aç/kapat ve hedefi değiştir.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct ThermostatWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ThermostatWidgetEntryView(entry: .preview)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            ThermostatWidgetEntryView(entry: .preview)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .preferredColorScheme(.dark)
        }
    }
}

import WidgetKit
import SwiftUI

struct ThermostatEntry: TimelineEntry {
    let date: Date
    let temperature: Double
    let humidity: Int
    let isHeating: Bool
    let mode: String
    let targetTemp: Double
}

struct ThermostatProvider: TimelineProvider {
    let appGroupId = "group.com.example.termostatApp"
    
    func placeholder(in context: Context) -> ThermostatEntry {
        ThermostatEntry(date: Date(), temperature: 22.5, humidity: 55, isHeating: true, mode: "on", targetTemp: 24.0)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (ThermostatEntry) -> Void) {
        let entry = readData()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<ThermostatEntry>) -> Void) {
        let entry = readData()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func readData() -> ThermostatEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let temp = defaults?.double(forKey: "temperature") ?? 0.0
        let hum = defaults?.integer(forKey: "humidity") ?? 0
        let heating = defaults?.bool(forKey: "isHeating") ?? false
        let mode = defaults?.string(forKey: "mode") ?? "off"
        let target = defaults?.double(forKey: "targetTemp") ?? 20.0
        
        return ThermostatEntry(
            date: Date(),
            temperature: temp == 0.0 ? 22.0 : temp,
            humidity: hum == 0 ? 50 : hum,
            isHeating: heating,
            mode: mode,
            targetTemp: target == 0.0 ? 20.0 : target
        )
    }
}

struct ThermostatWidgetEntryView: View {
    var entry: ThermostatProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.15, green: 0.1, blue: 0.25)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 8) {
                // Header
                HStack {
                    Text("🌡️ Termostat")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    // Heating status
                    HStack(spacing: 3) {
                        Circle()
                            .fill(entry.isHeating ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(entry.isHeating ? "Açık" : "Kapalı")
                            .font(.caption2)
                            .foregroundColor(entry.isHeating ? .green : .red)
                    }
                }
                
                // Temperature & Humidity
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.1f", entry.temperature))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("°C")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 2) {
                            Text("💧")
                                .font(.caption2)
                            Text("\(entry.humidity)%")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.cyan)
                        }
                        Text("Hedef: \(Int(entry.targetTemp))°")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                
                // Control buttons
                HStack(spacing: 8) {
                    Link(destination: URL(string: "termostat://heating-on")!) {
                        HStack {
                            Text("🔥")
                                .font(.caption2)
                            Text("Aç")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.3))
                        .cornerRadius(8)
                        .foregroundColor(.green)
                    }
                    
                    Link(destination: URL(string: "termostat://heating-off")!) {
                        HStack {
                            Text("⏸")
                                .font(.caption2)
                            Text("Kapat")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.3))
                        .cornerRadius(8)
                        .foregroundColor(.red)
                    }
                }
            }
            .padding(12)
        }
    }
}

@main
struct ThermostatWidget: Widget {
    let kind: String = "ThermostatWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ThermostatProvider()) { entry in
            ThermostatWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Termostat")
        .description("Sıcaklık, nem ve ısıtma durumunu görüntüle")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ThermostatWidget_Previews: PreviewProvider {
    static var previews: some View {
        ThermostatWidgetEntryView(
            entry: ThermostatEntry(
                date: Date(),
                temperature: 23.5,
                humidity: 58,
                isHeating: true,
                mode: "on",
                targetTemp: 25.0
            )
        )
        .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}

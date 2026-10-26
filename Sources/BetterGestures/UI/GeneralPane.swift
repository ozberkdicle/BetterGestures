import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section("Durum") {
                Toggle("Jestler etkin", isOn: $state.isEnabled)
                    .toggleStyle(.switch)
                LabeledContent("Erişilebilirlik izni") {
                    if state.isAccessibilityTrusted {
                        Label("Verildi", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack {
                            Button("İzin iste") { state.requestAccessibility() }
                            Button("Ayarları aç") { state.openAccessibilitySettings() }
                        }
                    }
                }
                LabeledContent("Cihazlar") {
                    VStack(alignment: .trailing, spacing: 2) {
                        if state.devices.isEmpty { Text(verbatim: "—") }
                        ForEach(state.devices) { device in
                            Text(verbatim: "\(device.name) · \(Int(device.width))×\(Int(device.height)) mm")
                        }
                    }
                }
            }

            Section {
                Toggle(isOn: $state.blocksMultiFingerScroll) {
                    Text("3 ve daha fazla parmakla kaydırmayı engelle")
                    Text("Sistem 3 parmak jestleri kapalıyken üç parmağı kaydırmaya çevirir. Bu açıkken üç ve daha fazla parmakla yapılan hareket sayfayı kaydırmaz, yalnızca jest olarak algılanır. İki parmakla kaydırma ve fare tekerleği etkilenmez.")
                }
                .toggleStyle(.switch)
                if let error = state.inputFilterError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            } header: {
                Text("Kaydırma")
            }

            Section("Başlangıç") {
                Toggle("Girişte başlat", isOn: $state.launchAtLogin)
                    .toggleStyle(.switch)
                if state.loginItemStatus == .requiresApproval {
                    HStack {
                        Text("Sistem Ayarları'nda onay bekliyor").foregroundStyle(.secondary)
                        Spacer()
                        Button("Giriş öğelerini aç") { state.openLoginItemsSettings() }
                    }
                }
                if let error = state.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }

            Section {
                LabeledContent("Dosya") {
                    Text(ConfigStore.fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Yeniden yükle") { state.reloadConfig() }
                    Button("Finder'da göster") { state.revealConfig() }
                    Button("Düzenleyicide aç") { state.openConfig() }
                }
                if let error = state.configError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                ForEach(state.configWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            } header: {
                Text("Config")
            } footer: {
                Text("Arayüzdeki değişiklikler bu dosyaya yazılır. Dosyayı elle düzenlerseniz \"Yeniden yükle\"ye basın.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $state.isDebug) {
                    Text("Ham dokunmaları logla")
                    Text("Her kare konsola ve unified log'a yazılır. Terminalde make logs ile izleyin.")
                }
                .toggleStyle(.switch)
            } header: {
                Text("Geliştirici")
            }
        }
        .formStyle(.grouped)
    }
}

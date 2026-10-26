import GestureCore
import SwiftUI

/// recognition thresholds. applied live while dragging, written to the config on release.
struct TuningPane: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section {
                slider("Azami süre", \.tapMaxDuration, 0.1...1.0, .duration,
                       "İlk parmağın inişinden son parmağın kalkışına kadar.")
                slider("Azami kayma", \.tapMaxMovement, 0.005...0.1, .distance,
                       "Herhangi bir parmak bundan fazla kayarsa dokunma sayılmaz.")
                slider("Çift dokunma aralığı", \.doubleTapWindow, 0.1...0.6, .duration,
                       "İki dokunuş arasındaki azami boşluk. Çift dokunma eşlenmişse tek dokunma bu kadar gecikir.")
            } header: {
                Text("3 / 4 / 5 parmak dokunma")
            }

            Section {
                slider("Bekleme süresi", \.holdDuration, 0.2...1.5, .duration,
                       "Üç parmak bu kadar hareketsiz kalınca tetiklenir.")
                slider("Azami kayma", \.holdMaxMovement, 0.005...0.1, .distance, nil)
            } header: {
                Text("3 parmak basılı tutma")
            }

            Section {
                slider("Sabit parmağın bekleme süresi", \.tipTapAnchorMinHold, 0...0.5, .duration,
                       "İkinci parmak inmeden önce ilki en az bu kadar basılı olmalı. İki parmakla birlikte dokunmayı (sağ tık) ayırt eder.")
                slider("Sabit parmağın azami kayması", \.tipTapAnchorMaxMovement, 0.005...0.1, .distance,
                       "Dokunma sırasında. Fazlası iki parmak kaydırma sayılır.")
                slider("Dokunuşun azami süresi", \.tipTapMaxDuration, 0.1...0.8, .duration,
                       "Dokunan parmak bundan uzun basılı kalırsa tetiklenmez.")
                slider("Dokunuşun azami kayması", \.tipTapMaxMovement, 0.005...0.1, .distance, nil)
                slider("İki parmakla dokunma aralığı", \.tipTapPairWindow, 0.02...0.2, .duration,
                       "İki parmakla TipTap'te ikinci parmak ilkinden en geç bu kadar sonra inmeli.")
            } header: {
                Text("TipTap")
            }

            Section {
                slider("Tetikleme mesafesi", \.swipeMinDistance, 0.03...0.4, .distance,
                       "Parmakların ortalama yol alması bunu geçince jest tetiklenir.")
                slider("Çapraz tolerans", \.swipeMaxOffAxisRatio, 0.1...1.0, .ratio,
                       "Yan eksendeki hareketin ana eksene oranı. Düşükse yalnızca düz kaydırmalar geçer.")
                slider("Parmak uyumu", \.swipeMinFingerAgreement, 0...1, .ratio,
                       "Her parmak ortalamanın en az bu oranı kadar aynı yöne gitmeli. Sıkıştırma ve döndürmeyi eler.")
            } header: {
                Text("3 parmak kaydırma")
            }

            Section {
                HStack {
                    Text(distanceNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Varsayılanlara dön") {
                        state.tuning = RecognizerTuning()
                        state.saveConfig()
                    }
                    .disabled(state.tuning == RecognizerTuning())
                }
            }
        }
        .formStyle(.grouped)
    }

    private enum Kind { case duration, distance, ratio }

    /// device used to turn distances into mm (the magic trackpad if there is one).
    private var referenceDevice: TouchSource.Device? {
        state.devices.first(where: { !$0.builtIn }) ?? state.devices.first
    }

    private var distanceNote: String {
        if let device = referenceDevice {
            String(localized: "Mesafeler trackpad genişliğine oranla verilir; mm değerleri \(device.name) içindir.")
        } else {
            String(localized: "Mesafeler trackpad genişliğine oranla verilir.")
        }
    }

    private func format(_ value: Double, _ kind: Kind) -> String {
        switch kind {
        case .duration:
            return "\(Int((value * 1000).rounded())) ms"
        case .distance:
            let percent = value.formatted(.percent.precision(.fractionLength(1)))
            guard let device = referenceDevice else { return percent }
            return percent + " · ≈ " + (value * device.width).formatted(.number.precision(.fractionLength(1))) + " mm"
        case .ratio:
            return value.formatted(.number.precision(.fractionLength(2)))
        }
    }

    private func slider(
        _ title: LocalizedStringKey, _ keyPath: WritableKeyPath<RecognizerTuning, Double>,
        _ range: ClosedRange<Double>, _ kind: Kind, _ help: LocalizedStringKey?
    ) -> some View {
        // with a `step` the macos slider draws lots of tick marks, so we round the value instead.
        let step = kind == .duration ? 0.01 : (kind == .distance ? 0.0025 : 0.05)
        let value = Binding(
            get: { state.tuning[keyPath: keyPath] },
            set: { state.tuning[keyPath: keyPath] = ($0 / step).rounded() * step }
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue, kind))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range) { editing in
                if !editing { state.saveConfig() }
            }
            .labelsHidden()
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

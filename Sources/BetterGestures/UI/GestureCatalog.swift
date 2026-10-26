import Foundation
import GestureCore

/// avoid the clash with swiftui's `Gesture` protocol: in this module `Gesture` is always a trackpad gesture.
typealias Gesture = GestureCore.Gesture

/// ui name, description and grouping of gestures.
extension Gesture {
    var title: String {
        switch self {
        case .threeFingerTap: String(localized: "3 parmak dokunma")
        case .fourFingerTap: String(localized: "4 parmak dokunma")
        case .fiveFingerTap: String(localized: "5 parmak dokunma")
        case .threeFingerDoubleTap: String(localized: "3 parmak çift dokunma")
        case .fourFingerDoubleTap: String(localized: "4 parmak çift dokunma")
        case .fiveFingerDoubleTap: String(localized: "5 parmak çift dokunma")
        case .threeFingerHold: String(localized: "3 parmak basılı tut")
        case .tipTapLeft: String(localized: "TipTap sol")
        case .tipTapRight: String(localized: "TipTap sağ")
        case .twoAnchorTipTapLeft: String(localized: "TipTap sol · 2 sabit")
        case .twoAnchorTipTapRight: String(localized: "TipTap sağ · 2 sabit")
        case .twoFingerTipTapLeft: String(localized: "TipTap sol · 2 parmakla")
        case .twoFingerTipTapRight: String(localized: "TipTap sağ · 2 parmakla")
        case .threeFingerSwipeLeft: String(localized: "Sola kaydır")
        case .threeFingerSwipeRight: String(localized: "Sağa kaydır")
        case .threeFingerSwipeUp: String(localized: "Yukarı kaydır")
        case .threeFingerSwipeDown: String(localized: "Aşağı kaydır")
        case .threeFingerClick: String(localized: "3 parmak tıklama")
        case .fourFingerClick: String(localized: "4 parmak tıklama")
        }
    }

    var subtitle: String {
        switch self {
        case .threeFingerTap: String(localized: "Üç parmakla kısa, sabit bir dokunuş")
        case .fourFingerTap: String(localized: "Dört parmakla kısa, sabit bir dokunuş")
        case .fiveFingerTap: String(localized: "Beş parmakla kısa, sabit bir dokunuş")
        case .threeFingerDoubleTap: String(localized: "Üç parmakla art arda iki kez dokun")
        case .fourFingerDoubleTap: String(localized: "Dört parmakla art arda iki kez dokun")
        case .fiveFingerDoubleTap: String(localized: "Beş parmakla art arda iki kez dokun")
        case .threeFingerHold: String(localized: "Üç parmağı kıpırdatmadan bir an beklet")
        case .tipTapLeft: String(localized: "Bir parmak dururken soluna kısa dokun")
        case .tipTapRight: String(localized: "Bir parmak dururken sağına kısa dokun")
        case .twoAnchorTipTapLeft: String(localized: "İki parmak dururken soluna dokun")
        case .twoAnchorTipTapRight: String(localized: "İki parmak dururken sağına dokun")
        case .twoFingerTipTapLeft: String(localized: "Bir parmak dururken soluna iki parmakla dokun")
        case .twoFingerTipTapRight: String(localized: "Bir parmak dururken sağına iki parmakla dokun")
        case .threeFingerSwipeLeft: String(localized: "Üç parmakla sola kaydır")
        case .threeFingerSwipeRight: String(localized: "Üç parmakla sağa kaydır")
        case .threeFingerSwipeUp: String(localized: "Üç parmakla yukarı kaydır")
        case .threeFingerSwipeDown: String(localized: "Üç parmakla aşağı kaydır")
        case .threeFingerClick: String(localized: "Üç parmak dururken trackpad'e bastırıp tıkla")
        case .fourFingerClick: String(localized: "Dört parmak dururken trackpad'e bastırıp tıkla")
        }
    }
}

enum GestureGroup: CaseIterable, Identifiable {
    case taps, clicks, tipTap, swipes

    var id: Self { self }

    var title: String {
        switch self {
        case .taps: String(localized: "Dokunma")
        case .clicks: String(localized: "Tıklama")
        case .tipTap: String(localized: "TipTap")
        case .swipes: String(localized: "3 parmak kaydırma")
        }
    }

    var footer: String? {
        switch self {
        case .taps: String(localized: "Çift dokunma eşlenirse aynı parmak sayısındaki tek dokunma, ikinci dokunuşu beklemek için biraz gecikir. Eşlenmemiş çift dokunmalar yalnızca bu pencere öndeyken tanınır.")
        case .clicks: String(localized: "Eşlenmiş tıklama jesti tetiklendiğinde tıklamanın kendisi uygulamaya gitmez. Eşlenmemişse tıklama normal çalışır.")
        case .tipTap: String(localized: "Sabit parmaklar kalkmadan art arda dokunabilirsiniz.")
        case .swipes: String(localized: "Parmaklar yeterince yol alınca, kaldırmadan tetiklenir. Sistemin kendi 3 parmak kaydırmaları kapalı olmalı.")
        }
    }

    var gestures: [Gesture] {
        switch self {
        case .taps: [.threeFingerTap, .fourFingerTap, .fiveFingerTap,
                     .threeFingerDoubleTap, .fourFingerDoubleTap, .fiveFingerDoubleTap,
                     .threeFingerHold]
        case .clicks: [.threeFingerClick, .fourFingerClick]
        case .tipTap: [.tipTapLeft, .tipTapRight, .twoAnchorTipTapLeft, .twoAnchorTipTapRight,
                       .twoFingerTipTapLeft, .twoFingerTipTapRight]
        case .swipes: [.threeFingerSwipeLeft, .threeFingerSwipeRight, .threeFingerSwipeUp, .threeFingerSwipeDown]
        }
    }
}

/// preset actions. no symbol keys ([, ] …) so they also work on non-us layouts.
struct ShortcutPreset: Identifiable {
    let name: String
    let shortcut: KeyShortcut
    var id: String { name }

    init(_ name: LocalizedStringResource, _ text: String) {
        self.name = String(localized: name)
        // fixed list; tests make sure every entry parses.
        self.shortcut = try! KeyShortcut(parsing: text)
    }

    struct Group: Identifiable {
        let title: String
        let presets: [ShortcutPreset]
        var id: String { title }

        init(title: LocalizedStringResource, presets: [ShortcutPreset]) {
            self.title = String(localized: title)
            self.presets = presets
        }
    }

    static let groups: [Group] = [
        Group(title: "Sekmeler", presets: [
            ShortcutPreset("Sonraki sekme", "ctrl+tab"),
            ShortcutPreset("Önceki sekme", "ctrl+shift+tab"),
            ShortcutPreset("Sonraki sekme (Chrome, VS Code)", "opt+cmd+right"),
            ShortcutPreset("Önceki sekme (Chrome, VS Code)", "opt+cmd+left"),
            ShortcutPreset("Yeni sekme", "cmd+t"),
            ShortcutPreset("Sekmeyi kapat", "cmd+w"),
            ShortcutPreset("Kapatılan sekmeyi aç", "shift+cmd+t"),
            ShortcutPreset("İlk sekme", "cmd+1"),
            ShortcutPreset("Son sekme", "cmd+9"),
            ShortcutPreset("Yeni pencere", "cmd+n"),
            ShortcutPreset("Yeni gizli pencere", "shift+cmd+n"),
        ]),
        Group(title: "Tarayıcı", presets: [
            ShortcutPreset("Geri", "cmd+left"),
            ShortcutPreset("İleri", "cmd+right"),
            ShortcutPreset("Yenile", "cmd+r"),
            ShortcutPreset("Önbelleksiz yenile", "shift+cmd+r"),
            ShortcutPreset("Adres çubuğu", "cmd+l"),
            ShortcutPreset("Sayfada bul", "cmd+f"),
            ShortcutPreset("Sonrakini bul", "cmd+g"),
            ShortcutPreset("Öncekini bul", "shift+cmd+g"),
            ShortcutPreset("Yer imi ekle", "cmd+d"),
            ShortcutPreset("Geçmiş", "cmd+y"),
            ShortcutPreset("Gerçek boyut", "cmd+0"),
            ShortcutPreset("Sayfa başı", "cmd+up"),
            ShortcutPreset("Sayfa sonu", "cmd+down"),
            ShortcutPreset("Bir sayfa yukarı", "pageup"),
            ShortcutPreset("Bir sayfa aşağı", "pagedown"),
        ]),
        Group(title: "Düzenleme", presets: [
            ShortcutPreset("Geri al", "cmd+z"),
            ShortcutPreset("Yinele", "shift+cmd+z"),
            ShortcutPreset("Kes", "cmd+x"),
            ShortcutPreset("Kopyala", "cmd+c"),
            ShortcutPreset("Yapıştır", "cmd+v"),
            ShortcutPreset("Biçimsiz yapıştır", "opt+shift+cmd+v"),
            ShortcutPreset("Tümünü seç", "cmd+a"),
            ShortcutPreset("Kaydet", "cmd+s"),
            ShortcutPreset("Farklı kaydet", "shift+cmd+s"),
            ShortcutPreset("Aç", "cmd+o"),
            ShortcutPreset("Yazdır", "cmd+p"),
            ShortcutPreset("Bul ve değiştir", "opt+cmd+f"),
        ]),
        Group(title: "Metin ve imleç", presets: [
            ShortcutPreset("Önceki kelime", "opt+left"),
            ShortcutPreset("Sonraki kelime", "opt+right"),
            ShortcutPreset("Satır başı", "ctrl+a"),
            ShortcutPreset("Satır sonu", "ctrl+e"),
            ShortcutPreset("Önceki kelimeyi sil", "opt+delete"),
            ShortcutPreset("Satırın başına kadar sil", "cmd+delete"),
            ShortcutPreset("Return", "return"),
            ShortcutPreset("Escape", "escape"),
        ]),
        Group(title: "Pencere ve uygulama", presets: [
            ShortcutPreset("Son uygulamaya geç", "cmd+tab"),
            ShortcutPreset("Pencereyi küçült", "cmd+m"),
            ShortcutPreset("Tam ekran", "ctrl+cmd+f"),
            ShortcutPreset("Pencereyi doldur", "fn+ctrl+f"),
            ShortcutPreset("Pencereyi ortala", "fn+ctrl+c"),
            ShortcutPreset("Uygulamayı gizle", "cmd+h"),
            ShortcutPreset("Diğerlerini gizle", "opt+cmd+h"),
            ShortcutPreset("Uygulamadan çık", "cmd+q"),
            ShortcutPreset("Uygulamadan zorla çık…", "opt+cmd+escape"),
        ]),
        Group(title: "Sistem", presets: [
            ShortcutPreset("Mission Control", "ctrl+up"),
            ShortcutPreset("Uygulama pencereleri", "ctrl+down"),
            ShortcutPreset("Soldaki Space", "ctrl+left"),
            ShortcutPreset("Sağdaki Space", "ctrl+right"),
            ShortcutPreset("Masaüstünü göster", "f11"),
            ShortcutPreset("Spotlight", "cmd+space"),
            ShortcutPreset("Bildirim Merkezi", "fn+n"),
            ShortcutPreset("Denetim Merkezi", "fn+c"),
            ShortcutPreset("Emoji ve semboller", "ctrl+cmd+space"),
            ShortcutPreset("Sözlükte ara", "ctrl+cmd+d"),
            ShortcutPreset("Ekranı kilitle", "ctrl+cmd+q"),
            ShortcutPreset("Ekran görüntüsü (tümü)", "shift+cmd+3"),
            ShortcutPreset("Ekran görüntüsü (alan)", "shift+cmd+4"),
            ShortcutPreset("Ekran görüntüsü araçları", "shift+cmd+5"),
        ]),
        Group(title: "Geliştirici", presets: [
            ShortcutPreset("Komut paleti (VS Code)", "shift+cmd+p"),
            ShortcutPreset("Satırı yukarı taşı", "opt+up"),
            ShortcutPreset("Satırı aşağı taşı", "opt+down"),
            ShortcutPreset("Geliştirici araçları (tarayıcı)", "opt+cmd+i"),
            ShortcutPreset("Derle (Xcode)", "cmd+b"),
            ShortcutPreset("Kenar çubuğunu aç/kapat", "ctrl+cmd+s"),
        ]),
    ]

    static func matching(_ shortcut: KeyShortcut?) -> ShortcutPreset? {
        guard let shortcut else { return nil }
        return groups.lazy.flatMap(\.presets).first { $0.shortcut.sameKeys(as: shortcut) }
    }
}

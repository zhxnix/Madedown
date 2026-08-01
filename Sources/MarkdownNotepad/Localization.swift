import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let preferenceKey = "Madedown.AppLanguage"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    var untitledDocumentName: String {
        text("Untitled", "未命名")
    }

    func text(_ english: String, _ simplifiedChinese: String) -> String {
        switch self {
        case .english:
            return english
        case .simplifiedChinese:
            return simplifiedChinese
        }
    }

    static var current: AppLanguage {
        persisted()
    }

    static func persisted(in defaults: UserDefaults = .standard) -> AppLanguage {
        guard let rawValue = defaults.string(forKey: preferenceKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .english
        }
        return language
    }

    func persist(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }
}

enum MadedownL10n {
    static func text(
        _ english: String,
        _ simplifiedChinese: String,
        language: AppLanguage = .current
    ) -> String {
        language.text(english, simplifiedChinese)
    }
}

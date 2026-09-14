import Foundation
import Security

enum KeychainStore {
    static func read(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.voiceintent.router", kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.voiceintent.router", kSecAttrAccount as String: account]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw RouterError.message("Keychain could not remove the credential (\(status)).")
            }
            return
        }
        let update = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw RouterError.message("Keychain could not save the credential (\(status)).") }
    }
}

struct SettingsDraft: Equatable {
    var assemblyAIKey: String
    var openRouterKey: String
    var model: String
    var shortcut: VoiceShortcut

    var normalized: Self {
        Self(assemblyAIKey: assemblyAIKey.trimmingCharacters(in: .whitespacesAndNewlines),
             openRouterKey: openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines),
             model: model.trimmingCharacters(in: .whitespacesAndNewlines), shortcut: shortcut)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var saved: SettingsDraft
    var assemblyAIKey: String { saved.assemblyAIKey }
    var openRouterKey: String { saved.openRouterKey }
    var model: String { saved.model }
    var shortcut: VoiceShortcut { saved.shortcut }
    var applyShortcut: ((VoiceShortcut) throws -> Void)?
    private let defaults: UserDefaults
    private let saveSecret: (String, String) throws -> Void

    init(defaults: UserDefaults = .standard,
         readSecret: (String) -> String = KeychainStore.read,
         saveSecret: @escaping (String, String) throws -> Void = { try KeychainStore.save($0, account: $1) }) {
        self.defaults = defaults
        self.saveSecret = saveSecret
        let shortcut = defaults.data(forKey: "voiceShortcut").flatMap { try? JSONDecoder().decode(VoiceShortcut.self, from: $0) }
        let storedModel = defaults.string(forKey: "generationModel") ?? OpenRouterProvider.defaultModel
        saved = SettingsDraft(assemblyAIKey: readSecret("assemblyai"), openRouterKey: readSecret("openrouter"),
                              model: OpenRouterProvider.option(storedModel) == nil ? OpenRouterProvider.defaultModel : storedModel,
                              shortcut: shortcut?.isValid == true ? shortcut! : .standard)
    }
    @Published var modeOverride: ContextMode? = UserDefaults.standard.string(forKey: "modeOverride").flatMap(ContextMode.init(rawValue:)) {
        didSet { UserDefaults.standard.set(modeOverride?.rawValue, forKey: "modeOverride") }
    }
    var isConfigured: Bool { !assemblyAIKey.isEmpty && !openRouterKey.isEmpty && OpenRouterProvider.isSupportedModel(model) }

    func save(_ draft: SettingsDraft) throws {
        let updated = draft.normalized
        guard OpenRouterProvider.option(updated.model) != nil, updated.shortcut.isValid else {
            throw RouterError.message("Choose an available OpenRouter model and a valid shortcut.")
        }
        let shortcutData = try JSONEncoder().encode(updated.shortcut)
        try applyShortcut?(updated.shortcut)
        do {
            if updated.assemblyAIKey != saved.assemblyAIKey { try saveSecret(updated.assemblyAIKey, "assemblyai") }
            if updated.openRouterKey != saved.openRouterKey { try saveSecret(updated.openRouterKey, "openrouter") }
        } catch {
            try? applyShortcut?(saved.shortcut)
            throw error
        }
        defaults.set(updated.model, forKey: "generationModel")
        defaults.set(shortcutData, forKey: "voiceShortcut")
        saved = updated
    }
}

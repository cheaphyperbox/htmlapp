import Foundation
import Security

struct AIProviderConfiguration: Equatable {
    enum Compatibility: String, CaseIterable, Identifiable {
        case openAI = "OpenAI Compatible"
        case anthropic = "Anthropic Compatible"
        var id: String { rawValue }
    }

    var compatibility: Compatibility
    var apiURL: String
    var model: String
    var apiKey: String

    var isConfigured: Bool {
        !apiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func endpointURL() -> URL? {
        let value = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if compatibility == .openAI, value.contains("chat/completions") { return URL(string: value) }
        if compatibility == .anthropic, value.hasSuffix("/messages") { return URL(string: value) }
        let trimmed = value.hasSuffix("/") ? String(value.dropLast()) : value
        switch compatibility {
        case .openAI:
            if trimmed.hasSuffix("/v1") { return URL(string: trimmed + "/chat/completions") }
            return URL(string: trimmed + "/v1/chat/completions")
        case .anthropic:
            if trimmed.hasSuffix("/v1") { return URL(string: trimmed + "/messages") }
            return URL(string: trimmed + "/v1/messages")
        }
    }
}

enum AISettingsStore {
    private static let providerKey = "ai.compatibility"
    private static let urlKey = "ai.apiURL"
    private static let modelKey = "ai.model"
    private static let uiProviderKey = "ai.ui.compatibility"
    private static let uiURLKey = "ai.ui.apiURL"
    private static let uiModelKey = "ai.ui.model"

    static var compatibility: AIProviderConfiguration.Compatibility {
        get { AIProviderConfiguration.Compatibility(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .openAI }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    static var apiURL: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? "https://api.openai.com" }
        set { UserDefaults.standard.set(newValue, forKey: urlKey) }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    static var apiKey: String {
        get { KeychainValueStore.read(account: "ai-api-key") ?? "" }
        set {
            if newValue.isEmpty { KeychainValueStore.delete(account: "ai-api-key") }
            else { KeychainValueStore.write(newValue, account: "ai-api-key") }
        }
    }

    static var configuration: AIProviderConfiguration {
        AIProviderConfiguration(compatibility: compatibility, apiURL: apiURL, model: model, apiKey: apiKey)
    }

    static var uiCompatibility: AIProviderConfiguration.Compatibility {
        get { AIProviderConfiguration.Compatibility(rawValue: UserDefaults.standard.string(forKey: uiProviderKey) ?? "") ?? .openAI }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: uiProviderKey) }
    }

    static var uiAPIURL: String {
        get { UserDefaults.standard.string(forKey: uiURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: uiURLKey) }
    }

    static var uiModel: String {
        get { UserDefaults.standard.string(forKey: uiModelKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: uiModelKey) }
    }

    static var uiAPIKey: String {
        get { KeychainValueStore.read(account: "ai-ui-api-key") ?? "" }
        set {
            if newValue.isEmpty { KeychainValueStore.delete(account: "ai-ui-api-key") }
            else { KeychainValueStore.write(newValue, account: "ai-ui-api-key") }
        }
    }

    static var uiConfiguration: AIProviderConfiguration {
        AIProviderConfiguration(compatibility: uiCompatibility, apiURL: uiAPIURL, model: uiModel, apiKey: uiAPIKey)
    }

    static var isUIOverhaulEnabled: Bool {
        !uiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && uiConfiguration.isConfigured
    }
}

enum KeychainValueStore {
    private static let service = "com.mekabrine.htmlapp.ai"

    static func write(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

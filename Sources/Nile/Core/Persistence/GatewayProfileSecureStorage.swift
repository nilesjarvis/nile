import Foundation
import Security

actor ProtectedFileGatewayProfileMetadataStorage: GatewayProfileMetadataStoring {
    private let storage: ProtectedFileStorage

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let resolvedFileURL: URL
        if let fileURL {
            resolvedFileURL = fileURL
        } else {
            resolvedFileURL = ProtectedFileStorage.applicationSupportURL(
                fileName: "gateway-profiles-v1.json",
                fileManager: fileManager
            )
        }
        storage = ProtectedFileStorage(
            fileURL: resolvedFileURL,
            fileManager: fileManager
        )
    }

    func read() throws -> Data? {
        try storage.read()
    }

    func write(_ data: Data) throws {
        try storage.write(data)
    }

    func remove() throws {
        try storage.remove()
    }
}

actor KeychainGatewayCredentialStore: GatewayCredentialStoring {
    private let service: String

    init(service: String = "com.niles.Nile.gateway-token.v1") {
        self.service = service
    }

    func token(credentialID: String) throws -> String? {
        var query = baseQuery(credentialID: credentialID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            throw GatewayProfileStoreError.credentialAccess
        }
        return token
    }

    func storeToken(_ token: String, credentialID: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw GatewayProfileStoreError.credentialAccess
        }
        let query = baseQuery(credentialID: credentialID)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw GatewayProfileStoreError.credentialAccess
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw GatewayProfileStoreError.credentialAccess
        }
    }

    func removeToken(credentialID: String) throws {
        let status = SecItemDelete(baseQuery(credentialID: credentialID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GatewayProfileStoreError.credentialAccess
        }
    }

    private func baseQuery(credentialID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialID,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}

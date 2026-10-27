import Foundation
import Security
import UserNotifications

enum DeviceToken {
    private static let service = "com.karlmageddon.Carguy"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "device", kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "device"]
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
        } else if status != errSecSuccess { throw CocoaError(.fileWriteUnknown) }
    }
}
enum Reminders {
    static func schedule(hour: Int, minute: Int, enabled: Bool) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-study"])
        guard enabled else { return }
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw NSError(domain: "Carguy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enable notifications for Carguy in iOS Settings."])
        }
        let content = UNMutableNotificationContent()
        content.title = "A few minutes in the garage"
        content.body = "Practice your Petersen docent stories and keep your streak going."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        try await center.add(UNNotificationRequest(identifier: "daily-study", content: content, trigger: trigger))
    }
}

import Foundation
import UIKit
import Contacts

@MainActor
class CommunicationIntegration {
    func sendMessage(params: [String: Any]) async throws -> ExecutionResult {
        guard let recipient = params["recipient"] as? String else {
            throw IntegrationError.missingParameter("recipient")
        }

        guard let body = params["body"] as? String else {
            throw IntegrationError.missingParameter("body")
        }

        let phoneNumber = try await resolveContact(name: recipient)

        let urlString = "sms:\(phoneNumber)&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        if let url = URL(string: urlString), await UIApplication.shared.canOpenURL(url) {
            await UIApplication.shared.open(url)
            return ExecutionResult(
                success: true,
                message: "Opening Messages to send to \(recipient)"
            )
        } else {
            throw IntegrationError.executionFailed("Cannot open Messages app")
        }
    }

    func composeEmail(params: [String: Any]) async throws -> ExecutionResult {
        guard let recipient = params["recipient"] as? String else {
            throw IntegrationError.missingParameter("recipient")
        }

        let subject = params["subject"] as? String ?? ""
        let body = params["body"] as? String ?? ""

        let email = try await resolveEmail(name: recipient)

        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let urlString = "mailto:\(email)?subject=\(subjectEncoded)&body=\(bodyEncoded)"

        if let url = URL(string: urlString), await UIApplication.shared.canOpenURL(url) {
            await UIApplication.shared.open(url)
            return ExecutionResult(
                success: true,
                message: "Opening Mail to compose email to \(recipient)"
            )
        } else {
            throw IntegrationError.executionFailed("Cannot open Mail app")
        }
    }

    func makeCall(params: [String: Any]) async throws -> ExecutionResult {
        guard let recipient = params["recipient"] as? String else {
            throw IntegrationError.missingParameter("recipient")
        }

        let isVideo = params["video"] as? Bool ?? false

        let phoneNumber = try await resolveContact(name: recipient)

        let scheme = isVideo ? "facetime" : "tel"
        let urlString = "\(scheme):\(phoneNumber)"

        if let url = URL(string: urlString), await UIApplication.shared.canOpenURL(url) {
            await UIApplication.shared.open(url)
            return ExecutionResult(
                success: true,
                message: "Calling \(recipient)"
            )
        } else {
            throw IntegrationError.executionFailed("Cannot make call")
        }
    }

    private func resolveContact(name: String) async throws -> String {
        if name.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" || $0 == " " }) {
            return name.replacingOccurrences(of: " ", with: "")
        }

        let status = await requestContactsAccess()
        guard status else {
            return name
        }

        let store = CNContactStore()
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]

        let predicate = CNContact.predicateForContacts(matchingName: name)

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

            if let contact = contacts.first,
               let phoneNumber = contact.phoneNumbers.first?.value.stringValue {
                return phoneNumber
            }
        } catch {
            print("Error fetching contacts: \(error)")
        }

        return name
    }

    private func resolveEmail(name: String) async throws -> String {
        if name.contains("@") {
            return name
        }

        let status = await requestContactsAccess()
        guard status else {
            return name
        }

        let store = CNContactStore()
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]

        let predicate = CNContact.predicateForContacts(matchingName: name)

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

            if let contact = contacts.first,
               let email = contact.emailAddresses.first?.value as String? {
                return email
            }
        } catch {
            print("Error fetching contacts: \(error)")
        }

        return name
    }

    private func requestContactsAccess() async -> Bool {
        return await withCheckedContinuation { continuation in
            let store = CNContactStore()
            store.requestAccess(for: .contacts) { granted, error in
                continuation.resume(returning: granted)
            }
        }
    }
}

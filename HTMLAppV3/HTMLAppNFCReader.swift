import Foundation
import CoreNFC

/// One-shot user-initiated foreground reader. Callback never retains web JS.
@MainActor
final class HTMLAppNFCReader: NSObject, NFCNDEFReaderSessionDelegate {
    private var session: NFCNDEFReaderSession?
    private var completion: ((Result<[[String: String]], Error>) -> Void)?

    static var available: Bool { NFCNDEFReaderSession.readingAvailable }

    func read() async throws -> [[String: String]] {
        guard Self.available else { throw NFCError.unavailable }
        guard session == nil else { throw NFCError.busy }
        return try await withCheckedThrowingContinuation { continuation in
            completion = { result in continuation.resume(with: result) }
            let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
            session.alertMessage = "Hold the iPhone near an NFC tag."
            self.session = session
            session.begin()
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let records = messages.flatMap(\.records).prefix(32).map { record -> [String: String] in
            ["typeNameFormat": String(record.typeNameFormat.rawValue),
             "type": String(data: record.type, encoding: .utf8) ?? "",
             "identifier": record.identifier.base64EncodedString(),
             "payloadBase64": record.payload.base64EncodedString()]
        }
        Task { @MainActor in finish(.success(records)) }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }

    private func finish(_ result: Result<[[String: String]], Error>) {
        guard let callback = completion else { return }
        completion = nil
        session = nil
        callback(result)
    }

    enum NFCError: LocalizedError {
        case unavailable, busy
        var errorDescription: String? {
            switch self {
            case .unavailable: return "NFC reader is not available on this device."
            case .busy: return "An NFC scan is already running."
            }
        }
    }
}

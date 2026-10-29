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

    private var pendingWrite: NFCNDEFMessage?
    private var writeContinuation: ((Result<Bool, Error>) -> Void)?

    /// Deliberately restricted to user-triggered, small plain-text NDEF
    /// writes, not arbitrary binary or system tags.
    func writeText(_ text: String) async throws -> Bool {
        guard Self.available else { throw NFCError.unavailable }
        guard session == nil else { throw NFCError.busy }
        guard !text.isEmpty, text.utf8.count <= 2048,
              let payload = NFCNDEFPayload.wellKnownTypeTextPayload(
                string: text, locale: Locale(identifier: "en")) else {
            throw NFCError.invalidPayload
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingWrite = NFCNDEFMessage(records: [payload])
            writeContinuation = { result in continuation.resume(with: result) }
            let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
            session.alertMessage = "Hold your iPhone near a writable NDEF tag. This will replace its existing message."
            self.session = session
            session.begin()
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [any NFCNDEFTag]) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = "Present exactly one NFC tag."
            session.restartPolling()
            return
        }
        session.connect(to: tag) { [weak self] connectionError in
            if let connectionError {
                session.invalidate(errorMessage: "Could not connect to this NFC tag.")
                Task { @MainActor in self?.finishWrite(.failure(connectionError)) }
                return
            }
            tag.queryNDEFStatus { [weak self] status, capacity, statusError in
                if let statusError {
                    session.invalidate(errorMessage: "Could not inspect NFC tag.")
                    Task { @MainActor in self?.finishWrite(.failure(statusError)) }
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self, let message = self.pendingWrite else { return }
                    guard status == .readWrite, capacity >= message.length else {
                        session.invalidate(errorMessage: "Tag is read-only or does not have enough space.")
                        self.finishWrite(.failure(NFCError.notWritable))
                        return
                    }
                    tag.writeNDEF(message) { [weak self] error in
                        if let error {
                            session.invalidate(errorMessage: "Could not write this NFC tag.")
                            Task { @MainActor in self?.finishWrite(.failure(error)) }
                        } else {
                            session.alertMessage = "NFC text saved."
                            session.invalidate()
                            Task { @MainActor in self?.finishWrite(.success(true)) }
                        }
                    }
                }
            }
        }
    }

    private func finishWrite(_ result: Result<Bool, Error>) {
        guard let callback = writeContinuation else { return }
        writeContinuation = nil
        pendingWrite = nil
        session = nil
        callback(result)
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
        Task { @MainActor in
            if writeContinuation != nil { finishWrite(.failure(error)) }
            else { finish(.failure(error)) }
        }
    }

    private func finish(_ result: Result<[[String: String]], Error>) {
        guard let callback = completion else { return }
        completion = nil
        session = nil
        callback(result)
    }

    enum NFCError: LocalizedError {
        case unavailable, busy, invalidPayload, notWritable
        var errorDescription: String? {
            switch self {
            case .unavailable: return "NFC reader is not available on this device."
            case .busy: return "An NFC scan is already running."
            case .invalidPayload: return "NFC text must be between 1 and 2048 UTF-8 bytes."
            case .notWritable: return "The selected tag is not writable or lacks capacity."
            }
        }
    }
}

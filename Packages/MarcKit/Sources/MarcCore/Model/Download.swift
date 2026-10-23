import Foundation

public struct Download: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Identifier<Download>

    public enum State: Hashable, Sendable, Codable {
        case inProgress(receivedBytes: Int64, expectedBytes: Int64?)
        case finished
        case failed(message: String)
        case cancelled

        public var isActive: Bool {
            if case .inProgress = self {
                true
            } else {
                false
            }
        }

        public var fractionCompleted: Double? {
            guard case let .inProgress(received, expected) = self, let expected, expected > 0 else { return nil }
            return min(Double(received) / Double(expected), 1)
        }
    }

    public let id: ID
    public let sourceURL: URL?
    public var fileName: String
    /// Final location on disk once known.
    public var fileURL: URL?
    public var state: State
    public let startedAt: Date
    public var finishedAt: Date?

    public init(
        id: ID = ID(),
        sourceURL: URL?,
        fileName: String,
        fileURL: URL? = nil,
        state: State = .inProgress(receivedBytes: 0, expectedBytes: nil),
        startedAt: Date = .now,
        finishedAt: Date? = nil,
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.fileURL = fileURL
        self.state = state
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

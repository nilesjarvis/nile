import Foundation

/// Attachment capability transport sharing the repository's active connection.
struct GatewayAttachmentService: HermesAttachmentServing, Sendable {
    private let rpc: any GatewayRPCRequesting
    private let connectionState: GatewayConnectionState
    private let dashboard: (any GatewayDashboardReading)?

    init(
        rpc: any GatewayRPCRequesting,
        connectionState: GatewayConnectionState,
        dashboard: (any GatewayDashboardReading)?
    ) {
        self.rpc = rpc
        self.connectionState = connectionState
        self.dashboard = dashboard
    }

    func attachImage(
        liveSessionID: String,
        base64: String,
        fileExtension: String,
        filename: String
    ) async throws -> AttachedImage {
        guard !liveSessionID.isBlank,
              !base64.isBlank,
              fileExtension.hasPrefix("."),
              !filename.isBlank else {
            throw HermesError(
                "image.attach_bytes requires a session, image, extension, and filename",
                retryable: false
            )
        }
        let result = try await rpc.request(
            method: "image.attach_bytes",
            params: [
                "session_id": .string(liveSessionID),
                "content_base64": .string(base64),
                "ext": .string(fileExtension),
                "filename": .string(filename),
            ],
            timeoutMilliseconds: 60_000,
            allowNullResult: false
        )
        let path = try result.requireNonBlankString(
            method: "image.attach_bytes",
            name: "path"
        )
        return AttachedImage(
            path: path,
            filename: result.optionalString("filename").flatMap {
                $0.isBlank ? nil : $0
            } ?? filename
        )
    }

    func detachImage(
        liveSessionID: String,
        path: String
    ) async throws -> Bool {
        guard !liveSessionID.isBlank, !path.isBlank else {
            throw HermesError(
                "image.detach requires a session and path",
                retryable: false
            )
        }
        let result = try await rpc.request(
            method: "image.detach",
            params: [
                "session_id": .string(liveSessionID),
                "path": .string(path),
            ],
            timeoutMilliseconds: 30_000,
            allowNullResult: true
        )
        guard case let .bool(detached)? = result["detached"] else {
            throw HermesError(
                "image.detach result was missing detached",
                retryable: false,
                requestMayHaveSucceeded: true
            )
        }
        return detached
    }

    func downloadAttachment(
        path: String,
        maxBytes: Int64
    ) async throws -> DownloadedAttachment {
        let connection = try await connectionState.requireActive()
        guard let dashboard else {
            throw HermesError(
                "Attachment downloads are unavailable for this connection",
                retryable: false
            )
        }
        return try await dashboard.download(
            connection: connection,
            path: path,
            maximumBytes: maxBytes
        )
    }
}

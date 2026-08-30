import Foundation

/// Owns command discovery, completion, and execution RPCs.
struct GatewayCommandService: HermesCommandServing, Sendable {
    private let rpc: any GatewayRPCRequesting
    private let codec = GatewayCommandCodec()

    init(rpc: any GatewayRPCRequesting) {
        self.rpc = rpc
    }

    func commandsCatalog() async throws -> CommandCatalog {
        let result = try await rpc.request(
            method: "commands.catalog",
            params: [:],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        return try codec.decodeCatalog(result)
    }

    func completeSlash(text: String) async throws -> SlashCompletions {
        let result = try await rpc.request(
            method: "complete.slash",
            params: ["text": .string(text)],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        return try codec.decodeCompletions(result)
    }

    func executeCommand(
        liveSessionID: String,
        command: String,
        route: CommandRoute
    ) async throws -> CommandExecution {
        let normalized = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "/" })
        guard !normalized.isEmpty else {
            throw HermesError("Command was empty", retryable: false)
        }
        switch route {
        case .slashExec:
            let result = try await rpc.request(
                method: "slash.exec",
                params: [
                    "session_id": .string(liveSessionID),
                    "command": .string(String(normalized)),
                ],
                timeoutMilliseconds: 60_000,
                allowNullResult: false
            )
            return try codec.decodeExecution(
                result,
                method: "slash.exec"
            )
        case .dispatch:
            let parts = normalized.split(
                maxSplits: 1,
                whereSeparator: \.isWhitespace
            )
            let result = try await rpc.request(
                method: "command.dispatch",
                params: [
                    "session_id": .string(liveSessionID),
                    "name": .string(String(parts[0])),
                    "arg": .string(
                        parts.count > 1
                            ? String(parts[1])
                            : ""
                    ),
                ],
                timeoutMilliseconds: 60_000,
                allowNullResult: false
            )
            return try codec.decodeExecution(
                result,
                method: "command.dispatch"
            )
        }
    }
}

struct TalkRuntimeEnvironment: Equatable, Sendable {
    let owner: TalkOwner?
    let canListen: Bool
    let isForeground: Bool
}

struct TalkSubmission: Equatable, Sendable {
    let owner: TalkOwner
    let entryID: String
    let text: String
}

struct TalkSubmissionFailure: Equatable, Sendable {
    let owner: TalkOwner
    let entryID: String?
    let uncertain: Bool
    let message: String
}

typealias TalkEnvironmentProvider =
    @MainActor @Sendable () -> TalkRuntimeEnvironment
typealias TalkErrorHandler = @MainActor @Sendable (String?) -> Void
typealias TalkSubmissionHandler =
    @MainActor @Sendable (TalkSubmission) -> Void
typealias TalkSubmissionFailureHandler =
    @MainActor @Sendable (TalkSubmissionFailure) -> Void
typealias TalkStopHandler = @MainActor @Sendable () -> Void

extension SessionTalkRuntime {
    typealias Environment = TalkRuntimeEnvironment
    typealias Submission = TalkSubmission
    typealias SubmissionFailure = TalkSubmissionFailure
    typealias EnvironmentProvider = TalkEnvironmentProvider
    typealias ErrorHandler = TalkErrorHandler
    typealias SubmissionHandler = TalkSubmissionHandler
    typealias SubmissionFailureHandler = TalkSubmissionFailureHandler
    typealias StopHandler = TalkStopHandler
}

extension NileAccessibilityID {
    static let goalButton = "niles.goal.button"
    static let goalCard = "niles.goal.card"
    static let goalSheet = "niles.goal.sheet"
    static let goalObjective = "niles.goal.objective"
    static let goalDetailsObjective = "niles.goal.details_objective"
    static let goalBudgetDefault = "niles.goal.budget.default"
    static let goalStart = "niles.goal.start"
    static let goalPause = "niles.goal.pause"
    static let goalResume = "niles.goal.resume"
    static let goalContinue = "niles.goal.continue"
    static let goalClear = "niles.goal.clear"
    static let blockingPrompt = "niles.blocking.prompt"
    static let blockingPromptAction = "niles.blocking.action"
    static let blockingPromptStatus = "niles.blocking.status"
    static let blockingPromptOtherAnswer = "niles.blocking.other_answer"
    static let blockingPromptContinue = "niles.blocking.continue"
    static let blockingPromptAlwaysConfirm = "niles.blocking.always_confirm"
    static let blockingPromptSecureEntry = "niles.blocking.secure_entry"
    static let blockingPromptSecureSubmit = "niles.blocking.secure_submit"

    static func blockingPrompt(_ id: String) -> String {
        "niles.blocking.prompt.\(id)"
    }

    static func goalBudget(_ turns: Int) -> String {
        "niles.goal.budget.\(turns)"
    }
}

#if DEBUG || NILE_LOCAL_RELEASE
import Foundation

extension SessionListFixture {
    var blockingEvents: [HermesStreamEvent] {
        switch self {
        case .blockingClarification:
            [
                .clarificationRequest(
                    sessionID: "live-brand",
                    requestID: "clarify-fixture",
                    question: "Which environment?",
                    choices: ["Staging", "Production"]
                ),
            ]
        case .blockingApprovals:
            [
                .approvalRequest(
                    sessionID: "live-brand",
                    command: "./deploy --staging",
                    description: "Deploy the staged build",
                    allowPermanent: true
                ),
                .approvalRequest(
                    sessionID: "live-brand",
                    command: "./verify --release",
                    description: "Verify the release",
                    allowPermanent: false
                ),
            ]
        case .blockingSudo:
            [
                .sudoRequest(
                    sessionID: "live-brand",
                    requestID: "sudo-fixture"
                ),
            ]
        case .blockingSecret:
            [
                .secretRequest(
                    sessionID: "live-brand",
                    requestID: "secret-fixture",
                    envVar: "DEPLOY_TOKEN",
                    prompt: "Enter the deployment token",
                    metadata: SecretRequestMetadata(
                        skillName: "deploy",
                        help: "Used only for this request.",
                        requiredFor: "release"
                    )
                ),
            ]
        case .blockingInvalid:
            [
                .blockingRequestInvalid(
                    sessionID: "live-brand",
                    requestType: "secret.request",
                    message: "Malformed secret request"
                ),
            ]
        case .empty,
             .androidBrand,
             .androidVisualBrand,
             .androidVisualMedia,
             .androidVisualAttachments,
             .androidVisualSyntax,
             .androidVisualModelPicker,
             .androidVisualDelegation,
             .androidVisualContext,
             .androidVisualStats,
             .transcriptScroll,
             .terminalBusy,
             .attachments,
             .modelPicker,
             .goalCreation,
             .goalActive:
            []
        }
    }

    var goal: HermesGoal? {
        guard self == .goalActive else {
            return nil
        }
        return HermesGoal(
            objective:
                "Finish the iOS standing-goal workflow and verify it against the pinned Android app.",
            phase: .active,
            turnsUsed: 7,
            maxTurns: 20,
            lastReason: "More work remains"
        )
    }

    var showsGoalSheet: Bool {
        self == .goalCreation
    }

    var composer: String {
        switch self {
        case .goalCreation:
            "keep my draft"
        case .androidVisualBrand:
            "Review the final interaction details"
        default:
            ""
        }
    }

    var usage: SessionUsage? {
        guard self == .androidVisualBrand else {
            return nil
        }
        return SessionUsage(
            inputTokens: 1_850,
            outputTokens: 760,
            totalTokens: 2_610,
            apiCalls: 4,
            contextPercent: 35,
            contextUsed: 45_800,
            contextMax: 131_000
        )
    }

    var modelPickerOptions: ModelOptions? {
        switch self {
        case .androidVisualModelPicker:
            return ModelOptions(
                model: "reasoning-model",
                provider: "provider",
                providers: [
                    ModelProvider(
                        slug: "provider",
                        name: "Provider",
                        authenticated: true,
                        isCurrent: true,
                        models: ["reasoning-model"],
                        capabilities: [
                            "reasoning-model": ModelCapabilities(
                                fast: true,
                                reasoning: true
                            ),
                        ]
                    ),
                ]
            )
        case .modelPicker:
            break
        default:
            return nil
        }
        return ModelOptions(
            model: "gemini-3-pro",
            provider: "google",
            providers: [
                ModelProvider(
                    slug: "google",
                    name: "Google",
                    authenticated: true,
                    isCurrent: true,
                    models: [
                        "gemini-3-flash",
                        "gemini-3-pro",
                    ],
                    capabilities: [
                        "gemini-3-flash": ModelCapabilities(
                            fast: true,
                            reasoning: true
                        ),
                        "gemini-3-pro": ModelCapabilities(
                            fast: false,
                            reasoning: true
                        ),
                    ],
                    pricing: [
                        "gemini-3-flash": ModelPricing(
                            input: "0.5",
                            output: "3",
                            cache: "0.05",
                            free: false
                        ),
                        "gemini-3-pro": ModelPricing(
                            input: "2",
                            output: "12",
                            cache: "0.2",
                            free: false
                        ),
                    ]
                ),
                ModelProvider(
                    slug: "openai",
                    name: "OpenAI",
                    authenticated: true,
                    isCurrent: false,
                    models: [
                        "gpt-5",
                        "gpt-5-mini",
                    ],
                    capabilities: [
                        "gpt-5": ModelCapabilities(
                            fast: false,
                            reasoning: true
                        ),
                        "gpt-5-mini": ModelCapabilities(
                            fast: true,
                            reasoning: true
                        ),
                    ],
                    pricing: [
                        "gpt-5": ModelPricing(
                            input: "1.25",
                            output: "10",
                            cache: "0.125",
                            free: false
                        ),
                    ],
                    unavailableModels: ["gpt-5"]
                ),
            ]
        )
    }

    var modelPins: Set<ModelPin> {
        guard self == .modelPicker else {
            return []
        }
        return [
            ModelPin(
                providerSlug: "google",
                modelID: "gemini-3-flash"
            ),
            ModelPin(
                providerSlug: "legacy-provider",
                modelID: "retired-model"
            ),
        ]
    }

    var pendingAttachments: [PendingAttachment] {
        guard self == .attachments || self == .androidVisualAttachments else {
            return []
        }
        let blue = Data(
            base64Encoded:
                "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjExLjEwMAD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABAEBAQAAAAAAAAAAAAAAAAAAAAYQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAAgACADASIAAhEAAxEA/9oADAMBAAIRAxEAPwCYBXo8AAAAAB//2Q=="
        ) ?? Data()
        let orange = Data(
            base64Encoded:
                "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjExLjEwMAD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAAAgEBAQAAAAAAAAAAAAAAAAAAAAYQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAAgACADASIAAhEAAxEA/9oADAMBAAIRAxEAPwCAEsuwAAAAAH//2Q=="
        ) ?? Data()
        return [
            PendingAttachment(
                id: "fixture-photo-one",
                filename: "workspace.jpg",
                data: blue
            ),
            PendingAttachment(
                id: "fixture-photo-two",
                filename: "reference.jpg",
                data:
                    self == .androidVisualAttachments
                        ? blue
                        : orange
            ),
        ]
    }
}
#endif

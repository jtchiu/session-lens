public enum ProviderID: String, CaseIterable, Codable, Hashable, Sendable {
    case opencode
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .opencode: "OpenCode"
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var abbreviation: String {
        switch self {
        case .opencode: "OC"
        case .claude: "CL"
        case .codex: "CX"
        }
    }
}

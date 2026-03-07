import Foundation

/// Checks team plan limits before allowing actions.
@MainActor
struct PlanEnforcer {
    enum ActionResult {
        case allowed
        case blocked(BlockReason)
    }

    enum BlockReason {
        case seatLimitReached(current: Int, limit: Int)
        case projectLimitReached(current: Int, limit: Int)
        case noPlan

        var title: String {
            switch self {
            case .seatLimitReached: return "Seat Limit Reached"
            case .projectLimitReached: return "Project Limit Reached"
            case .noPlan: return "No Active Plan"
            }
        }

        var message: String {
            switch self {
            case .seatLimitReached(let current, let limit):
                return "Your team has \(current)/\(limit) seats. Upgrade your plan to add more team members."
            case .projectLimitReached(let current, let limit):
                return "Your team has \(current)/\(limit) synced projects. Upgrade your plan to sync more projects."
            case .noPlan:
                return "Subscribe to a plan to use this feature."
            }
        }
    }

    private let premium: PremiumService

    init(premium: PremiumService = .shared) {
        self.premium = premium
    }

    /// Check if the team can add another member.
    func canAddMember(currentCount: Int) -> ActionResult {
        guard let team = premium.status.team else {
            return .blocked(.noPlan)
        }

        let effectiveLimit = effectiveSeatLimit(team: team)
        if currentCount >= effectiveLimit {
            return .blocked(.seatLimitReached(current: currentCount, limit: effectiveLimit))
        }
        return .allowed
    }

    /// Check if the team can sync another project.
    func canSyncProject(currentCount: Int) -> ActionResult {
        guard let team = premium.status.team else {
            return .blocked(.noPlan)
        }

        if let limit = effectiveProjectLimit(team: team) {
            if currentCount >= limit {
                return .blocked(.projectLimitReached(current: currentCount, limit: limit))
            }
        }
        // nil project_limit = unlimited
        return .allowed
    }

    /// Effective seat limit considering grants.
    private func effectiveSeatLimit(team: Team) -> Int {
        if let grant = premium.status.grant, let grantSeats = grant.seatLimit {
            return max(team.seatLimit, grantSeats)
        }
        return team.seatLimit
    }

    /// Effective project limit considering grants. nil = unlimited.
    private func effectiveProjectLimit(team: Team) -> Int? {
        if let grant = premium.status.grant {
            // Grant overrides — if grant has no limit, unlimited
            if grant.projectLimit == nil { return nil }
            if let grantLimit = grant.projectLimit, let teamLimit = team.projectLimit {
                return max(teamLimit, grantLimit)
            }
            return grant.projectLimit
        }
        return team.projectLimit
    }
}

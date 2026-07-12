import Foundation

enum TeamRoleContext: Equatable {
    case solo
    case owner
    case salesRep
    case technician

    init(summary: TeamWorkspaceSurfaceSummary?) {
        guard let summary else {
            self = .solo
            return
        }

        if summary.role == .owner {
            self = .owner
        } else if summary.currentMemberWorkType == .technician {
            self = .technician
        } else {
            self = .salesRep
        }
    }

    var defaultTabIndex: Int {
        switch self {
        case .solo, .owner:
            return 0
        case .salesRep:
            return 1
        case .technician:
            return MainAppTab.work.rawValue
        }
    }

    var defaultWorkSection: WorkTabSection {
        self == .technician ? .schedule : .followUps
    }

    var mapTabTitle: String {
        switch self {
        case .technician:
            return "Map"
        default:
            return "Map"
        }
    }

    var leadsTabTitle: String {
        switch self {
        case .salesRep:
            return "Mine"
        default:
            return "Leads"
        }
    }

    var workTabTitle: String {
        self == .technician ? "Jobs" : "Work"
    }

    var workScreenTitle: String {
        self == .technician ? "My Work" : "Work"
    }

    var workScheduleSectionTitle: String {
        self == .technician ? "Jobs" : "Schedule"
    }

    var workScheduleActionTitle: String {
        self == .technician ? "Schedule job" : "Schedule appointment"
    }

    var moreTabTitle: String {
        "More"
    }

    var leadScreenTitle: String {
        switch self {
        case .salesRep:
            return "My Leads"
        case .technician:
            return "Work"
        default:
            return "Leads"
        }
    }

    var appointmentScreenTitle: String {
        switch self {
        case .technician:
            return "Today's Jobs"
        case .owner:
            return "Schedule"
        default:
            return "Appointments"
        }
    }

    var appointmentEmptyTitle: String {
        switch self {
        case .technician:
            return "No jobs in this view"
        default:
            return "No appointments in this view"
        }
    }

    var workspaceMenuTitle: String {
        switch self {
        case .owner:
            return "Team Admin"
        case .salesRep:
            return "My Team"
        case .technician:
            return "Job Workspace"
        case .solo:
            return "Team Workspace"
        }
    }

    var workspaceMenuSubtitle: String {
        switch self {
        case .owner:
            return "Invites, workers, team map, and dispatch"
        case .salesRep:
            return "Assigned leads, duty status, and owner updates"
        case .technician:
            return "Assigned jobs, route, and status updates"
        case .solo:
            return "Create or join a team workspace"
        }
    }
}

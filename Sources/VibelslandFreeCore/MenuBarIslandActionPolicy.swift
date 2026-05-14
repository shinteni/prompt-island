import Foundation

package enum MenuBarIslandVisibilityAction: Equatable {
    case createAndShow
    case restoreVisible
    case keepVisible
}

package enum MenuBarIslandActionPolicy {
    package static func openPanelAction(windowExists: Bool, windowVisible: Bool) -> MenuBarIslandVisibilityAction {
        guard windowExists else {
            return .createAndShow
        }
        return windowVisible ? .keepVisible : .restoreVisible
    }
}

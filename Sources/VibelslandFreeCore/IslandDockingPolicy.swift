import CoreGraphics
import Foundation

package enum IslandDockEdge: String, Codable {
    case left, right
}

package struct IslandDockPlacement: Codable, Equatable {
    package var edge: IslandDockEdge
    package var displayID: UInt32
    package var verticalFraction: Double

    package init(edge: IslandDockEdge, displayID: UInt32, verticalFraction: Double) {
        self.edge = edge
        self.displayID = displayID
        self.verticalFraction = verticalFraction
    }
}

package enum IslandDockingPolicy {
    package static let snapDistance: CGFloat = 24
    package static let tabSize = CGSize(width: 30, height: 50)
    package static let collapseDelay: TimeInterval = 0.65

    package static func edge(for frame: CGRect, in screen: CGRect) -> IslandDockEdge? {
        // Dragging the pointer to an edge carries part of the window past it.
        // Negative distances must still dock instead of pushing the island back in.
        let left = frame.minX - screen.minX
        let right = screen.maxX - frame.maxX
        guard min(left, right) <= snapDistance else { return nil }
        return left <= right ? .left : .right
    }

    package static func frame(edge: IslandDockEdge, size: CGSize, screen: CGRect, verticalFraction: Double) -> CGRect {
        let centerY = screen.minY + screen.height * min(1, max(0, verticalFraction))
        return CGRect(
            x: edge == .left ? screen.minX : screen.maxX - size.width,
            y: min(max(centerY - size.height / 2, screen.minY), screen.maxY - size.height),
            width: size.width,
            height: size.height
        ).integral
    }
}

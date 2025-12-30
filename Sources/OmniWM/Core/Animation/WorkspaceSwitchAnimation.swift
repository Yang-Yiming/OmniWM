import Foundation
import QuartzCore

enum WorkspaceSwitch {
    case animation(SpringAnimation)
    case gesture(WorkspaceSwitchGesture)

    func currentIndex() -> Double {
        switch self {
        case let .animation(anim):
            return anim.value(at: CACurrentMediaTime())
        case let .gesture(gesture):
            return gesture.currentIndex
        }
    }

    func isAnimating() -> Bool {
        switch self {
        case let .animation(anim):
            return !anim.isComplete(at: CACurrentMediaTime())
        case .gesture:
            return true
        }
    }

    mutating func tick(at time: TimeInterval) -> Bool {
        switch self {
        case let .animation(anim):
            return !anim.isComplete(at: time)
        case .gesture:
            return true
        }
    }
}

struct WorkspaceSwitchGesture {
    var startIndex: Double
    var currentIndex: Double
    var centerIndex: Int
    let tracker: SwipeTracker
}

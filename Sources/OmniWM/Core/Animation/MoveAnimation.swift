import Foundation

struct MoveAnimation {
    let animation: SpringAnimation
    let fromOffset: CGFloat

    func currentOffset(at time: TimeInterval) -> CGFloat {
        fromOffset * CGFloat(animation.value(at: time))
    }

    func isComplete(at time: TimeInterval) -> Bool {
        animation.isComplete(at: time)
    }
}

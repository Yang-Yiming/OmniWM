import Foundation
import QuartzCore

final class AnimationClock {
    private var currentTime: TimeInterval
    private var lastSeenTime: TimeInterval
    let rate: Double = 1.0
    private(set) var shouldCompleteInstantly: Bool

    init(time: TimeInterval = CACurrentMediaTime()) {
        self.currentTime = time
        self.lastSeenTime = time
        self.shouldCompleteInstantly = false
    }

    func now() -> TimeInterval {
        let time = CACurrentMediaTime()
        guard lastSeenTime != time else { return currentTime }

        let delta = time - lastSeenTime
        currentTime += delta
        lastSeenTime = time
        return currentTime
    }

    func setCompleteInstantly(_ value: Bool) {
        shouldCompleteInstantly = value
    }
}

import Foundation
import QuartzCore

struct CubicConfig {
    let duration: Double

    init(duration: Double = 0.3) {
        self.duration = max(0.01, duration)
    }

    static let `default` = CubicConfig()
}

final class CubicAnimation {
    private(set) var from: Double
    private(set) var target: Double
    private let startTime: TimeInterval
    private let timeOffset: TimeInterval
    let config: CubicConfig
    private let clock: AnimationClock?

    init(
        from: Double,
        to: Double,
        startTime: TimeInterval,
        initialVelocity: Double = 0,
        config: CubicConfig = .default,
        clock: AnimationClock? = nil
    ) {
        self.from = from
        target = to
        self.startTime = startTime
        self.config = config
        self.clock = clock

        let range = to - from
        if abs(initialVelocity) > 0.001 && abs(range) > 0.001 {
            let normalizedVel = initialVelocity * config.duration / range
            let maxVel = 3.0
            let clampedVel = max(-maxVel, min(maxVel, normalizedVel))
            let sqrtArg = abs(clampedVel) / 3.0
            let progress = 1.0 - sqrt(sqrtArg)
            timeOffset = progress * config.duration
        } else {
            timeOffset = 0
        }
    }

    func value(at time: TimeInterval) -> Double {
        if clock?.shouldCompleteInstantly ?? false {
            return target
        }

        let elapsed = max(0, time - startTime) + timeOffset
        let progress = min(1.0, elapsed / config.duration)
        let easedProgress = 1.0 - pow(1.0 - progress, 3)

        return from + easedProgress * (target - from)
    }

    func isComplete(at time: TimeInterval) -> Bool {
        if clock?.shouldCompleteInstantly ?? false {
            return true
        }

        let elapsed = max(0, time - startTime) + timeOffset
        return elapsed >= config.duration
    }

    func velocity(at time: TimeInterval) -> Double {
        if clock?.shouldCompleteInstantly ?? false { return 0 }

        let elapsed = max(0, time - startTime) + timeOffset
        let progress = min(1.0, elapsed / config.duration)
        if progress >= 1.0 { return 0 }

        let derivative = 3.0 * pow(1.0 - progress, 2)
        return derivative * (target - from) / config.duration
    }

    func duration() -> TimeInterval {
        config.duration
    }

    func offsetBy(_ delta: Double) {
        from += delta
        target += delta
    }
}

import Foundation
import SwiftUI

struct SpringConfig {
    let duration: Double
    let bounce: Double
    let epsilon: Double
    let velocityEpsilon: Double

    init(duration: Double = 0.2, bounce: Double = 0.0, epsilon: Double = 0.5, velocityEpsilon: Double = 10.0) {
        self.duration = max(0.1, duration)
        self.bounce = min(max(bounce, -1.0), 1.0)
        self.epsilon = max(0, epsilon)
        self.velocityEpsilon = max(0, velocityEpsilon)
    }

    static let `default` = SpringConfig()

    var appleSpring: Spring {
        Spring(duration: duration, bounce: bounce)
    }
}

final class SpringAnimation {
    private(set) var from: Double
    private(set) var target: Double
    private let initialVelocity: Double
    private let startTime: TimeInterval
    let config: SpringConfig
    private let displayRefreshRate: Double

    private let spring: Spring
    private var displacement: Double

    init(
        from: Double,
        to: Double,
        initialVelocity: Double = 0,
        startTime: TimeInterval,
        config: SpringConfig = .default,
        displayRefreshRate: Double = 60.0
    ) {
        self.from = from
        target = to
        self.startTime = startTime
        self.config = config
        self.displayRefreshRate = displayRefreshRate
        self.initialVelocity = initialVelocity

        spring = config.appleSpring
        displacement = to - from
    }

    func value(at time: TimeInterval) -> Double {
        let elapsed = max(0, time - startTime)

        let springValue = spring.value(
            target: displacement,
            initialVelocity: initialVelocity,
            time: elapsed
        )

        return from + springValue
    }

    func isComplete(at time: TimeInterval) -> Bool {
        let position = value(at: time)
        let currentVelocity = velocity(at: time)

        let refreshScale = 60.0 / displayRefreshRate
        let scaledEpsilon = config.epsilon * refreshScale
        let scaledVelocityEpsilon = config.velocityEpsilon * refreshScale

        let positionSettled = abs(position - target) < scaledEpsilon
        let velocitySettled = abs(currentVelocity) < scaledVelocityEpsilon

        return positionSettled && velocitySettled
    }

    func velocity(at time: TimeInterval) -> Double {
        let elapsed = max(0, time - startTime)

        return spring.velocity(
            target: displacement,
            initialVelocity: initialVelocity,
            time: elapsed
        )
    }

    func offsetBy(_ delta: Double) {
        from += delta
        target += delta
    }
}

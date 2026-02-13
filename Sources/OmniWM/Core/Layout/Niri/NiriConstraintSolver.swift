import Foundation

enum NiriAxisSolver {
    struct Input {
        let weight: CGFloat
        let minConstraint: CGFloat
        let maxConstraint: CGFloat
        let hasMaxConstraint: Bool
        let isConstraintFixed: Bool
        let hasFixedValue: Bool
        let fixedValue: CGFloat?
    }

    struct Output {
        let value: CGFloat
        let wasConstrained: Bool
    }

    @inlinable
    static func solve(
        windows: [Input],
        availableSpace: CGFloat,
        gapSize: CGFloat,
        isTabbed: Bool = false
    ) -> [Output] {
        guard !windows.isEmpty else { return [] }

        if isTabbed {
            return solveTabbed(windows: windows, availableSpace: availableSpace)
        }

        let totalGaps = gapSize * CGFloat(max(0, windows.count - 1))
        let spaceForWindows = availableSpace - totalGaps

        guard spaceForWindows > 0 else {
            return windows.map { window in
                Output(
                    value: window.minConstraint,
                    wasConstrained: true
                )
            }
        }

        var values = [CGFloat](repeating: 0, count: windows.count)
        var isFixed = [Bool](repeating: false, count: windows.count)
        var usedSpace: CGFloat = 0

        for (i, window) in windows.enumerated() {
            if window.hasFixedValue, let fixedV = window.fixedValue {
                var clamped = fixedV
                clamped = max(clamped, window.minConstraint)
                if window.hasMaxConstraint { clamped = min(clamped, window.maxConstraint) }
                values[i] = clamped
                isFixed[i] = true
                usedSpace += clamped
            } else if window.isConstraintFixed {
                values[i] = window.minConstraint
                isFixed[i] = true
                usedSpace += values[i]
            }
        }

        let maxIterations = windows.count + 1
        var iteration = 0

        while iteration < maxIterations {
            iteration += 1

            let remainingSpace = spaceForWindows - usedSpace
            var totalWeight: CGFloat = 0

            for (i, window) in windows.enumerated() {
                if !isFixed[i] {
                    totalWeight += window.weight
                }
            }

            if totalWeight <= 0 {
                break
            }

            var anyViolation = false

            for (i, window) in windows.enumerated() {
                if isFixed[i] { continue }

                let proposedValue = remainingSpace * (window.weight / totalWeight)

                if proposedValue < window.minConstraint {
                    values[i] = window.minConstraint
                    isFixed[i] = true
                    usedSpace += window.minConstraint
                    anyViolation = true
                    break
                }
            }

            if !anyViolation {
                for (i, window) in windows.enumerated() {
                    if !isFixed[i] {
                        values[i] = remainingSpace * (window.weight / totalWeight)
                    }
                }
                break
            }
        }

        var excessSpace: CGFloat = 0

        for (i, window) in windows.enumerated() {
            if window.hasMaxConstraint, values[i] > window.maxConstraint {
                let excess = values[i] - window.maxConstraint
                values[i] = window.maxConstraint
                excessSpace += excess
                isFixed[i] = true
            }
        }

        if excessSpace > 0 {
            var remainingWeight: CGFloat = 0
            for (i, window) in windows.enumerated() {
                if !isFixed[i] {
                    remainingWeight += window.weight
                }
            }

            if remainingWeight > 0 {
                for (i, window) in windows.enumerated() {
                    if !isFixed[i] {
                        values[i] += excessSpace * (window.weight / remainingWeight)
                    }
                }
            }
        }

        var outputs: [Output] = []
        for (i, window) in windows.enumerated() {
            let wasConstrained = isFixed[i] && (
                values[i] == window.minConstraint ||
                    values[i] == window.maxConstraint
            )
            outputs.append(Output(
                value: max(1, values[i]),
                wasConstrained: wasConstrained
            ))
        }

        return outputs
    }

    @inlinable
    static func solveTabbed(
        windows: [Input],
        availableSpace: CGFloat
    ) -> [Output] {
        let maxMinConstraint = windows.map(\.minConstraint).max() ?? 1

        let fixedValue = windows.first(where: { $0.hasFixedValue && $0.fixedValue != nil })?.fixedValue

        var sharedValue: CGFloat = if let fixed = fixedValue {
            max(fixed, maxMinConstraint)
        } else {
            max(availableSpace, maxMinConstraint)
        }

        let maxMaxConstraint = windows.compactMap { $0.hasMaxConstraint ? $0.maxConstraint : nil }
            .min()
        if let maxC = maxMaxConstraint {
            sharedValue = min(sharedValue, maxC)
        }

        sharedValue = max(1, sharedValue)

        return windows.map { window in
            let wasConstrained = sharedValue == window.minConstraint ||
                (window.hasMaxConstraint && sharedValue == window.maxConstraint)
            return Output(value: sharedValue, wasConstrained: wasConstrained)
        }
    }
}

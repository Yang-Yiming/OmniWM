import CZigLayout
import Foundation
import Testing

private let axisOK: Int32 = 0
private let axisErrInvalidArgs: Int32 = -1

@Suite struct NiriZigAxisKernelTests {
    @Test func solveNormalRedistributionRespectsCascadingMaxConstraints() {
        let windows: [OmniAxisInput] = [
            OmniAxisInput(
                weight: 1,
                min_constraint: 1,
                max_constraint: 10,
                has_max_constraint: 1,
                is_constraint_fixed: 0,
                has_fixed_value: 0,
                fixed_value: 0
            ),
            OmniAxisInput(
                weight: 1,
                min_constraint: 1,
                max_constraint: 20,
                has_max_constraint: 1,
                is_constraint_fixed: 0,
                has_fixed_value: 0,
                fixed_value: 0
            ),
            OmniAxisInput(
                weight: 1,
                min_constraint: 1,
                max_constraint: 0,
                has_max_constraint: 0,
                is_constraint_fixed: 0,
                has_fixed_value: 0,
                fixed_value: 0
            )
        ]

        var output = [OmniAxisOutput](repeating: OmniAxisOutput(value: 0, was_constrained: 0), count: windows.count)
        let rc: Int32 = windows.withUnsafeBufferPointer { windowsBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                omni_axis_solve(
                    windowsBuf.baseAddress,
                    windowsBuf.count,
                    120,
                    0,
                    0,
                    outBuf.baseAddress,
                    outBuf.count
                )
            }
        }

        #expect(rc == axisOK)
        #expect(output[0].value <= 10.0001)
        #expect(output[1].value <= 20.0001)
        #expect(output[2].value >= 89.999)
    }

    @Test func axisSolveValidatesPointersForPositiveCountAndAllowsZeroCountNilPointers() {
        var output = [OmniAxisOutput](repeating: OmniAxisOutput(value: 0, was_constrained: 0), count: 1)

        let missingInputRc: Int32 = output.withUnsafeMutableBufferPointer { outBuf in
            omni_axis_solve(nil, 1, 10, 0, 0, outBuf.baseAddress, outBuf.count)
        }
        #expect(missingInputRc == axisErrInvalidArgs)

        let window = OmniAxisInput(
            weight: 1,
            min_constraint: 1,
            max_constraint: 0,
            has_max_constraint: 0,
            is_constraint_fixed: 0,
            has_fixed_value: 0,
            fixed_value: 0
        )
        let missingOutputRc: Int32 = withUnsafePointer(to: window) { windowPtr in
            omni_axis_solve(windowPtr, 1, 10, 0, 0, nil, 1)
        }
        #expect(missingOutputRc == axisErrInvalidArgs)

        let missingInputTabbedRc: Int32 = output.withUnsafeMutableBufferPointer { outBuf in
            omni_axis_solve_tabbed(nil, 1, 10, 0, outBuf.baseAddress, outBuf.count)
        }
        #expect(missingInputTabbedRc == axisErrInvalidArgs)

        let missingOutputTabbedRc: Int32 = withUnsafePointer(to: window) { windowPtr in
            omni_axis_solve_tabbed(windowPtr, 1, 10, 0, nil, 1)
        }
        #expect(missingOutputTabbedRc == axisErrInvalidArgs)

        let zeroCountRc = omni_axis_solve(nil, 0, 10, 0, 0, nil, 0)
        #expect(zeroCountRc == axisOK)

        let zeroCountTabbedRc = omni_axis_solve_tabbed(nil, 0, 10, 0, nil, 0)
        #expect(zeroCountTabbedRc == axisOK)
    }
}

import Foundation

extension Thread {
    @discardableResult
    func runInLoopAsync(
        job: RunLoopJob = RunLoopJob(),
        autoCheckCancelled: Bool = true,
        _ body: @Sendable @escaping (RunLoopJob) -> Void
    ) -> RunLoopJob {
        let action = RunLoopAction(job: job, autoCheckCancelled: autoCheckCancelled, body)
        job.action = action
        action.perform(#selector(action.action), on: self, with: nil, waitUntilDone: false)
        return job
    }

    func runInLoop<T: Sendable>(
        timeout: Duration = .seconds(2),
        _ body: @Sendable @escaping (RunLoopJob) throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let job = RunLoopJob()

        Task {
            try? await Task.sleep(for: timeout)
            job.cancel()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                self.runInLoopAsync(job: job, autoCheckCancelled: false) { job in
                    do {
                        try job.checkCancellation()
                        try cont.resume(returning: body(job))
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            job.cancel()
        }
    }
}

final class RunLoopAction: NSObject, Sendable {
    nonisolated(unsafe) private var _action: (@Sendable (RunLoopJob) -> Void)?
    let job: RunLoopJob
    private let autoCheckCancelled: Bool

    init(job: RunLoopJob, autoCheckCancelled: Bool, _ action: @escaping @Sendable (RunLoopJob) -> Void) {
        self.job = job
        self.autoCheckCancelled = autoCheckCancelled
        _action = action
    }

    @objc func action() {
        guard let actionToRun = _action else { return }
        _action = nil
        job.action = nil
        if autoCheckCancelled, job.isCancelled { return }
        actionToRun(job)
    }

    func clearAction() {
        _action = nil
    }
}

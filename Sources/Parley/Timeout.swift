import Foundation

/// The on-device model did not answer in time (Vietnamese message; distinct from the caller cancelling).
struct TimeoutError: LocalizedError, Equatable {
    let seconds: Double
    var errorDescription: String? { "AI trên máy không trả lời sau \(Int(seconds)) giây." }
}

/// Resumes a continuation exactly once — whichever comes first: the work, the timer or the caller's cancellation.
@MainActor private final class FirstResult<T: Sendable> {
    var continuation: CheckedContinuation<T, Error>?
    var work: Task<Void, Never>?
    var timer: Task<Void, Never>?

    func finish(_ result: Result<T, Error>) {
        guard let c = continuation else { return }
        continuation = nil
        timer?.cancel()
        if case .failure = result { work?.cancel() } // ask the model to stop; we don't wait for it
        c.resume(with: result)
    }
}

/// Runs main-actor work (the model's non-Sendable sessions) for at most `seconds`. It returns as soon as the time is
/// up — even when the work ignores cancellation, which keeps running and is discarded — throwing `TimeoutError`.
/// When the caller is cancelled it throws `CancellationError` at once.
@MainActor func modelTimeout<T: Sendable>(_ seconds: Double, _ work: @escaping @MainActor () async throws -> T) async throws -> T {
    let box = FirstResult<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
            box.continuation = c
            box.work = Task { @MainActor in
                do { box.finish(.success(try await work())) } catch { box.finish(.failure(error)) }
            }
            box.timer = Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { box.finish(.failure(TimeoutError(seconds: seconds))) }
            }
        }
    } onCancel: {
        Task { @MainActor in box.finish(.failure(CancellationError())) }
    }
}

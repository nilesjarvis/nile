import Foundation

actor SpeechCaptureGate {
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard held else {
            held = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            held = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

final class SpeechCapture: @unchecked Sendable {
    let generation: Int64
    private let lock = NSLock()
    private var cancelled = false
    private var finishRequested = false
    private var terminal = false
    private var source: (any PcmAudioSource)?
    private var task: Task<Void, Never>?

    init(generation: Int64) {
        self.generation = generation
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    var isFinishRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finishRequested
    }

    var isTerminal: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminal
    }

    func setTask(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel {
            task.cancel()
        }
    }

    @discardableResult
    func setSource(_ source: any PcmAudioSource) -> Bool {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return false
        }
        self.source = source
        lock.unlock()
        return true
    }

    func clearSource() {
        lock.lock()
        source = nil
        lock.unlock()
    }

    func requestFinish() {
        lock.lock()
        finishRequested = true
        let source = source
        lock.unlock()
        source?.stop()
    }

    func cancelSynchronously() {
        lock.lock()
        cancelled = true
        let source = source
        let task = task
        lock.unlock()
        source?.close()
        task?.cancel()
    }

    func markTerminalIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !terminal else {
            return false
        }
        terminal = true
        return true
    }
}

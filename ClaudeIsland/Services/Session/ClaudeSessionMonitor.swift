//
//  ClaudeSessionMonitor.swift
//  ClaudeIsland
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation

@MainActor
class ClaudeSessionMonitor: ObservableObject {
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    private var cancellables = Set<AnyCancellable>()
    private var eventTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<HookEvent>.Continuation?

    init() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        InterruptWatcherManager.shared.delegate = self
    }

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
        // Hook events MUST be processed in arrival order. Spawning a detached
        // Task per event gives no ordering guarantee, so a PreToolUse could be
        // processed after the PermissionRequest it precedes and clobber the
        // waitingForApproval phase (notch collapses with the approval unanswered).
        // An AsyncStream consumed by a single task is strictly FIFO.
        let (stream, continuation) = AsyncStream.makeStream(of: HookEvent.self)
        eventContinuation = continuation
        eventTask = Task {
            for await event in stream {
                await SessionStore.shared.process(.hookReceived(event))
            }
        }

        HookSocketServer.shared.start(
            onEvent: { event in
                // Called on the server's serial queue — yield preserves order
                continuation.yield(event)

                if event.sessionPhase == .processing {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.startWatching(
                            sessionId: event.sessionId,
                            cwd: event.cwd
                        )
                    }
                }

                if event.status == "ended" {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.stopWatching(sessionId: event.sessionId)
                    }
                }

                if event.event == "Stop" {
                    HookSocketServer.shared.cancelPendingPermissions(sessionId: event.sessionId)
                }

                if event.event == "PostToolUse", let toolUseId = event.toolUseId {
                    HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                }
            },
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            }
        )
    }

    func stopMonitoring() {
        HookSocketServer.shared.stop()
        eventContinuation?.finish()
        eventContinuation = nil
        eventTask?.cancel()
        eventTask = nil
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String) {
        respondToPermission(sessionId: sessionId, decision: "allow", reason: nil)
    }

    func denyPermission(sessionId: String, reason: String?) {
        respondToPermission(sessionId: sessionId, decision: "deny", reason: reason)
    }

    private func respondToPermission(sessionId: String, decision: String, reason: String?) {
        // Answer the socket from the published snapshot so Claude unblocks
        // immediately — hopping to the store actor first leaves the response
        // queued behind whatever JSONL parsing the actor is doing.
        if let permission = instances.first(where: { $0.sessionId == sessionId })?.activePermission {
            sendResponse(sessionId: sessionId, toolUseId: permission.toolUseId, decision: decision, reason: reason)
            return
        }

        // Snapshot can lag a permission that only just arrived — fall back to the store.
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }
            sendResponse(sessionId: sessionId, toolUseId: permission.toolUseId, decision: decision, reason: reason)
        }
    }

    private func sendResponse(sessionId: String, toolUseId: String, decision: String, reason: String?) {
        HookSocketServer.shared.respondToPermission(
            toolUseId: toolUseId,
            decision: decision,
            reason: reason
        )

        Task {
            await SessionStore.shared.process(
                decision == "allow"
                    ? .permissionApproved(sessionId: sessionId, toolUseId: toolUseId)
                    : .permissionDenied(sessionId: sessionId, toolUseId: toolUseId, reason: reason)
            )
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    // MARK: - State Update

    private func updateFromSessions(_ sessions: [SessionState]) {
        instances = sessions
        pendingInstances = sessions.filter { $0.needsAttention }
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }
}

// MARK: - Interrupt Watcher Delegate

extension ClaudeSessionMonitor: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task {
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
        }
    }
}

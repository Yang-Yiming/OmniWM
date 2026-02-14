import Foundation

@MainActor
final class FocusManager {
    private(set) var focusedHandle: WindowHandle?
    private(set) var lastFocusedByWorkspace: [WorkspaceDescriptor.ID: WindowHandle] = [:]
    private(set) var isNonManagedFocusActive: Bool = false
    private(set) var isAppFullscreenActive: Bool = false

    private var pendingFocusHandle: WindowHandle?
    private var deferredFocusHandle: WindowHandle?
    private var isFocusOperationPending = false
    private var lastFocusTime: Date = .distantPast

    var onFocusedHandleChanged: ((WindowHandle?) -> Void)?

    func setNonManagedFocus(active: Bool) {
        isNonManagedFocusActive = active
    }

    func setAppFullscreen(active: Bool) {
        isAppFullscreenActive = active
    }

    func setFocus(_ handle: WindowHandle, in workspaceId: WorkspaceDescriptor.ID) {
        focusedHandle = handle
        lastFocusedByWorkspace[workspaceId] = handle
        onFocusedHandleChanged?(handle)
    }

    func clearFocus() {
        focusedHandle = nil
        onFocusedHandleChanged?(nil)
    }

    func updateWorkspaceFocusMemory(_ handle: WindowHandle, for workspaceId: WorkspaceDescriptor.ID) {
        lastFocusedByWorkspace[workspaceId] = handle
    }

    func clearWorkspaceFocusMemory(for workspaceId: WorkspaceDescriptor.ID) {
        lastFocusedByWorkspace[workspaceId] = nil
    }

    func resolveWorkspaceFocus(
        for workspaceId: WorkspaceDescriptor.ID,
        entries: [WindowModel.Entry]
    ) -> WindowHandle? {
        lastFocusedByWorkspace[workspaceId] ?? entries.first?.handle
    }

    func handleWindowRemoved(_ handle: WindowHandle, in workspaceId: WorkspaceDescriptor.ID?) {
        if pendingFocusHandle?.id == handle.id {
            pendingFocusHandle = nil
        }
        if deferredFocusHandle?.id == handle.id {
            deferredFocusHandle = nil
        }
        if focusedHandle?.id == handle.id {
            clearFocus()
        }
        if let wsId = workspaceId,
           lastFocusedByWorkspace[wsId]?.id == handle.id
        {
            lastFocusedByWorkspace[wsId] = nil
        }
    }

    func focusWindow(
        _ handle: WindowHandle,
        workspaceId: WorkspaceDescriptor.ID,
        performFocus: @escaping () async -> Void,
        onDeferredFocus: @escaping (WindowHandle) -> Void
    ) {
        let now = Date()

        if pendingFocusHandle == handle {
            if now.timeIntervalSince(lastFocusTime) < 0.016 {
                return
            }
        }

        if isFocusOperationPending {
            deferredFocusHandle = handle
            return
        }

        isFocusOperationPending = true
        pendingFocusHandle = handle
        lastFocusTime = now
        lastFocusedByWorkspace[workspaceId] = handle

        Task { @MainActor [weak self] in
            await performFocus()
            guard let self else { return }
            self.isFocusOperationPending = false
            if let deferred = self.deferredFocusHandle, deferred != handle {
                self.deferredFocusHandle = nil
                onDeferredFocus(deferred)
            }
        }
    }

    func ensureFocusedHandleValid(
        in workspaceId: WorkspaceDescriptor.ID,
        engine: NiriLayoutEngine?,
        workspaceManager: WorkspaceManager,
        focusWindowAction: (WindowHandle) -> Void
    ) {
        if let focused = focusedHandle,
           workspaceManager.entry(for: focused)?.workspaceId == workspaceId
        {
            lastFocusedByWorkspace[workspaceId] = focused
            if let engine,
               let node = engine.findNode(for: focused)
            {
                var state = workspaceManager.niriViewportState(for: workspaceId)
                if state.selectedNodeId != node.id {
                    state.selectedNodeId = node.id
                    workspaceManager.updateNiriViewportState(state, for: workspaceId)
                }
            }
            return
        }

        if let remembered = lastFocusedByWorkspace[workspaceId],
           workspaceManager.entry(for: remembered) != nil
        {
            setFocus(remembered, in: workspaceId)
            if let engine,
               let node = engine.findNode(for: remembered)
            {
                var state = workspaceManager.niriViewportState(for: workspaceId)
                state.selectedNodeId = node.id
                workspaceManager.updateNiriViewportState(state, for: workspaceId)
            }
            focusWindowAction(remembered)
            return
        }

        let newHandle = workspaceManager.entries(in: workspaceId).first?.handle
        if let newHandle {
            setFocus(newHandle, in: workspaceId)
            if let engine,
               let node = engine.findNode(for: newHandle)
            {
                var state = workspaceManager.niriViewportState(for: workspaceId)
                state.selectedNodeId = node.id
                workspaceManager.updateNiriViewportState(state, for: workspaceId)
            }
            focusWindowAction(newHandle)
        } else {
            clearFocus()
        }
    }
}

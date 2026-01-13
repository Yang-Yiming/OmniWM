import CoreGraphics
import Foundation

final class WindowModel {
    final class Entry {
        let handle: WindowHandle
        var axRef: AXWindowRef
        var workspaceId: WorkspaceDescriptor.ID
        let windowId: Int
        var hiddenProportionalPosition: CGPoint?

        var layoutReason: LayoutReason = .standard

        var parentKind: ParentKind = .tilingContainer

        var prevParentKind: ParentKind?

        var cachedConstraints: WindowSizeConstraints?
        var constraintsCacheTime: Date?

        init(
            handle: WindowHandle,
            axRef: AXWindowRef,
            workspaceId: WorkspaceDescriptor.ID,
            windowId: Int,
            hiddenProportionalPosition: CGPoint?
        ) {
            self.handle = handle
            self.axRef = axRef
            self.workspaceId = workspaceId
            self.windowId = windowId
            self.hiddenProportionalPosition = hiddenProportionalPosition
        }
    }

    private(set) var entries: [WindowHandle: Entry] = [:]
    private var keyToHandle: [WindowKey: WindowHandle] = [:]
    private var handlesByWorkspace: [WorkspaceDescriptor.ID: [WindowHandle]] = [:]
    private var windowIdToHandle: [Int: WindowHandle] = [:]

    struct WindowKey: Hashable {
        let pid: pid_t
        let windowId: Int
    }

    func upsert(window: AXWindowRef, pid: pid_t, windowId: Int, workspace: WorkspaceDescriptor.ID) -> WindowHandle {
        let key = WindowKey(pid: pid, windowId: windowId)
        if let handle = keyToHandle[key] {
            entries[handle]?.axRef = window
            return handle
        } else {
            let handle = WindowHandle(id: UUID(), pid: pid, axElement: window.element)
            let entry = Entry(
                handle: handle,
                axRef: window,
                workspaceId: workspace,
                windowId: windowId,
                hiddenProportionalPosition: nil
            )
            entries[handle] = entry
            keyToHandle[key] = handle
            handlesByWorkspace[workspace, default: []].append(handle)
            windowIdToHandle[windowId] = handle
            return handle
        }
    }

    func updateWorkspace(for handle: WindowHandle, workspace: WorkspaceDescriptor.ID) {
        guard let oldWorkspace = entries[handle]?.workspaceId else { return }
        if oldWorkspace != workspace {
            handlesByWorkspace[oldWorkspace]?.removeAll { $0 == handle }
            handlesByWorkspace[workspace, default: []].append(handle)
        }
        entries[handle]?.workspaceId = workspace
    }

    func windows(in workspace: WorkspaceDescriptor.ID) -> [Entry] {
        guard let handles = handlesByWorkspace[workspace] else { return [] }
        return handles.compactMap { entries[$0] }
    }

    func workspace(for handle: WindowHandle) -> WorkspaceDescriptor.ID? {
        entries[handle]?.workspaceId
    }

    func entry(for handle: WindowHandle) -> Entry? {
        entries[handle]
    }

    func entry(forPid pid: pid_t, windowId: Int) -> Entry? {
        let key = WindowKey(pid: pid, windowId: windowId)
        guard let handle = keyToHandle[key] else { return nil }
        return entries[handle]
    }

    func entries(forPid pid: pid_t) -> [Entry] {
        entries.values.filter { $0.handle.pid == pid }
    }

    func entry(forWindowId windowId: Int) -> Entry? {
        guard let handle = windowIdToHandle[windowId] else { return nil }
        return entries[handle]
    }

    func entry(forWindowId windowId: Int, inVisibleWorkspaces visibleIds: Set<WorkspaceDescriptor.ID>) -> Entry? {
        guard let handle = windowIdToHandle[windowId] else { return nil }
        guard let entry = entries[handle] else { return nil }
        guard visibleIds.contains(entry.workspaceId) else { return nil }
        return entry
    }

    func allEntries() -> [Entry] {
        Array(entries.values)
    }

    func setHiddenProportionalPosition(_ position: CGPoint?, for handle: WindowHandle) {
        entries[handle]?.hiddenProportionalPosition = position
    }

    func isHiddenInCorner(_ handle: WindowHandle) -> Bool {
        entries[handle]?.hiddenProportionalPosition != nil
    }

    func layoutReason(for handle: WindowHandle) -> LayoutReason {
        entries[handle]?.layoutReason ?? .standard
    }

    func setLayoutReason(_ reason: LayoutReason, for handle: WindowHandle) {
        guard let entry = entries[handle] else { return }
        if reason != .standard, entry.layoutReason == .standard {
            entry.prevParentKind = entry.parentKind
        }
        entry.layoutReason = reason
    }

    func restoreFromNativeState(for handle: WindowHandle) -> ParentKind? {
        guard let entry = entries[handle],
              entry.layoutReason != .standard,
              let prevKind = entry.prevParentKind else { return nil }
        entry.layoutReason = .standard
        entry.parentKind = prevKind
        entry.prevParentKind = nil
        return prevKind
    }

    func removeMissing(keys activeKeys: Set<WindowKey>) {
        let toRemove = keyToHandle.keys.filter { !activeKeys.contains($0) }
        for key in toRemove {
            if let handle = keyToHandle[key] {
                if let entry = entries[handle] {
                    handlesByWorkspace[entry.workspaceId]?.removeAll { $0 == handle }
                    windowIdToHandle.removeValue(forKey: entry.windowId)
                }
                entries.removeValue(forKey: handle)
                keyToHandle.removeValue(forKey: key)
            }
        }
    }

    func removeWindow(key: WindowKey) {
        if let handle = keyToHandle[key] {
            if let entry = entries[handle] {
                handlesByWorkspace[entry.workspaceId]?.removeAll { $0 == handle }
                windowIdToHandle.removeValue(forKey: entry.windowId)
            }
            entries.removeValue(forKey: handle)
            keyToHandle.removeValue(forKey: key)
        }
    }

    func cachedConstraints(for handle: WindowHandle, maxAge: TimeInterval = 5.0) -> WindowSizeConstraints? {
        guard let entry = entries[handle],
              let cached = entry.cachedConstraints,
              let cacheTime = entry.constraintsCacheTime,
              Date().timeIntervalSince(cacheTime) < maxAge else {
            return nil
        }
        return cached
    }

    func setCachedConstraints(_ constraints: WindowSizeConstraints, for handle: WindowHandle) {
        guard let entry = entries[handle] else { return }
        entry.cachedConstraints = constraints
        entry.constraintsCacheTime = Date()
    }

}

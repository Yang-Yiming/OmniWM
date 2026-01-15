import Foundation

enum OmniWMFocusNotificationKey {
    static let oldWorkspaceId = "oldWorkspaceId"
    static let newWorkspaceId = "newWorkspaceId"
    static let oldWorkspaceName = "oldWorkspaceName"
    static let newWorkspaceName = "newWorkspaceName"
    static let oldMonitorIndex = "oldMonitorIndex"
    static let newMonitorIndex = "newMonitorIndex"
    static let oldMonitorName = "oldMonitorName"
    static let newMonitorName = "newMonitorName"
    static let oldWindowId = "oldWindowId"
    static let newWindowId = "newWindowId"
    static let oldHandleId = "oldHandleId"
    static let newHandleId = "newHandleId"
}

extension Notification.Name {
    static let omniwmFocusChanged = Notification.Name("OmniWM.FocusChanged")
    static let omniwmFocusedWorkspaceChanged = Notification.Name("OmniWM.FocusedWorkspaceChanged")
    static let omniwmFocusedMonitorChanged = Notification.Name("OmniWM.FocusedMonitorChanged")
}

import AppKit
import SwiftUI

struct StatusBarMenuView: View {
    @Binding var settings: SettingsStore
    let controller: WMController

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.2"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            GlassMenuDivider()
            togglesSection
            GlassMenuDivider()
            actionsSection
            GlassMenuDivider()
            linksSection
            GlassMenuDivider()
            quitSection
        }
        .padding(.vertical, 8)
        .frame(width: 260)
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "o.circle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("OmniWM")
                    .font(.system(size: 15, weight: .semibold))
                Text("v\(appVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var togglesSection: some View {
        GlassMenuSection {
            GlassToggleRow(label: "Focus Follows Mouse", isOn: $settings.focusFollowsMouse)
                .onChange(of: settings.focusFollowsMouse) { _, newValue in
                    controller.setFocusFollowsMouse(newValue)
                }
            GlassToggleRow(label: "Move Mouse to Focused Window", isOn: $settings.moveMouseToFocusedWindow)
                .onChange(of: settings.moveMouseToFocusedWindow) { _, newValue in
                    controller.setMoveMouseToFocusedWindow(newValue)
                }
            GlassToggleRow(label: "Window Borders", isOn: $settings.bordersEnabled)
                .onChange(of: settings.bordersEnabled) { _, newValue in
                    controller.setBordersEnabled(newValue)
                }
            GlassToggleRow(label: "Workspace Bar", isOn: $settings.workspaceBarEnabled)
                .onChange(of: settings.workspaceBarEnabled) { _, newValue in
                    controller.setWorkspaceBarEnabled(newValue)
                }
            GlassToggleRow(label: "Keep Awake", isOn: $settings.preventSleepEnabled)
                .onChange(of: settings.preventSleepEnabled) { _, newValue in
                    controller.setPreventSleepEnabled(newValue)
                }
        }
    }

    private var actionsSection: some View {
        GlassMenuSection {
            GlassMenuRow(icon: "slider.horizontal.3", action: {
                AppRulesWindowController.shared.show(settings: settings, controller: controller)
            }) {
                Text("App Rules…")
                    .font(.system(size: 13))
            }
            GlassMenuRow(icon: "gearshape", action: {
                SettingsWindowController.shared.show(settings: settings, controller: controller)
            }) {
                Text("Settings…")
                    .font(.system(size: 13))
            }
        }
    }

    private var linksSection: some View {
        GlassMenuSection {
            GlassMenuRow(icon: "link", action: {
                if let url = URL(string: "https://github.com/BarutSRB/OmniWM") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("GitHub")
                    .font(.system(size: 13))
            }
            GlassMenuRow(icon: "heart", action: {
                if let url = URL(string: "https://github.com/sponsors/BarutSRB") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("Sponsor on GitHub")
                    .font(.system(size: 13))
            }
            GlassMenuRow(icon: "heart", action: {
                if let url = URL(string: "https://paypal.me/beacon2024") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("Sponsor on PayPal")
                    .font(.system(size: 13))
            }
        }
    }

    private var quitSection: some View {
        GlassMenuRow(icon: "power", action: {
            NSApplication.shared.terminate(nil)
        }) {
            Text("Quit OmniWM")
                .font(.system(size: 13))
        }
    }
}

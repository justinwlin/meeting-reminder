import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                if controller.hasGoogleAccess {
                    Label(controller.googleEmail ?? "Google Calendar connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Google Calendar not connected", systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }

                if let authError = controller.authError {
                    Text(authError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if controller.hasGoogleAccess {
                Button {
                    controller.disconnectGoogle()
                } label: {
                    Label("Disconnect Google", systemImage: "person.crop.circle.badge.minus")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    controller.connectGoogle()
                } label: {
                    Label(controller.isConnectingGoogle ? "Connecting..." : "Connect Google", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isConnectingGoogle)
            }

            Divider()

            // Speed picker — how long the plane takes to cross the screen
            VStack(alignment: .leading, spacing: 4) {
                Text("Plane speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("Plane speed", selection: $controller.flightDuration) {
                    Text("Slow").tag(AppController.slowSpeed)
                    Text("Normal").tag(AppController.normalSpeed)
                    Text("Fast").tag(AppController.fastSpeed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            Button {
                controller.testAirplane()
            } label: {
                Label("Test airplane", systemImage: "airplane")
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit MeetingReminder", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 260)
    }
}

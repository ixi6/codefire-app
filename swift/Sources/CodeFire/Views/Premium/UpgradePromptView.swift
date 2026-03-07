import SwiftUI

/// Wrapper to make PlanEnforcer.BlockReason work with .sheet(item:)
struct IdentifiableBlock: Identifiable {
    let id = UUID()
    let reason: PlanEnforcer.BlockReason
}

/// Shown when a plan limit blocks an action.
struct UpgradePromptView: View {
    let reason: PlanEnforcer.BlockReason
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text(reason.title)
                .font(.system(size: 16, weight: .semibold))

            Text(reason.message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            HStack(spacing: 12) {
                Button("Upgrade Plan") {
                    onUpgrade()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button("Not Now") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 340, height: 220)
    }
}

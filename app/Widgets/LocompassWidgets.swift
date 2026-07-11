import WidgetKit
import SwiftUI
import ActivityKit

@main
struct LocompassWidgetBundle: WidgetBundle {
    var body: some Widget {
        NavActivityWidget()
    }
}

struct NavActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavActivityAttributes.self) { context in
            // Lock screen banner — this presentation is also what the Apple
            // Watch Smart Stack mirrors.
            HStack(spacing: 16) {
                arrow(context.state, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.friendName).font(.headline)
                    Text(context.state.distanceText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(context.state.sourceText)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    arrow(context.state, size: 40).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.friendName).font(.headline)
                        Text(context.state.distanceText)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.sourceText)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } compactLeading: {
                arrow(context.state, size: 18)
            } compactTrailing: {
                Text(context.state.distanceText).font(.caption2)
            } minimal: {
                arrow(context.state, size: 18)
            }
        }
    }

    @ViewBuilder
    private func arrow(_ state: NavActivityAttributes.ContentState, size: CGFloat) -> some View {
        if let angle = state.angle {
            Image(systemName: "location.north.fill")
                .resizable().scaledToFit()
                .frame(width: size, height: size)
                .rotationEffect(.degrees(angle))
        } else {
            Image(systemName: "arrow.triangle.2.circlepath")
                .resizable().scaledToFit()
                .frame(width: size, height: size)
        }
    }
}

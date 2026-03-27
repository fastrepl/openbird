import SwiftUI
import OpenbirdKit

struct RawLogInspectorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.rawEvents) { event in
                HStack(alignment: .top, spacing: 12) {
                    ActivityAppIcon(bundleId: event.bundleId, appName: event.appName)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(OpenbirdDateFormatting.timeString(for: event.startedAt)) – \(OpenbirdDateFormatting.timeString(for: event.endedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if event.isExcluded {
                                Label("Excluded", systemImage: "eye.slash")
                                    .font(.caption)
                            }
                        }
                        Text(event.appName)
                            .font(.headline)
                        Text(event.displayTitle)
                        if let url = event.url {
                            Text(url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if event.visibleText.isEmpty == false {
                            Text(event.visibleText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .navigationTitle("Raw Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 540)
    }
}

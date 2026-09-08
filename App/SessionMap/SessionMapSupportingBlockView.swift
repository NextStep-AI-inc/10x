import Charts
import SwiftUI

struct SessionMapSupportingBlockView: View {
    let block: SessionMapBlock
    let onAction: (SessionMapAction) -> Void

    var body: some View {
        switch block {
        case .section(let title, let blocks):
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(TenXTypography.accent(size: 14))
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, child in
                    SessionMapSupportingBlockView(block: child, onAction: onAction)
                }
            }
        case .row(let blocks):
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { rowBlocks(blocks) }
                VStack(alignment: .leading, spacing: 10) { rowBlocks(blocks) }
            }
        case .text(let text):
            compactDocument(text)
        case .stat(_, let label, let value, let tone):
            stat(label: label, value: value, tone: tone)
        case .timeline(let events):
            timeline(events)
        case .files(let files):
            fileList(files)
        case .chart(let kind, let points):
            chart(kind: kind, points: points)
        case .checklist(let items):
            checklist(items)
        case .callout(let title, let tone, let ref, let text):
            callout(title: title, tone: tone, ref: ref, text: text)
        case .next(let steps):
            nextSteps(steps)
        }
    }

    @ViewBuilder
    private func rowBlocks(_ blocks: [SessionMapBlock]) -> some View {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, child in
            SessionMapSupportingBlockView(block: child, onAction: onAction)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func compactDocument(_ text: String) -> some View {
        ContentDocumentView(
            document: MessageContentParser.parse(text),
            spacing: 6,
            bodySize: 12)
    }

    private func stat(label: String, value: String, tone: SessionMapTone) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(TenXTypography.accent(size: 20))
                .foregroundStyle(color(for: tone))
            Text(label)
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func chart(kind: SessionMapChartKind, points: [SessionMapChartPoint]) -> some View {
        Chart(Array(points.indices), id: \.self) { index in
            let point = points[index]
            if kind == .bar {
                BarMark(x: .value("Position", String(index)), y: .value("Value", point.value))
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                    .annotation(position: .top) { chartLabel(point) }
                    .accessibilityLabel(point.label)
                    .accessibilityValue(point.value.formatted())
            } else {
                LineMark(x: .value("Position", String(index)), y: .value("Value", point.value))
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                PointMark(x: .value("Position", String(index)), y: .value("Value", point.value))
                    .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                    .annotation(position: .top) { chartLabel(point) }
                    .accessibilityLabel(point.label)
                    .accessibilityValue(point.value.formatted())
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(minWidth: 100)
        .frame(height: 86)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind == .bar ? "Bar chart" : "Line chart")
    }

    private func chartLabel(_ point: SessionMapChartPoint) -> some View {
        Text("\(point.label) \(point.value.formatted())")
            .font(TenXTypography.body(size: 9, weight: .medium))
            .accessibilityLabel(point.label)
            .accessibilityValue(point.value.formatted())
    }

    private func timeline(_ events: [SessionMapTimelineEvent]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                HStack(alignment: .top, spacing: 7) {
                    Circle().fill(color(for: event.tone)).frame(width: 6, height: 6).padding(.top, 5)
                    Text(event.time).font(TenXTypography.body(size: 10, weight: .semibold))
                    Text(event.text).font(TenXTypography.body(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    if let ref = event.ref {
                        Button("Jump") { onAction(.jump(ref: ref)) }
                            .buttonStyle(GhostActionStyle(horizontalPadding: 4))
                    }
                }
            }
        }
    }

    private func fileList(_ files: [SessionMapFile]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: fileIcon(file.change))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    VStack(alignment: .leading, spacing: 2) {
                        TranscriptReferenceView(reference: .file(path: file.path, line: nil))
                        if let note = file.note {
                            Text(note).font(TenXTypography.body(size: 11))
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        }
                    }
                }
            }
        }
    }

    private func checklist(_ items: [SessionMapChecklistItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Label(item.text, systemImage: item.done ? "checkmark.circle.fill" : "circle")
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(item.done
                        ? TenXPalette.color(TenXPalette.interactiveCyanHex)
                        : TenXPalette.color(TenXPalette.nearBlackHex))
                    .accessibilityLabel("\(item.done ? "Done" : "Not done"), \(item.text)")
            }
        }
    }

    private func callout(title: String, tone: SessionMapTone, ref: String?, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(TenXTypography.body(size: 12, weight: .semibold))
            Text(text).font(TenXTypography.body(size: 12))
            if let ref {
                Button("Jump") { onAction(.jump(ref: ref)) }.buttonStyle(GhostActionStyle())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(for: tone).opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func nextSteps(_ steps: [SessionMapNextStep]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Next steps").font(TenXTypography.accent(size: 14))
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(step.text).font(TenXTypography.body(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Use") { onAction(.usePrompt(step.prompt)) }
                        .buttonStyle(GhostActionStyle())
                }
            }
        }
    }

    private func color(for tone: SessionMapTone) -> Color {
        switch tone {
        case .neutral: TenXPalette.color(TenXPalette.nearBlackHex)
        case .good: TenXPalette.color(TenXPalette.interactiveCyanHex)
        case .warn: TenXPalette.color(TenXPalette.yellowHex)
        case .bad: TenXPalette.color(TenXPalette.signalRedHex)
        }
    }

    private func fileIcon(_ change: SessionMapFileChange) -> String {
        switch change {
        case .edited: "pencil"
        case .created: "plus"
        case .read: "eye"
        }
    }
}

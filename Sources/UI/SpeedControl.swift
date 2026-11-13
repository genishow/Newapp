import SwiftUI

/// "Reading speed" under the player (D-440). The words never change here: the same script
/// is read again at another speed, and the new reading replaces the audio, so the player,
/// the download, the video and later fixes all use it. A speed already recorded comes back
/// free and at once; a new one costs what voicing the script costs, said on the button.
struct SpeedControl: View {
    @EnvironmentObject private var state: AppState
    let jobId: String
    let job: JobStatus
    /// Called when the new reading is in place, to reload the player.
    let onChanged: () -> Void

    @State private var busy: String?
    @State private var batchId: String?
    @State private var started = Date()
    @State private var problem: String?
    @State private var asking: String?

    static let levels: [(id: String, title: String)] = [
        ("slow", "Slower"), ("normal", "Normal"), ("fast", "Faster"),
    ]

    private var current: String { job.pace ?? "normal" }

    private func isReady(_ pace: String) -> Bool {
        (job.pacesReady ?? []).contains { $0.pace == pace }
    }

    private func title(_ id: String) -> String {
        T(Self.levels.first { $0.id == id }?.title ?? id)
    }

    private var price: String {
        let p = job.pacePrice ?? 0
        return p == p.rounded() ? String(Int(p)) : String(format: "%.1f", p)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Tf("Reading speed, now %@", title(current)))
                .font(Theme.smallMedium).foregroundStyle(Theme.black)
                .accessibilityIdentifier("speedNow")
            HStack(spacing: 8) {
                ForEach(Self.levels, id: \.id) { level in
                    Button {
                        choose(level.id)
                    } label: {
                        VStack(spacing: 2) {
                            if busy == level.id {
                                ProgressView().tint(Theme.black)
                            } else {
                                Text(T(level.title)).font(Theme.smallMedium)
                            }
                            Text(level.id == current ? T("Playing")
                                 : isReady(level.id) ? T("Free")
                                 : Tf("%@ credits", price))
                                .font(Theme.font(11, .medium, relativeTo: .caption2))
                                .foregroundStyle(Theme.muted)
                        }
                        .foregroundStyle(Theme.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(level.id == current ? Theme.lime : Theme.white))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.black, lineWidth: level.id == current ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy != nil)
                    .accessibilityIdentifier("speed-\(level.id)")
                }
            }
            if let busy {
                HStack(spacing: 8) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Tf("Reading it %@ · %@", title(busy).lowercased(),
                                Fmt.clock(context.date.timeIntervalSince(started))))
                            .font(Theme.small).monospacedDigit()
                    }
                    Spacer()
                    Button(T("Stop")) { Task { await stop() } }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("speedStop")
                }
                NoteText(text: T("The whole script is read again at this speed. Your words stay the same."))
            }
            if let problem {
                Text(problem).font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("speedProblem")
            }
        }
        // keeps the buttons inside findable on their own
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("speedControl")
        .confirmationDialog(asking.map { Tf("Read it %@?", title($0).lowercased()) } ?? "",
                            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible) {
            if let pace = asking {
                Button(Tf("Read it %@ · %@ credits", title(pace).lowercased(), price)) {
                    Task { await change(to: pace) }
                }
                .accessibilityIdentifier("speedConfirm")
            }
            Button(T("Cancel"), role: .cancel) { asking = nil }
        } message: {
            Text(T("The whole script is read again at this speed and replaces this audio. The speed you have now stays saved, so going back to it is free."))
        }
    }

    private func choose(_ pace: String) {
        problem = nil
        guard pace != current else { return }
        if isReady(pace) {
            Task { await change(to: pace) }
        } else {
            asking = pace
        }
    }

    private func change(to pace: String) async {
        asking = nil
        guard busy == nil else { return }
        busy = pace
        started = Date()
        defer { busy = nil; batchId = nil }
        do {
            var batch = try await state.api.changePace(jobId: jobId, pace: pace)
            batchId = batch.batchId
            var misses = 0
            var tries = 0
            while !batch.isOver, let id = batch.batchId, tries < 600 {
                tries += 1
                try await Task.sleep(nanoseconds: UInt64((Launch.isMock ? 0.2 : 2) * 1_000_000_000))
                do {
                    batch = try await state.api.fixStatus(jobId: jobId, batchId: id)
                    misses = 0
                } catch {
                    // A dropped look is not a failed reading, as with fixes.
                    misses += 1
                    if misses > 30 { throw error }
                }
            }
            if batch.status == "done" {
                await state.refresh()
                onChanged()
            } else if batch.status == "failed" {
                problem = batch.error.map(APIError.sentenceCase) ?? T("That speed could not be recorded.")
            } else if batch.status != "cancelled" {
                problem = T("Still reading. It will be ready here in a minute.")
            }
        } catch {
            if !Task.isCancelled { problem = state.report(error) }
        }
    }

    private func stop() async {
        guard let batchId else { return }
        try? await state.api.fixCancel(jobId: jobId, batchId: batchId)
    }
}

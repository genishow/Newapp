import AVFoundation
import SwiftUI

/// Earn credits by making a short video about Kinbir (D-450). The video is reviewed by
/// Kinbir; an approved one adds credits, with a notification and an email.
struct PromoView: View {
    @EnvironmentObject private var state: AppState

    @State private var list: PromoList?
    @State private var picking = false
    @State private var picked: URL?
    @State private var pickedSeconds: Double = 0
    @State private var link = ""
    @State private var note = ""
    @State private var rightsOk = false
    @State private var sending = false
    @State private var stage = ""
    @State private var problem: String?
    @State private var sentNote: String?

    private var reward: String { Fmt.credits(list?.reward ?? 20) }
    private var lengthOk: Bool { pickedSeconds >= 10 && pickedSeconds <= 180 }
    private var canSend: Bool { picked != nil && lengthOk && rightsOk && !sending }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(T("Earn credits")).screenTitle(amharic: A("Earn credits"))
                    .accessibilityIdentifier("promoHeading")

                Text(Tf("Make a short video about Kinbir, like a TikTok or a Reel, and send it here. When we approve it, you get %@ credits.", reward))
                    .font(Theme.body).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .card(fill: Theme.lime)

                tips

                if let sentNote {
                    Text(sentNote).font(Theme.body).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .card(fill: Theme.grey, padding: 14)
                        .accessibilityIdentifier("promoSentNote")
                }
                form

                if let promos = list?.promos, !promos.isEmpty {
                    Text(T("Your videos")).font(Theme.heading).foregroundStyle(Theme.black)
                    ForEach(promos) { promo in
                        row(promo)
                    }
                }
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $picking) {
            VideoLibraryPicker { url in
                picking = false
                Task { await choose(url) }
            }
            .ignoresSafeArea()
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("What works")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
            ForEach([
                T("10 seconds to 3 minutes, filmed upright (vertical)."),
                T("Show Kinbir on your screen and say what you made with it."),
                T("Your own face and voice are welcome. Speak in Amharic or English."),
                T("No music or clips you do not own. Use music from the app you post on, or none."),
                T("Posted it on TikTok, Instagram or YouTube? Add the link."),
            ], id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").font(Theme.body).foregroundStyle(Theme.black)
                    Text(line).font(Theme.small).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card(fill: Theme.white, padding: 14)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                problem = nil
                sentNote = nil
                if Launch.isMock {
                    // the UI tests cannot drive the photo picker
                    Task { await choose(FileManager.default.temporaryDirectory.appendingPathComponent("mock.mp4")) }
                } else {
                    picking = true
                }
            } label: {
                Text(picked == nil ? T("Choose my video") : T("Choose another video"))
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(sending)
            .accessibilityIdentifier("promoChooseVideo")

            if picked != nil {
                Text(lengthOk ? Tf("Video chosen, %@ long.", Fmt.clock(pickedSeconds))
                              : Tf("This video is %@ long. It needs to be between 10 seconds and 3 minutes.", Fmt.clock(pickedSeconds)))
                    .font(Theme.small).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("promoChosenNote")
            }

            TextField(T("Link to your post (optional)"), text: $link)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(Theme.body)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.black, lineWidth: 1))
                .accessibilityIdentifier("promoLink")
            TextField(T("Anything we should know (optional)"), text: $note, axis: .vertical)
                .lineLimit(1...4)
                .font(Theme.body)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.black, lineWidth: 1))
                .accessibilityIdentifier("promoNote")

            Button {
                Haptics.tap()
                rightsOk.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: rightsOk ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22)).foregroundStyle(Theme.black)
                    Text(T("I made this video, everyone in it agreed, and Kinbir may use and edit it in its own ads and posts."))
                        .font(Theme.small).foregroundStyle(Theme.black)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(sending)
            .accessibilityIdentifier("promoRightsTick")
            Link(T("Read the terms"), destination: URL(string: "https://kinbir.com/terms")!)
                .font(Theme.smallMedium).foregroundStyle(Theme.black)

            if let problem {
                ProblemCard(message: problem)
            }
            Button {
                Task { await send() }
            } label: {
                BusyLabel(title: sending ? stage : T("Send my video"), busy: sending)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSend)
            .accessibilityIdentifier("promoSend")
        }
        .card(fill: Theme.grey, padding: 14)
    }

    private func row(_ promo: PromoSubmission) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                switch promo.status {
                case "approved":
                    Pill(text: Tf("Approved · +%@ credits", Fmt.credits(promo.credits ?? 0)), fill: Theme.lime)
                case "rejected":
                    Pill(text: T("Not approved"), fill: Theme.grey)
                default:
                    Pill(text: T("Waiting for review"), fill: Theme.white)
                }
                Spacer()
                Text(Fmt.ago(promo.createdAt)).font(Theme.small).foregroundStyle(Theme.muted)
            }
            if promo.status == "rejected", let reason = promo.reason, !reason.isEmpty {
                Text(reason).font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let link = promo.link {
                Text(link).font(Theme.small).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
        .card(fill: Theme.white, padding: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("promoRow")
    }

    private func load() async {
        do {
            list = try await state.api.myPromos()
        } catch {
            problem = state.report(error)
        }
    }

    private func choose(_ url: URL?) async {
        guard let url else { return }
        picked = url
        pickedSeconds = Launch.isMock ? 30 : await VideoFiles.seconds(of: url)
    }

    private func send() async {
        guard let picked else { return }
        sending = true
        problem = nil
        defer { sending = false }
        do {
            stage = T("Getting it ready")
            let ready = Launch.isMock ? picked : await PromoVideo.prepare(picked)
            stage = T("Sending")
            _ = try await state.api.submitPromo(videoURL: ready, link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                                                note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            Haptics.success()
            sentNote = T("Sent. We will watch it soon, and you will get a notification and an email when it is checked.")
            self.picked = nil
            pickedSeconds = 0
            link = ""
            note = ""
            rightsOk = false
            await load()
        } catch {
            problem = state.report(error)
        }
    }
}

/// Makes a phone video small enough to send: Full HD when it is large, and smaller
/// still for a long one. A video that is already small is sent as it is.
enum PromoVideo {
    static let sendAsIsBytes = 60 * 1024 * 1024
    static let maxBytes = 140 * 1024 * 1024

    static func prepare(_ source: URL) async -> URL {
        if VideoFiles.bytes(of: source) <= sendAsIsBytes { return source }
        if let full = await export(source, preset: AVAssetExportPreset1920x1080),
           VideoFiles.bytes(of: full) <= maxBytes {
            return full
        }
        return await export(source, preset: AVAssetExportPreset1280x720) ?? source
    }

    private static func export(_ source: URL, preset: String) async -> URL? {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinbir-promo-" + UUID().uuidString)
            .appendingPathExtension("mp4")
        session.outputURL = target
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        return session.status == .completed ? target : nil
    }
}

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
    /// One field per post; more can be added.
    @State private var links: [LinkEntry] = [LinkEntry()]
    /// The video whose "add links" field is open, and what is typed there.
    @State private var addingTo: String?
    @State private var addLink = ""
    @State private var adding = false
    @State private var note = ""
    @State private var rightsOk = false
    @State private var sending = false
    @State private var stage = ""
    @State private var problem: String?
    @State private var sentNote: String?

    private var reward: String { Fmt.credits(list?.reward ?? 40) }
    private var perPlatform: String { Fmt.credits(list?.perPlatform ?? 10) }
    private var filledLinks: [String] {
        links.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var lengthOk: Bool { pickedSeconds >= 60 && pickedSeconds <= 180 }
    private var linkOk: Bool { !filledLinks.isEmpty && filledLinks.allSatisfy(PromoRules.isSocialLink) }
    private var canSend: Bool { picked != nil && lengthOk && linkOk && rightsOk && !sending }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Text(T("Earn credits")).screenTitle(amharic: A("Earn credits"))
                    .accessibilityIdentifier("promoHeading")

                Text(Tf("Make a video about Kinbir and post it on your social media. Earn %@ credits for each of TikTok, Instagram, YouTube and Facebook, %@ for all four. Credits arrive within a few hours, at most 2 days.", perPlatform, reward))
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
                if let left = list?.videosLeft, left <= 0 {
                    Text(Tf("You have sent %@ videos for free credits, the most one account can send. Thank you for sharing Kinbir!", "\(list?.maxVideos ?? 10)"))
                        .font(Theme.body).foregroundStyle(Theme.black)
                        .fixedSize(horizontal: false, vertical: true)
                        .card(fill: Theme.grey, padding: 14)
                        .accessibilityIdentifier("promoLimitReached")
                } else {
                    if let left = list?.videosLeft {
                        Text(Tf("You can send %@ more of %@ videos.", "\(left)", "\(list?.maxVideos ?? 10)"))
                            .font(Theme.small).foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("promoVideosLeft")
                    }
                    form
                }

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
            Text(T("How it works")).font(Theme.bodyMedium).foregroundStyle(Theme.black)
            ForEach([
                T("1. Film a video about Kinbir, at least 1 minute and at most 3, upright (vertical)."),
                T("2. Post it on your own TikTok, Instagram, YouTube and Facebook, and keep it up."),
                T("3. Paste the link to each post and send them here with the same video."),
                T("Posted somewhere new later? Add the link to your video below and earn the rest."),
                T("Up to 10 videos per account. A video that is not approved does not count."),
                T("Show Kinbir on your screen and say what you made with it. Amharic or English."),
                T("No music or clips you do not own. Use music from the app you post on, or none."),
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
                              : Tf("This video is %@ long. It needs to be between 1 and 3 minutes.", Fmt.clock(pickedSeconds)))
                    .font(Theme.small).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("promoChosenNote")
            }

            Text(T("Links to your posts")).font(Theme.smallMedium).foregroundStyle(Theme.black)
            ForEach($links) { $entry in
                let first = entry.id == links.first?.id
                HStack(spacing: 8) {
                    linkField(T(first ? "Link to your post" : "Another post link"), text: $entry.text)
                        .accessibilityIdentifier(first ? "promoLink" : "promoLinkMore")
                    if !first {
                        Button {
                            let id = entry.id
                            links.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "minus.circle").font(.system(size: 20)).foregroundStyle(Theme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(T("Remove link"))
                    }
                }
            }
            if links.count < 6 {
                Button {
                    links.append(LinkEntry())
                } label: {
                    Label(T("Add another link"), systemImage: "plus")
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("promoAddLink")
            }
            if filledLinks.contains(where: { !PromoRules.isSocialLink($0) }) {
                Text(T("Paste links to your posts on TikTok, Instagram, YouTube or Facebook."))
                    .font(Theme.small).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("promoLinkNote")
            } else if !filledLinks.isEmpty {
                let count = PromoRules.rewardedPlatforms(filledLinks)
                Text(Tf("%@ of 4 platforms · up to %@ credits", "\(count)",
                        Fmt.credits(Double(count) * (list?.perPlatform ?? 10))))
                    .font(Theme.small).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("promoPlatformCount")
            }
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
                    Text(T(PromoRules.rightsText))
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
                    Pill(text: T("Waiting for review · within 2 days"), fill: Theme.white)
                }
                Spacer()
                Text(Fmt.ago(promo.createdAt)).font(Theme.small).foregroundStyle(Theme.muted)
            }
            if promo.status == "rejected", let reason = promo.reason, !reason.isEmpty {
                Text(reason).font(Theme.small).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(promo.allLinks, id: \.self) { link in
                Text(link).font(Theme.small).foregroundStyle(Theme.muted).lineLimit(1)
            }
            if promo.status != "rejected" {
                if addingTo == promo.promoId {
                    linkField(T("Link to your new post"), text: $addLink)
                        .accessibilityIdentifier("promoAddLinkField")
                    HStack {
                        Button {
                            Task { await addLinks(to: promo) }
                        } label: {
                            BusyLabel(title: T("Add link"), busy: adding)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(adding || !PromoRules.isSocialLink(addLink))
                        .accessibilityIdentifier("promoAddLinkSend")
                        Button(T("Cancel")) { addingTo = nil; addLink = "" }
                            .buttonStyle(QuietButtonStyle())
                    }
                } else {
                    Button {
                        addingTo = promo.promoId
                        addLink = ""
                    } label: {
                        Label(T("Posted somewhere else? Add a link"), systemImage: "plus")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("promoAddMoreLinks")
                }
            }
        }
        .card(fill: Theme.white, padding: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("promoRow")
    }

    private func linkField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .font(Theme.body)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.black, lineWidth: 1))
    }

    private func addLinks(to promo: PromoSubmission) async {
        adding = true
        defer { adding = false }
        do {
            _ = try await state.api.addPromoLinks(
                promoId: promo.promoId, links: [addLink.trimmingCharacters(in: .whitespacesAndNewlines)])
            addingTo = nil
            addLink = ""
            sentNote = T("Link added. We check it within a few hours, at most 2 days, and add the credits for the new platform.")
            await load()
        } catch {
            problem = state.report(error)
        }
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
        pickedSeconds = Launch.isMock ? 75 : await VideoFiles.seconds(of: url)
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
            _ = try await state.api.submitPromo(videoURL: ready, links: filledLinks,
                                                note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            Haptics.success()
            sentNote = T("Sent. We review every video within a few hours, at most 2 days. You get a notification and an email as soon as your credits are added.")
            self.picked = nil
            pickedSeconds = 0
            links = [LinkEntry()]
            note = ""
            rightsOk = false
            await load()
        } catch {
            problem = state.report(error)
        }
    }
}

struct LinkEntry: Identifiable, Equatable {
    let id = UUID()
    var text = ""
}

enum PromoRules {
    /// What the customer agrees to, word for word as the server records it.
    static let rightsText = "I made this video and posted it on my own social media. Everyone in it agreed. I give Kinbir a free, permanent, worldwide right to use, edit, repost and share it on Kinbir's social media, website and ads, with or without my name."

    static let socialHosts = ["tiktok.com", "instagram.com", "youtube.com", "youtu.be", "facebook.com",
                              "fb.watch", "fb.com", "x.com", "twitter.com", "snapchat.com", "threads.net", "linkedin.com"]

    static let rewardedHosts: [(String, [String])] = [
        ("tiktok", ["tiktok.com"]), ("instagram", ["instagram.com"]),
        ("youtube", ["youtube.com", "youtu.be"]), ("facebook", ["facebook.com", "fb.watch", "fb.com"]),
    ]

    /// How many of TikTok, Instagram, YouTube and Facebook these links cover.
    static func rewardedPlatforms(_ links: [String]) -> Int {
        let hosts = links.compactMap { host(of: $0) }
        return rewardedHosts.filter { _, names in
            hosts.contains { h in names.contains { h == $0 || h.hasSuffix("." + $0) } }
        }.count
    }

    static func host(of raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        return URLComponents(string: text)?.host?.lowercased()
    }

    /// True for a link to a post on one of the social apps the server accepts.
    static func isSocialLink(_ raw: String) -> Bool {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let host = URLComponents(string: text)?.host?.lowercased() else { return false }
        return socialHosts.contains { host == $0 || host.hasSuffix("." + $0) }
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

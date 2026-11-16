import PhotosUI
import SwiftUI
import UIKit

/// The talking presenter: one photo of the user, shown speaking in the video.
struct AvatarCard: View {
    @EnvironmentObject private var state: AppState
    @Binding var choice: AvatarChoice
    let audioSec: Double
    let shape: Shape

    @State private var info: AvatarInfo?
    @State private var photo: UIImage?
    @State private var declared = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var busy = false
    @State private var problem: String?

    private var ready: Bool { info?.isReady == true }
    @State private var askedForMore = false

    /// Accounts that have not paid get short appearances (the server enforces it too).
    private var paid: Bool { state.me?.hasPaid == true }
    private var maxSeconds: Int { paid ? AvatarChoice.maxSeconds : AvatarChoice.freeMaxSeconds }
    /// Presenter tries left before the first purchase; nil when there is no limit.
    private var freeLeft: Int? { paid ? nil : state.me?.avatarFreeLeft }

    /// Brings every length inside what this account may use.
    private func capLengths() {
        let cap = maxSeconds
        if choice.seconds > cap { choice.seconds = cap }
        if let s = choice.startSeconds, s > cap { choice.startSeconds = cap }
        if let e = choice.endSeconds, e > cap { choice.endSeconds = cap }
        choice.middles = choice.middles.map { min($0, cap) }
        if !paid { choice.wholeVideo = false }
        if freeLeft != nil { choice.middles = [] }
    }

    /// Full frame, at four times the price, when the photo and the video share a shape.
    private var fullFrame: Bool {
        guard let photo else { return false }
        return (photo.size.width >= photo.size.height) == (shape == .landscape)
    }

    private var presenterSeconds: Double { choice.totalSeconds(audioSec: audioSec) }

    private var quote: Double {
        AvatarChoice.credits(seconds: presenterSeconds, fullFrame: fullFrame)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Presenter")).font(Theme.heading).foregroundStyle(Theme.black)
            Text(T("Your photo, speaking your voiceover."))
                .font(Theme.small).foregroundStyle(Theme.muted)

            if let problem {
                NoteText(text: problem).accessibilityIdentifier("avatarProblem")
            }

            if ready {
                photoRow
                if freeLeft == 0 {
                    // The one free try is used: the presenter opens with a purchase.
                    VStack(alignment: .leading, spacing: 10) {
                        Text(T("You have used your free presenter. It opens again after your first purchase."))
                            .font(Theme.body).foregroundStyle(Theme.black)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(T("Buy credits")) {
                            state.selectedTab = 2
                            state.pendingAccountRoute = .buyCredits
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("avatarBuyCredits")
                    }
                    .card(fill: Theme.grey, padding: 14)
                    .accessibilityIdentifier("avatarLocked")
                    .onAppear { choice.enabled = false }
                } else {
                    Toggle(T("Use the presenter in this video"), isOn: $choice.enabled)
                        .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
                        .accessibilityIdentifier("avatarToggle")
                    if freeLeft != nil {
                        NoteText(text: T("Free try: one 5-second appearance in one video. More opens after your first purchase."))
                            .accessibilityIdentifier("avatarFreeTryNote")
                    }
                    if choice.enabled { options }
                }
            } else {
                uploadPart
            }
        }
        .card(fill: Theme.white)
        .task {
            capLengths()
            await load()
        }
        .onChange(of: paid) { _, _ in capLengths() }
        .onChange(of: pickerItem) { _, item in
            if let item { Task { await upload(item) } }
        }
    }

    private var photoRow: some View {
        HStack(spacing: 12) {
            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Image(systemName: "person.fill").font(.system(size: 22)).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 56, height: 56)
            .background(Theme.grey)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.black, lineWidth: 1))
            Text(T("Your photo is saved")).font(Theme.body).foregroundStyle(Theme.black)
                .accessibilityIdentifier("avatarReady")
            Spacer()
            Button(T("Remove")) { Task { await remove() } }
                .buttonStyle(QuietButtonStyle())
                .disabled(busy)
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Length of each appearance")).font(Theme.smallMedium).foregroundStyle(Theme.black)
            Picker(T("Seconds"), selection: Binding(
                get: { choice.seconds },
                set: { picked in
                    // Longer appearances are for accounts that have bought credits.
                    if picked > maxSeconds {
                        choice.seconds = maxSeconds
                        askedForMore = true
                    } else {
                        choice.seconds = picked
                        askedForMore = false
                    }
                })) {
                ForEach(AvatarChoice.lengths, id: \.self) { Text("\($0)s").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("avatarLengthPicker")
            if !paid {
                Text(T("Free accounts get up to 5 seconds. Longer appearances open after your first credit purchase."))
                    .font(askedForMore ? Theme.smallMedium : Theme.small)
                    .foregroundStyle(askedForMore ? Theme.black : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(askedForMore ? 10 : 0)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(askedForMore ? Theme.lime.opacity(0.45) : Color.clear))
                    .accessibilityIdentifier("avatarPaidNote")
            }

            Text(T("Where do you appear?")).font(Theme.smallMedium).foregroundStyle(Theme.black)
            // One appearance is at most 14 seconds; the whole-video choice is gone (Geni).
            places
            // The free try is one appearance, so no middle ones until a purchase.
            if freeLeft == nil { middlePart }
            delivery
        }
    }

    private var endFits: Bool { choice.endFits(audioSec: audioSec) }
    private var middleFits: Bool { choice.middleFits(audioSec: audioSec) }

    /// At the start and at the end, each with its own length.
    private var places: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(T("At the start"), isOn: $choice.atStart)
                .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
                .accessibilityIdentifier("avatarStartToggle")
            if choice.atStart {
                secondsStepper(Binding(get: { choice.startSeconds ?? choice.seconds },
                                       set: { choice.startSeconds = $0 }))
                    .accessibilityIdentifier("avatarStartSeconds")
            }
            Toggle(T("At the end"), isOn: Binding(get: { choice.atEnd && endFits },
                                                  set: { choice.atEnd = $0 }))
                .font(Theme.body).foregroundStyle(endFits ? Theme.black : Theme.muted).tint(Theme.black)
                .disabled(!endFits)
                .accessibilityIdentifier("avatarEndToggle")
            if !endFits {
                NoteText(text: T("Needs a longer video to fit with the start."))
            } else if choice.atEnd {
                secondsStepper(Binding(get: { choice.endSeconds ?? choice.seconds },
                                       set: { choice.endSeconds = $0 }))
                    .accessibilityIdentifier("avatarEndSeconds")
            }
        }
    }

    /// How many times in the middle, and how long each one is.
    private var middlePart: some View {
        let fitCount = choice.middlesThatFit(audioSec: audioSec)
        return VStack(alignment: .leading, spacing: 10) {
            Stepper(value: Binding(get: { choice.middles.count },
                                   set: { choice.setMiddleCount($0) }),
                    in: 0...AvatarChoice.maxMiddles) {
                Text(Tf("In the middle: %@ times", "\(choice.middles.count)"))
                    .font(Theme.body).foregroundStyle(middleFits ? Theme.black : Theme.muted)
            }
            .disabled(!middleFits && choice.middles.isEmpty)
            .accessibilityIdentifier("avatarMiddleStepper")
            ForEach(Array(choice.middles.indices), id: \.self) { index in
                secondsStepper(Binding(
                    get: { index < choice.middles.count ? choice.middles[index] : choice.seconds },
                    set: { if index < choice.middles.count { choice.middles[index] = $0 } }),
                               label: Tf("Middle %@", "\(index + 1)"))
                    .accessibilityIdentifier("avatarMiddleSeconds-\(index + 1)")
            }
            if !middleFits {
                NoteText(text: T("Needs a longer video to fit between the others."))
            } else if fitCount < choice.middles.count {
                NoteText(text: Tf("Only %@ fit in a video this long. The rest are not charged.", "\(fitCount)"))
                    .accessibilityIdentifier("avatarMiddleNote")
            }
        }
    }

    private func secondsStepper(_ value: Binding<Int>, label: String? = nil) -> some View {
        Stepper(value: value, in: AvatarChoice.minSeconds...maxSeconds) {
            Text((label.map { $0 + ": " } ?? "") + Tf("%@ seconds", "\(value.wrappedValue)"))
                .font(Theme.small).foregroundStyle(Theme.black)
        }
        .padding(.leading, 12)
    }

    private var delivery: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("How do you want it delivered?")).font(Theme.smallMedium).foregroundStyle(Theme.black)
            Picker(T("Delivery"), selection: $choice.mode) {
                ForEach(AvatarChoice.Mode.allCases) { Text(T($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            NoteText(text: choice.mode == .inVideo
                     ? T("The avatar plays inside your finished video at the places you picked.")
                     : T("The video is built without it, and the avatar downloads on its own so you can cut it in yourself."))
            if choice.mode == .inVideo {
                Text(T("Where should your avatar be?")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                if shape == .portrait {
                    Picker(T("Avatar place"), selection: $choice.sideVertical) {
                        Text(T("Bottom")).tag("bottom")
                        Text(T("Top")).tag("top")
                        Text(T("Full screen")).tag("full")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("avatarSide")
                } else {
                    Picker(T("Avatar place"), selection: $choice.sideHorizontal) {
                        Text(T("Right")).tag("right")
                        Text(T("Left")).tag("left")
                        Text(T("Full screen")).tag("full")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("avatarSide")
                }
            }
            if quote > 0 {
                Text(Tf("Avatar: %@s of %@", "\(Int(presenterSeconds))", Fmt.clock(audioSec.rounded(.down))))
                    .font(Theme.small).foregroundStyle(Theme.black)
                    .accessibilityIdentifier("avatarSeconds")
                NoteText(text: Tf("The presenter adds about %@ credits. Any part that cannot be made is refunded.", Fmt.credits(quote)))
                    .accessibilityIdentifier("avatarQuote")
            } else {
                NoteText(text: T("Pick at least one place for your avatar, or turn it off."))
                    .accessibilityIdentifier("avatarNothingPicked")
            }
        }
    }

    /// What a good presenter photo looks like, drawn, next to the upload (Geni,
    /// 2026-11-16): serious face, cropped close, no empty space around the head.
    private var photoGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                guideTile(good: true)
                guideTile(good: false)
            }
            NoteText(text: T("Serious face, no smile. Crop close: head and shoulders, no empty space around."))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("avatarPhotoGuide")
    }

    private func guideTile(good: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.grey)
                Image(systemName: "person.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(Theme.black.opacity(0.75))
                    // good: the person fills the picture; not good: small, with empty space
                    .frame(width: good ? 78 : 30, height: good ? 78 : 30)
                    .offset(y: good ? 10 : 22)
            }
            .frame(width: 90, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.black, lineWidth: good ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                Image(systemName: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.black, good ? Theme.lime : Theme.white)
                    .padding(4)
            }
            Text(good ? T("Like this") : T("Not like this"))
                .font(Theme.small).foregroundStyle(Theme.black)
        }
    }

    private var uploadPart: some View {
        VStack(alignment: .leading, spacing: 10) {
            photoGuide
            Toggle(T("This is a photo of me"), isOn: $declared)
                .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
                .accessibilityIdentifier("avatarDeclare")
            if busy {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.black)
                    Text(T("Saving your photo")).font(Theme.small).foregroundStyle(Theme.black)
                }
            } else if Launch.isMock {
                // The simulator's photo library is empty, so the UI tests take this path.
                Button(T("Use sample photo")) { Task { await send(Data("sample".utf8), image: nil) } }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!declared)
                    .accessibilityIdentifier("samplePhotoButton")
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(T("Choose a photo"))
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!declared)
            }
            NoteText(text: T("A clear photo of your face, looking at the camera. Only your own photo."))
        }
    }

    private func load() async {
        guard info == nil else { return }
        info = try? await state.api.avatarInfo()
        if ready, photo == nil, let url = try? await state.api.avatarPhoto(),
           let data = try? Data(contentsOf: url) {
            photo = UIImage(data: data)
        }
        if !ready { choice.enabled = false }
    }

    private func upload(_ item: PhotosPickerItem) async {
        problem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = AvatarPhoto.jpeg(from: image) else {
            problem = T("That photo could not be read. Try another.")
            return
        }
        await send(jpeg, image: image)
    }

    private func send(_ jpeg: Data, image: UIImage?) async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            info = try await state.api.uploadAvatarPhoto(jpeg: jpeg)
            photo = image
            pickerItem = nil
        } catch {
            problem = state.report(error)
        }
    }

    private func remove() async {
        busy = true
        defer { busy = false }
        do {
            try await state.api.deleteAvatarPhoto()
            info = AvatarInfo(hasPhoto: false, verified: false)
            photo = nil
            choice.enabled = false
            declared = false
        } catch {
            problem = state.report(error)
        }
    }
}

enum AvatarPhoto {
    /// The server takes jpg under 8 MB. Photos are scaled to 2048 px on the long side first.
    static func jpeg(from image: UIImage, maxSide: CGFloat = 2048) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(),
                          height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.jpegData(compressionQuality: 0.9)
    }
}

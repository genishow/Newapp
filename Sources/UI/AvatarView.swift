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

    /// Full frame, at four times the price, when the photo and the video share a shape.
    private var fullFrame: Bool {
        guard let photo else { return false }
        return (photo.size.width >= photo.size.height) == (shape == .landscape)
    }

    private var quote: Double {
        AvatarChoice.credits(seconds: choice.totalSeconds(audioSec: audioSec), fullFrame: fullFrame)
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
                Toggle(T("Use the presenter in this video"), isOn: $choice.enabled)
                    .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
                    .accessibilityIdentifier("avatarToggle")
                if choice.enabled { options }
            } else {
                uploadPart
            }
        }
        .card(fill: Theme.white)
        .task { await load() }
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
            Toggle(T("For the whole video"), isOn: $choice.wholeVideo)
                .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
            if !choice.wholeVideo {
                Toggle(T("At the start"), isOn: $choice.atStart)
                    .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
                Toggle(T("At the end"), isOn: $choice.atEnd)
                    .font(Theme.body).foregroundStyle(Theme.black).tint(Theme.black)
                Text(T("Seconds each time")).font(Theme.smallMedium).foregroundStyle(Theme.black)
                Picker(T("Seconds"), selection: $choice.seconds) {
                    ForEach(AvatarChoice.lengths, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Picker(T("Delivery"), selection: $choice.mode) {
                ForEach(AvatarChoice.Mode.allCases) { Text(T($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            if quote > 0 {
                NoteText(text: Tf("The presenter adds about %@ credits. Any part that cannot be made is refunded.", Fmt.credits(quote)))
                    .accessibilityIdentifier("avatarQuote")
            } else {
                NoteText(text: T("Choose where the presenter appears."))
            }
        }
    }

    private var uploadPart: some View {
        VStack(alignment: .leading, spacing: 10) {
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

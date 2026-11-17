import SwiftUI

/// The questions people ask before they start, the same ones as kinbir.com
/// (Geni: "my website has the FAQ, my app needs it"). Payment answers are the
/// App Store's wording here: in the app, credits are bought through Apple.
enum FAQ {
    struct Entry: Identifiable, Equatable {
        let question: String
        let questionAm: String?
        let answer: String
        let answerAm: String?
        var id: String { question }
    }

    static let entries: [Entry] = [
        Entry(question: "Do I need to clone my voice?",
              questionAm: "ድምፄን ማስቀረፅ ግዴታ ነው?",
              answer: "No. Kinbir has a built-in voice you can use right away. Cloning your own voice is optional: record one short video once, and from then on everything is read in your voice.",
              answerAm: "አይደለም። ቅንብር ወዲያውኑ መጠቀም የሚችሉት የራሱ ድምፅ አለው። የራስዎን ድምፅ ማስቀረፅ በፍላጎት ነው፤ አንድ አጭር ቪዲዮ አንድ ጊዜ ይቅረጹ፣ ከዚያ በኋላ ሁሉም በድምፅዎ ይነበባል።"),
        Entry(question: "What does voice cloning need from me?",
              questionAm: "ድምፅ ማስመሰል ምን ይፈልጋል?",
              answer: "One short video of you reading a fixed paragraph on camera. After a quality check your voice appears in your voices. It stays private to your account and you can delete it at any time.",
              answerAm: "አንድ አንቀጽ እያነበቡ ራስዎን በካሜራ ይቅረጹ። ጥራቱ ከተረጋገጠ በኋላ ድምፅዎ በድምፆችዎ ዝርዝር ውስጥ ይገኛል። ለመለያዎ ብቻ የግል ነው፤ በማንኛውም ጊዜ ማጥፋት ይችላሉ።"),
        Entry(question: "How natural is the Amharic?",
              questionAm: "አማርኛው ምን ያህል ተፈጥሯዊ ነው?",
              answer: "Scripts are written in spoken Ethiopian style, the rhythm of broadcast, not literal translation. Voices are trained on native Amharic speech.",
              answerAm: "ስክሪፕቶቹ እንደ ንግግር ነው የሚጻፉት፤ ድምፆቹም የአፍ መፍቻ ተናጋሪ መስለው ይሰማሉ።"),
        Entry(question: "Does Kinbir do English too?",
              questionAm: "ቅንብር እንግሊዝኛም ይሠራል?",
              answer: "Yes. Set the language to English and Kinbir writes the script, reads it and finishes the video the same way. One account can hold both languages.",
              answerAm: "አዎ። ቋንቋውን ወደ እንግሊዝኛ ይቀይሩ፤ ቅንብር ስክሪፕቱን ይጽፋል፣ ያነባል፣ ቪዲዮውንም በተመሳሳይ መንገድ ያዘጋጃል።"),
        Entry(question: "Can I stop after one step?",
              questionAm: "አንድ ደረጃ ብቻ ተጠቅሜ ማቆም እችላለሁ?",
              answer: "Yes. Take only a script, or stop once you have the voiceover, and you use credits for just that. A voiceover stays ready for 48 hours, so come back within two days to turn it into a video.",
              answerAm: "አዎ። ጽሑፍ ብቻ ወይም ድምፅ ብቻ ወስደው ማቆም ይችላሉ፤ ለተጠቀሙበት ብቻ ነው ክሬዲት የሚቀነሰው። ድምፁ ለ48 ሰዓት ይቆያል፤ ወደ ቪዲዮ ለመቀየር በሁለት ቀን ውስጥ ይመለሱ።"),
        Entry(question: "How do credits and plans work?",
              questionAm: "ክሬዲትና ዕቅዶች እንዴት ይሠራሉ?",
              answer: "One balance covers every step: script, voice, footage and the finished video. New accounts start with free credits. A plan adds credits every month and renews until you cancel it in your iPhone Settings. Unused plan credits carry over, up to one month's allowance. Top-up credits never expire.",
              answerAm: "አንድ የክሬዲት ሒሳብ ሁሉንም ደረጃ ይሸፍናል። አዲስ መለያ በነፃ ክሬዲት ይጀምራል። ዕቅድ በየወሩ ክሬዲት ይጨምራል፤ በስልክዎ Settings እስኪሰርዙት ድረስ ይታደሳል።"),
        Entry(question: "How long are my files kept?",
              questionAm: "ፋይሎቼ ለምን ያህል ጊዜ ይቆያሉ?",
              answer: "Voiceovers and videos stay in your Library for 48 hours. Save what you want to keep to Photos or Files before then. Your scripts are kept.",
              answerAm: "የድምፅ ቅጂዎችና ቪዲዮዎች ለ48 ሰዓት በማህደርዎ ይቆያሉ። ማቆየት የሚፈልጉትን ከዚያ በፊት ያስቀምጡ።"),
        Entry(question: "What do I get at the end?",
              questionAm: "መጨረሻ ላይ ምን አገኛለሁ?",
              answer: "A finished video, vertical or horizontal, with captions if you want them, ready to save to Photos or share. Stop after the voice step and you get the audio instead.",
              answerAm: "የተጠናቀቀ ቪዲዮ ያገኛሉ፤ በድምፅ ደረጃ ካቆሙ ደግሞ የድምፅ ፋይል ያገኛሉ።"),
        Entry(question: "Can I earn money from the videos?",
              questionAm: "ቪዲዮዎቹን ገንዘብ ማስገኘት እችላለሁ?",
              answer: "Yes. The voiceover, the stock footage and the finished video are yours to publish and monetize on any platform. What you bring is your responsibility: write it yourself, or use material you have permission to use.",
              answerAm: "አዎ! ድምፁ፣ ምስሉና የተጠናቀቀው ቪዲዮ የእርስዎ ናቸው።"),
    ]
}

struct FAQView: View {
    @State private var open: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(T("Questions")).screenTitle(amharic: "ጥያቄዎች")
                    .accessibilityIdentifier("faqHeading")
                ForEach(FAQ.entries) { entry in
                    row(entry)
                }
                MailButton(url: URL(string: "mailto:support@kinbir.com")!) {
                    Text(T("Still have a question? Email us"))
                        .font(Theme.bodyMedium).foregroundStyle(Theme.black).underline()
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            .page()
        }
        .background(Theme.white)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ entry: FAQ.Entry) -> some View {
        let isOpen = open == entry.id
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { open = isOpen ? nil : entry.id }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.question).font(Theme.bodyMedium).foregroundStyle(Theme.black)
                            .multilineTextAlignment(.leading)
                        if let am = entry.questionAm {
                            Text(am).font(Theme.small).foregroundStyle(Theme.black.opacity(0.75))
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isOpen ? "minus" : "plus")
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.black)
                        .padding(.top, 3)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("faq-" + String(FAQ.entries.firstIndex(of: entry) ?? 0))
            if isOpen {
                Text(entry.answer).font(Theme.body).foregroundStyle(Theme.black)
                    .fixedSize(horizontal: false, vertical: true)
                if let am = entry.answerAm {
                    Text(am).font(Theme.small).foregroundStyle(Theme.black.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card(fill: isOpen ? Theme.lime : Theme.grey, padding: 14)
    }
}

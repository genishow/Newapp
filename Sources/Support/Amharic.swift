import Foundation

/// The app's interface language. Separate from the project language on the Create screen.
enum UILanguage: String, CaseIterable, Identifiable {
    case am, en
    var id: String { rawValue }
    var name: String { self == .am ? "አማርኛ" : "English" }

    static let key = "kinbir.ui"

    /// The owner tried the all-Amharic interface and preferred English, with Amharic shown
    /// small under the big titles. So the interface is English; the table below is kept for
    /// those subtitles (and for a full Amharic interface later, if wanted).
    static var current: UILanguage { .en }
}

/// Translates interface text. English is the key; an Amharic line is looked up when the
/// interface is in Amharic. Text with no Amharic line yet is shown in English.
func T(_ english: String) -> String {
    guard UILanguage.current == .am else { return english }
    return Amharic.table[english] ?? english
}

/// The Amharic for a piece of interface text, shown small under big English titles.
func A(_ english: String) -> String? {
    Amharic.table[english]
}

/// The same for text with values in it: `Tf("Shot %@", "3")`.
func Tf(_ english: String, _ values: String...) -> String {
    var out = T(english)
    for value in values {
        if let range = out.range(of: "%@") { out.replaceSubrange(range, with: value) }
    }
    return out
}

/// Amharic interface text. Reviewed by the owner before release: these lines were drafted
/// by the builder, not by a professional translator.
enum Amharic {
    static let table: [String: String] = [
        // Tabs and common words
        "Create": "ፍጠር", "Library": "ማህደር", "Account": "መለያ", "Buy credits": "ክሬዲት ይግዙ", "Earn credits": "ክሬዲት ያግኙ", "Kinbir": "ቅንብር",
        "Done": "ጨርስ", "Cancel": "ሰርዝ", "Continue": "ቀጥል", "Close": "ዝጋ", "Save": "አስቀምጥ",
        "Delete": "አጥፋ", "Rename": "ስም ቀይር", "Remove": "አስወግድ", "Change": "ቀይር",
        "Undo": "መልስ", "Clear": "አጽዳ", "Copy": "ቅዳ", "Copied": "ተቀድቷል", "Listen": "አድምጥ",
        "Use": "ተጠቀም", "Play": "አጫውት", "Pause": "ለአፍታ አቁም", "Stop": "አቁም", "Speak": "ተናገር",
        "More": "ተጨማሪ", "Name": "ስም", "None": "የለም", "Ready": "ዝግጁ", "Problem": "ችግር",
        "Try again": "እንደገና ሞክር", "Check again": "እንደገና አረጋግጥ", "credits": "ክሬዲት",
        "Automatic": "ራስ-ሰር", "Language": "ቋንቋ", "Thanks": "እናመሰግናለን", "Saved": "ተቀምጧል",
        "Tip: ": "ምክር፦ ", "Yours": "የእርስዎ", "Vertical": "ቁመታዊ", "Horizontal": "አግድም",
        "Amharic": "አማርኛ", "English": "እንግሊዝኛ",

        // Welcome and sign in
        "Amharic voiceovers in": "የአማርኛ ድምፅ ትረካ",
        "your own voice": "በራስዎ ድምፅ",
        "Write Amharic, or paste English or a link. Kinbir writes the script and reads it aloud in a voice cloned from you.":
            "በአማርኛ ይጻፉ፣ ወይም እንግሊዝኛ ጽሑፍ ወይም ሊንክ ይለጥፉ። ቅንብር ጽሑፉን አዘጋጅቶ ከእርስዎ በተቀዳ ድምፅ ያነበዋል።",
        "Hear it first": "መጀመሪያ ያድምጡ",
        "Type a short Amharic sentence": "አጭር የአማርኛ ዓረፍተ ነገር ይጻፉ",
        "Play in the Kinbir voice": "በቅንብር ድምፅ አጫውት",
        "Play again": "እንደገና አጫውት", "Preparing": "በመዘጋጀት ላይ",
        "Preparing the voice. The first time can take a minute.": "ድምፁ እየተዘጋጀ ነው። ለመጀመሪያ ጊዜ አንድ ደቂቃ ሊወስድ ይችላል።",
        "Start free": "በነፃ ጀምር",
        "Your first voiceovers are free. No card needed.": "የመጀመሪያ ትረካዎችዎ ነፃ ናቸው። ካርድ አያስፈልግም።",
        "Privacy": "ግላዊነት", "Terms": "ውሎች", "Support": "ድጋፍ",
        "Start with your email": "በኢሜይልዎ ይጀምሩ", "Enter your code": "ኮድዎን ያስገቡ",
        "No password. We email you a code. If you are new, this also creates your account.":
            "የይለፍ ቃል የለም። ኮድ በኢሜይል እንልክልዎታለን። አዲስ ከሆኑ መለያዎም በዚሁ ይፈጠራል።",
        "Send me a code": "ኮድ ላክልኝ", "Send a new code": "አዲስ ኮድ ላክ",
        "Use a different email": "ሌላ ኢሜይል ተጠቀም", "6-digit code": "ባለ 6 አሃዝ ኮድ",
        "We sent a 6-digit code to %@. It works for 10 minutes.": "ባለ 6 አሃዝ ኮድ ወደ %@ ልከናል። ለ10 ደቂቃ ይሠራል።",
        "Your email": "ኢሜይልዎ",

        // Create
        "Clone your voice first": "መጀመሪያ ድምፅዎን ያስቀዱ",
        "Read a short script on camera once. After that, every voiceover is in your voice.":
            "አጭር ጽሑፍ አንድ ጊዜ በካሜራ ፊት ያንብቡ። ከዚያ በኋላ እያንዳንዱ ትረካ በእርስዎ ድምፅ ይሆናል።",
        "Clone my voice": "ድምፄን አስቀዳ",
        "Nothing yet": "ገና ምንም የለም", "Link": "ሊንክ", "English text": "የእንግሊዝኛ ጽሑፍ",
        "English script": "የእንግሊዝኛ ስክሪፕት", "Amharic script": "የአማርኛ ስክሪፕት",
        "Get the article": "ጽሑፉን አምጣ", "Getting the article": "ጽሑፉ እየመጣ ነው",
        "Write Amharic script": "የአማርኛ ስክሪፕት ጻፍ", "Make voiceover": "ትረካ አዘጋጅ",
        "Writing": "በመጻፍ ላይ", "Starting": "በመጀመር ላይ", "One moment": "አንድ አፍታ",
        "Writing the Amharic script costs about %@ credits.": "የአማርኛ ስክሪፕት መጻፍ ወደ %@ ክሬዲት ያስከፍላል።",
        "Writing your script. You can edit it when it is done.": "ስክሪፕትዎ እየተጻፈ ነው። ሲያልቅ ማረም ይችላሉ።",
        "Free credits voice up to %@ Amharic characters at a time. This script has %@.":
            "ነፃ ክሬዲት በአንድ ጊዜ እስከ %@ የአማርኛ ፊደላት ያነባል። ይህ ስክሪፕት %@ አለው።",
        "Voice: ": "ድምፅ፦ ", "My voice": "የእኔ ድምፅ",
        "Script length": "የስክሪፕት ርዝመት", "Reading speed": "የንባብ ፍጥነት",
        "Emphasis on pauses": "በቆምታዎች ላይ አጽንዖት", "Emphasis": "አጽንዖት",
        "This voice was cloned reading Amharic, so its English has an Amharic accent. Clone an English reading for a native sound.":
            "ይህ ድምፅ የተቀዳው አማርኛ ሲያነብ ስለሆነ እንግሊዝኛው የአማርኛ ቅላጼ አለው። ለተፈጥሯዊ ድምፅ በእንግሊዝኛ አንብበው ያስቀዱ።",
        "Change the script": "ስክሪፕቱን ቀይር", "Tell Kinbir what to change": "ምን እንዲቀየር ለቅንብር ይንገሩ",
        "Change it": "ቀይረው",
        "For example: make it shorter, or start with a question. Each change costs credits.":
            "ለምሳሌ፦ አሳጥረው፣ ወይም በጥያቄ ጀምር። እያንዳንዱ ለውጥ ክሬዲት ያስከፍላል።",
        "Listening. Speak in Amharic, then tap Stop.": "እያዳመጥኩ ነው። በአማርኛ ይናገሩ፣ ከዚያ አቁምን ይንኩ።",
        "Turning your words into text.": "ንግግርዎ ወደ ጽሑፍ እየተቀየረ ነው።",
        "Clone your voice first. Your account has no voice yet.": "መጀመሪያ ድምፅዎን ያስቀዱ። መለያዎ ገና ድምፅ የለውም።",
        "Nothing was heard. Try again a little closer to the phone.": "ምንም አልተሰማም። ወደ ስልኩ ቀረብ ብለው እንደገና ይሞክሩ።",
        "Kinbir needs the microphone to hear you. Allow it in Settings, then try again.":
            "ቅንብር እርስዎን ለመስማት ማይክሮፎን ያስፈልገዋል። በቅንብሮች ውስጥ ይፍቀዱ፣ ከዚያ እንደገና ይሞክሩ።",

        // Voiceover
        "In line": "በወረፋ ላይ", "Recording your voiceover": "ትረካዎ እየተቀዳ ነው",
        "The first voiceover of a session takes a couple of minutes longer while the voice engine wakes up. You can leave this screen. It will be in your Library when it is ready.":
            "የመጀመሪያው ትረካ የድምፅ ሞተሩ እስኪነሳ ሁለት ደቂቃ ያህል ተጨማሪ ይወስዳል። ከዚህ ገጽ መውጣት ይችላሉ። ሲዘጋጅ በማህደርዎ ውስጥ ያገኙታል።",
        "This one did not work": "ይህ አልተሳካም", "Your voiceover": "የእርስዎ ትረካ",
        "Loading the audio.": "ድምፁ እየተጫነ ነው።", "Share or save": "አጋራ ወይም አስቀምጥ",
        "Kept for 48 hours. Save it if you need it later.": "ለ48 ሰዓት ይቆያል። በኋላ የሚፈልጉት ከሆነ ያስቀምጡት።",
        "Make a video": "ቪዲዮ አዘጋጅ", "Continue the video": "ቪዲዮውን ቀጥል", "Script": "ስክሪፕት",
        "A word sounds wrong? Tap it to fix it.": "አንድ ቃል በትክክል አልተነበበም? ለማስተካከል ይንኩት።",
        "Free. The audio is updated at once.": "ነፃ። ድምፁ ወዲያውኑ ይዘምናል።",
        "Make another": "ሌላ አዘጋጅ", "Part %@ of %@": "ክፍል %@ ከ %@",
        "The audio could not be opened. Use Share or save to get the file.": "ድምፁ ሊከፈት አልቻለም። ፋይሉን ለማግኘት አጋራ ወይም አስቀምጥን ይጠቀሙ።",
        "The audio could not be played. Try again.": "ድምፁ ሊጫወት አልቻለም። እንደገና ይሞክሩ።",
        "This is taking too long. Try again in a moment.": "በጣም እየቆየ ነው። ከአፍታ በኋላ እንደገና ይሞክሩ።",

        // Fix a word
        "Fix this word": "ይህን ቃል አስተካክል",
        "Listen, then use the one that sounds right": "ያድምጡ፣ ከዚያ ትክክል የሚመስለውን ይጠቀሙ",
        "No other readings exist for this word yet. Type how it should sound below.": "ለዚህ ቃል ሌላ ንባብ ገና የለም። እንዴት መነበብ እንዳለበት ከታች ይጻፉ።",
        "Or type how it should sound": "ወይም እንዴት መነበብ እንዳለበት ይጻፉ", "Your spelling": "የእርስዎ አጻጻፍ",
        "Read the whole sentence again": "ሙሉውን ዓረፍተ ነገር እንደገና አንብብ",
        "Listening to a reading is free when it has been made before; a brand new one costs under 1 credit. Using a fix costs 1.5 credits and records that sentence again.":
            "ቀድሞ የተሠራ ንባብ ማዳመጥ ነፃ ነው፤ አዲስ ንባብ ከ1 ክሬዲት በታች ያስከፍላል። ማስተካከያ መጠቀም 1.5 ክሬዲት ያስከፍላል፣ ዓረፍተ ነገሩም እንደገና ይቀዳል።",
        "Preparing this reading.": "ይህ ንባብ እየተዘጋጀ ነው።", "Recording the sentence again.": "ዓረፍተ ነገሩ እንደገና እየተቀዳ ነው።",
        "That reading could not be made. Try another.": "ያ ንባብ ሊሠራ አልቻለም። ሌላ ይሞክሩ።",
        "The fix could not be started. Try again.": "ማስተካከያው ሊጀመር አልቻለም። እንደገና ይሞክሩ።",

        // Library
        "Nothing here yet": "እዚህ ገና ምንም የለም",
        "Your voiceovers and videos appear here for 48 hours.": "ትረካዎችዎ እና ቪዲዮዎችዎ ለ48 ሰዓት እዚህ ይታያሉ።",
        "Videos": "ቪዲዮዎች", "Voiceovers": "ትረካዎች", "Did not work": "አልተሳካም", "Recording": "በመቅዳት ላይ",

        // Voices and cloning
        "My voices": "ድምፆቼ", "No voice yet": "ገና ድምፅ የለም",
        "Clone your voice to start making voiceovers.": "ትረካ መሥራት ለመጀመር ድምፅዎን ያስቀዱ።",
        "Add a voice": "ድምፅ ጨምር", "In use": "በጥቅም ላይ", "Tap to use": "ለመጠቀም ይንኩ",
        " · Amharic": " · አማርኛ", " · English": " · እንግሊዝኛ",
        "Listen to a sample": "ናሙና አድምጥ", "Preparing the sample": "ናሙናው እየተዘጋጀ ነው",
        "You have 5 voices, which is the most an account can keep. Delete one to add another.":
            "5 ድምፆች አሉዎት፤ አንድ መለያ ሊይዝ የሚችለው ከፍተኛው ይህ ነው። ሌላ ለመጨመር አንዱን ያጥፉ።",
        "Rename voice": "የድምፁን ስም ቀይር", "Delete this voice?": "ይህ ድምፅ ይጥፋ?", "Delete voice": "ድምፁን አጥፋ",
        "This cannot be undone. Voiceovers you already made are not affected.": "ይህ ሊመለስ አይችልም። ቀድሞ የሠሯቸው ትረካዎች አይነኩም።",
        "Clone your voice": "ድምፅዎን ያስቀዱ",
        "I am recording my own voice and face. I give permission for an AI voice of me to be created and used only by me.":
            "የራሴን ድምፅ እና ፊት እየቀዳሁ ነው። የእኔ የሆነ የኤአይ ድምፅ እንዲፈጠር እና በእኔ ብቻ ጥቅም ላይ እንዲውል እፈቅዳለሁ።",
        "Reading language": "የንባብ ቋንቋ",
        "Read in English to get a voice with a native English sound.": "ተፈጥሯዊ የእንግሊዝኛ ድምፅ ለማግኘት በእንግሊዝኛ ያንብቡ።",
        "Read this aloud": "ይህን ጮክ ብለው ያንብቡ",
        "A quiet room, no music or TV.": "ጸጥ ያለ ክፍል፣ ሙዚቃ ወይም ቲቪ የሌለበት።",
        "Hold the phone close, about an arm's length.": "ስልኩን በክንድ ርቀት ያህል ቀረብ አድርገው ይያዙ።",
        "Read naturally, the way you normally speak.": "እንደተለመደው አነጋገርዎ በተፈጥሯዊ መንገድ ያንብቡ።",
        "10 to 40 seconds.": "ከ10 እስከ 40 ሰከንድ።",
        "Creating your voice. This can take a minute.": "ድምፅዎ እየተፈጠረ ነው። አንድ ደቂቃ ሊወስድ ይችላል።",
        "Record now": "አሁን ቅዳ", "Choose a video": "ቪዲዮ ምረጥ", "Your voice is ready": "ድምፅዎ ዝግጁ ነው",
        "%@ free credits are on your account.": "%@ ነፃ ክሬዲት በመለያዎ ላይ ተጨምሯል።",
        "The recording was a little rough. If the voice does not sound right, record again in a quieter place.":
            "ቀረጻው ትንሽ ሸካራ ነበር። ድምፁ ትክክል ካልመሰለ ጸጥ ባለ ቦታ እንደገና ይቅዱ።",
        "Your video was received. You will get an email when it is approved.": "ቪዲዮዎ ደርሶናል። ሲጸድቅ ኢሜይል ይደርስዎታል።",
        "The script could not be loaded.": "ጽሑፉ ሊጫን አልቻለም።",

        // Account
        "A one-minute voiceover is about 2.5 credits. ": "የአንድ ደቂቃ ትረካ ወደ 2.5 ክሬዲት ነው። ",
        "Buy more on the Account page.": "ተጨማሪ በመለያ ገጹ ይግዙ።",
        "Script rules": "የስክሪፕት ደንቦች", "Sign out": "ውጣ", "Delete my account": "መለያዬን አጥፋ",
        "Delete my account for good": "መለያዬን ለዘለቄታው አጥፋ",
        "This removes your account, your voices, your scripts and any credits left. It cannot be undone.":
            "ይህ መለያዎን፣ ድምፆችዎን፣ ስክሪፕቶችዎን እና የቀረውን ክሬዲት ያጠፋል። ሊመለስ አይችልም።",
        "Type your email to confirm: %@": "ለማረጋገጥ ኢሜይልዎን ይጻፉ፦ %@",
        "Kinbir follows these every time it writes or changes a script for you.": "ቅንብር ስክሪፕት በጻፈልዎ ወይም በቀየረልዎ ቁጥር እነዚህን ይከተላል።",
        "Save rules": "ደንቦቹን አስቀምጥ", "Reset to the Kinbir template": "ወደ ቅንብር ናሙና መልስ",
        "Leave it empty to use no rules. %@ of %@ characters.": "ያለ ደንብ ለመጠቀም ባዶ ይተዉት። %@ ከ %@ ፊደላት።",
        "Version %@, build %@": "ስሪት %@፣ ግንባታ %@", "Interface language": "የመተግበሪያ ቋንቋ",

        // Video
        "Shape": "ቅርጽ", "Footage": "ምስል",
        "Vertical 9:16": "ቁመታዊ 9:16", "Horizontal 16:9": "አግድም 16:9",
        "Stock": "ክምችት", "Stock + mine": "ክምችት + የእኔ", "Only mine": "የእኔ ብቻ",
        "Kinbir finds free stock clips for every shot.": "ቅንብር ለእያንዳንዱ ትዕይንት ነፃ ክሊፖችን ያገኛል።",
        "Your clips go where they fit. Stock clips fill the rest.": "የእርስዎ ክሊፖች በሚስማሙበት ቦታ ይገባሉ። ቀሪውን የክምችት ክሊፖች ይሞላሉ።",
        "Only clips you add are used.": "እርስዎ የጨመሯቸው ክሊፖች ብቻ ጥቅም ላይ ይውላሉ።",
        "No clips added yet": "ገና ክሊፕ አልተጨመረም", "%@ of your clips added": "%@ ክሊፖችዎ ተጨምረዋል",
        "Add my clips": "ክሊፖቼን ጨምር",
        "Only add footage you filmed or have permission to use.": "ራስዎ የቀረጹትን ወይም ለመጠቀም ፈቃድ ያለዎትን ምስል ብቻ ይጨምሩ።",
        "Plan the shots": "ትዕይንቶቹን አቅድ",
        "Planning costs about %@ credits. Finding footage and changing shots is free. The finished video is 2 credits.":
            "ማቀድ ወደ %@ ክሬዲት ያስከፍላል። ምስል መፈለግ እና ትዕይንት መቀየር ነፃ ነው። ያለቀው ቪዲዮ 2 ክሬዲት ነው።",
        "Planning your video": "ቪዲዮዎ እየታቀደ ነው",
        "Deciding what each shot should show.": "እያንዳንዱ ትዕይንት ምን ማሳየት እንዳለበት እየተወሰነ ነው።",
        "This can take a few minutes. You can leave this screen and come back.": "ጥቂት ደቂቃዎች ሊወስድ ይችላል። ከዚህ ገጽ ወጥተው መመለስ ይችላሉ።",
        "Your shots": "ትዕይንቶችዎ",
        "Stock footage is not available right now": "የክምችት ምስል አሁን አይገኝም",
        "The free stock library has reached its limit. Upload your own footage for the empty shots, or try stock again in a few minutes.":
            "ነፃው የክምችት ቤተ-መጻሕፍት ገደቡ ላይ ደርሷል። ለባዶ ትዕይንቶች የራስዎን ምስል ይጫኑ፣ ወይም ከጥቂት ደቂቃ በኋላ እንደገና ይሞክሩ።",
        "Try stock again": "ክምችቱን እንደገና ሞክር",
        "%@ shots need footage": "%@ ትዕይንቶች ምስል ያስፈልጋቸዋል",
        "Tap a shot to search with other words, or add your own clips.": "በሌላ ቃላት ለመፈለግ ትዕይንቱን ይንኩ፣ ወይም የራስዎን ክሊፖች ይጨምሩ።",
        "Finding footage for your shots.": "ለትዕይንቶችዎ ምስል እየተፈለገ ነው።", "Placing your clips.": "ክሊፖችዎ እየተቀመጡ ነው።",
        "Music": "ሙዚቃ", "Stop preview": "ቅድመ-እይታውን አቁም", "Captions on the video": "በቪዲዮው ላይ የግርጌ ጽሑፍ",
        "Make video · 2 credits": "ቪዲዮ ሥራ · 2 ክሬዲት",
        "Every shot needs footage before the video can be made.": "ቪዲዮው ከመሠራቱ በፊት እያንዳንዱ ትዕይንት ምስል ያስፈልገዋል።",
        "Shot %@": "ትዕይንት %@", "Needs footage": "ምስል ያስፈልገዋል",
        "Tap a clip to use it": "ለመጠቀም ክሊፑን ይንኩ", "No clip found for this shot yet.": "ለዚህ ትዕይንት ገና ክሊፕ አልተገኘም።",
        "Search with other words": "በሌላ ቃላት ፈልግ", "Search stock footage": "የክምችት ምስል ፈልግ",
        "Use one of your clips": "ከክሊፖችዎ አንዱን ይጠቀሙ",
        "Stock footage is not available right now. Use one of your own clips, or try again in a few minutes.":
            "የክምችት ምስል አሁን አይገኝም። ከራስዎ ክሊፖች አንዱን ይጠቀሙ፣ ወይም ከጥቂት ደቂቃ በኋላ እንደገና ይሞክሩ።",
        "Nothing found. Try simpler words, like one object or place.": "ምንም አልተገኘም። እንደ አንድ ዕቃ ወይም ቦታ ያሉ ቀለል ያሉ ቃላት ይሞክሩ።",
        "No new clips for those words. Try different words.": "ለእነዚያ ቃላት አዲስ ክሊፕ የለም። ሌላ ቃላት ይሞክሩ።",
        "Making your video": "ቪዲዮዎ እየተሠራ ነው", "Clip %@ of %@": "ክሊፕ %@ ከ %@",
        "This takes a few minutes. You can leave this screen. The video will be in your Library when it is ready.":
            "ጥቂት ደቂቃዎች ይወስዳል። ከዚህ ገጽ መውጣት ይችላሉ። ቪዲዮው ሲዘጋጅ በማህደርዎ ውስጥ ያገኙታል።",
        "Stop and get the credits back": "አቁምና ክሬዲቱን መልስ", "Stopped": "ቆሟል",
        "The video was stopped. %@ credits were returned.": "ቪዲዮው ቆሟል። %@ ክሬዲት ተመልሷል።",
        "Your video": "የእርስዎ ቪዲዮ",
        "The preview is not available here. Save the video to watch it.": "ቅድመ-እይታው እዚህ አይገኝም። ለማየት ቪዲዮውን ያስቀምጡ።",
        "Save or share video": "ቪዲዮውን አስቀምጥ ወይም አጋራ", "Downloading": "በማውረድ ላይ",

        // Presenter
        "Presenter": "አቅራቢ", "Presenter: ": "አቅራቢ፦ ",
        "Your photo, speaking your voiceover.": "ፎቶዎ ትረካዎን ሲናገር።",
        "Your photo is saved": "ፎቶዎ ተቀምጧል", "Use the presenter in this video": "በዚህ ቪዲዮ አቅራቢውን ተጠቀም",
        "For the whole video": "ለሙሉው ቪዲዮ", "At the start": "መጀመሪያ ላይ", "At the end": "መጨረሻ ላይ",
        "Seconds each time": "በእያንዳንዱ ጊዜ ሰከንዶች", "In the video": "በቪዲዮው ውስጥ", "Separate file": "የተለየ ፋይል",
        "The presenter adds about %@ credits. Any part that cannot be made is refunded.": "አቅራቢው ወደ %@ ክሬዲት ይጨምራል። ሊሠራ ያልቻለ ክፍል ክሬዲቱ ይመለሳል።",
        "Choose where the presenter appears.": "አቅራቢው የሚታይበትን ይምረጡ።",
        "This is a photo of me": "ይህ የእኔ ፎቶ ነው", "Saving your photo": "ፎቶዎ እየተቀመጠ ነው",
        "Choose a photo": "ፎቶ ምረጥ",
        "A clear photo of your face, looking at the camera. Only your own photo.": "ወደ ካሜራ የሚመለከት ግልጽ የፊትዎ ፎቶ። የራስዎ ፎቶ ብቻ።",
        "Save the presenter clip": "የአቅራቢውን ክሊፕ አስቀምጥ",
        "That photo could not be read. Try another.": "ያ ፎቶ ሊነበብ አልቻለም። ሌላ ይሞክሩ።",

        // Build 5
        "Finishing": "በማጠናቀቅ ላይ", "usually 1 to 3 minutes": "ብዙ ጊዜ ከ1 እስከ 3 ደቂቃ",
        "usually 2 to 5 minutes": "ብዙ ጊዜ ከ2 እስከ 5 ደቂቃ",
        "Putting the clips together": "ክሊፖቹ እየተገጣጠሙ ነው",
        "Planning the shots": "ትዕይንቶቹ እየታቀዱ ነው", "Finding footage": "ምስል እየተፈለገ ነው",
        "Ready for you to review": "ለእርስዎ ግምገማ ዝግጁ",
        "Make the video for me": "ቪዲዮውን ሥራልኝ",
        "Kinbir plans the shots, finds the footage and makes the video in one go. You can still change any shot afterwards and make it again.":
            "ቅንብር ትዕይንቶቹን አቅዶ፣ ምስሉን ፈልጎ ቪዲዮውን በአንድ ጊዜ ይሠራል። ከዚያ በኋላም ማንኛውንም ትዕይንት ቀይረው እንደገና መሥራት ይችላሉ።",
        "Choose this to check every shot yourself before the video is made.": "ቪዲዮው ከመሠራቱ በፊት እያንዳንዱን ትዕይንት ራስዎ ለማየት ይህን ይምረጡ።",
        "Write the script from this idea": "ከዚህ ሐሳብ ስክሪፕት ጻፍ",
        "You have %@ credits left, enough for about one short voiceover.": "%@ ክሬዲት ቀርቶዎታል፤ ለአንድ አጭር ትረካ ያህል ይበቃል።",
        "Need an idea? Tap one, then change it to yours.": "ሐሳብ ይፈልጋሉ? አንዱን ይንኩ፣ ከዚያ ወደ ራስዎ ይቀይሩት።",
        "News": "ዜና", "History": "ታሪክ", "Motivation": "ማነቃቂያ", "Business": "ንግድ", "How to": "እንዴት",
        "Shorter": "አሳጥር", "Longer": "አስረዝም", "More dramatic": "የበለጠ አጓጊ", "Simpler": "ቀለል አድርግ",
        "Stronger opening": "ጠንካራ መክፈቻ",
        "The words stay on screen while you record.": "በሚቀዱበት ጊዜ ቃላቱ በስክሪኑ ላይ ይቆያሉ።",
        "%@ h left": "%@ ሰዓት ቀርቷል",
        "Slow": "ዘገምተኛ", "Normal": "መደበኛ", "Fast": "ፈጣን", "Punchy": "ጠንከር ያለ", "Strong": "ጠንካራ",
        "Starter": "ጀማሪ", "Pro": "ፕሮ", "Studio": "ስቱዲዮ",
        "Delivery": "አቀራረብ", "Seconds": "ሰከንዶች",

        // Build 6: the website's script page and fixing flow
        "About %@": "%@ ገደማ", "Amharic text": "የአማርኛ ጽሑፍ", "Apply": "ተግብር", "Article link": "የጽሑፍ ሊንክ",
        "Ask Kinbir": "ቅንብርን ጠይቅ", "Ask for a change": "ለውጥ ይጠይቁ", "Change the words": "ቃላቱን ቀይር",
        "Close to the original": "ለዋናው የቀረበ", "Composing your voiceover": "ድምፅዎ እየተቀናበረ ነው",
        "Done. Your new take is in the player above. Press play to hear it.": "ተጠናቋል። አዲሱ ቅጂ ከላይ ባለው ማጫወቻ ውስጥ ነው። ለመስማት አጫውትን ይጫኑ።",
        "Each change costs credits. Undo brings the old script back.": "እያንዳንዱ ለውጥ ክሬዲት ያስከፍላል። መልስ የቀድሞውን ስክሪፕት ይመልሳል።",
        "Edit this sentence": "ይህን ዓረፍተ ነገር አርም",
        "Finish step 1 first. The button wakes up when there is a script.": "መጀመሪያ ደረጃ 1ን ይጨርሱ። ስክሪፕት ሲኖር ቁልፉ ይሠራል።",
        "Fix how a word sounds": "የቃል አነባበብ አስተካክል",
        "For example: the history of Ethiopian coffee": "ለምሳሌ፦ የኢትዮጵያ ቡና ታሪክ",
        "Generate my %@ changes · 1.5 credits": "%@ ለውጦቼን ሥራ · 1.5 ክሬዲት",
        "How should this word sound?": "ይህ ቃል እንዴት መነበብ አለበት?",
        "It appears %@ times. Fixing it here changes all of them.": "%@ ጊዜ ይገኛል። እዚህ ማስተካከል ሁሉንም ይቀይራል።",
        "Keeps the original order and wording as much as possible.": "የዋናውን ቅደም ተከተል እና አገላለጽ በተቻለ መጠን ይጠብቃል።",
        "Make the voiceover": "ትረካውን ሥራ", "Not right? Type it your way": "ትክክል አይደለም? በራስዎ መንገድ ይጻፉ",
        "Nothing is recorded yet. Your changes wait in a list, and you generate them all together for 1.5 credits.":
            "ገና ምንም አልተቀዳም። ለውጦችዎ በዝርዝር ይጠብቃሉ፤ ሁሉንም በአንድ ላይ በ1.5 ክሬዲት ያሠራሉ።",
        "Option %@": "አማራጭ %@",
        "Paste English text. Kinbir writes it as a natural Amharic script.": "የእንግሊዝኛ ጽሑፍ ይለጥፉ። ቅንብር ተፈጥሯዊ የአማርኛ ስክሪፕት አድርጎ ይጽፈዋል።",
        "Paste a link to an article. Kinbir reads it and brings the text here.": "የጽሑፍ ሊንክ ይለጥፉ። ቅንብር አንብቦ ጽሑፉን እዚህ ያመጣል።",
        "Paste any text. Kinbir rewrites it as a video script.": "ማንኛውንም ጽሑፍ ይለጥፉ። ቅንብር የቪዲዮ ስክሪፕት አድርጎ ይጽፈዋል።",
        "Paste the text here.": "ጽሑፉን እዚህ ይለጥፉ።",
        "Pick as many changes as you like. They are all recorded together for 1.5 credits.": "የፈለጉትን ያህል ለውጦች ይምረጡ። ሁሉም በአንድ ላይ በ1.5 ክሬዲት ይቀዳሉ።",
        "Preparing options": "አማራጮች እየተዘጋጁ ነው",
        "Preparing the audio. %@ seconds so far.": "ድምፁ እየተዘጋጀ ነው። እስካሁን %@ ሰከንድ።",
        "Put the old words back": "የቀድሞ ቃላትን መልስ",
        "Recommended. Rebuilt to hold attention, at the length you choose.": "የሚመከር። ትኩረት እንዲይዝ በመረጡት ርዝመት እንደገና ይዋቀራል።",
        "Record this sentence again": "ይህን ዓረፍተ ነገር እንደገና ቅዳ",
        "Recording the changed sentences again.": "የተቀየሩት ዓረፍተ ነገሮች እንደገና እየተቀዱ ነው።",
        "Save this edit": "ይህን እርማት አስቀምጥ",
        "Say what the video is about. Kinbir writes the whole script.": "ቪዲዮው ስለ ምን እንደሆነ ይንገሩ። ቅንብር ሙሉ ስክሪፕቱን ይጽፋል።",
        "Sentence %@ again": "ዓረፍተ ነገር %@ እንደገና", "Sentence %@ edited": "ዓረፍተ ነገር %@ ታርሟል",
        "Something went wrong on our side. Your credits were returned.": "በእኛ በኩል ችግር ተፈጥሯል። ክሬዲትዎ ተመልሷል።",
        "Stopped. Your credits were returned.": "ቆሟል። ክሬዲትዎ ተመልሷል።",
        "Style": "አጻጻፍ", "Text to rewrite": "እንደገና የሚጻፍ ጽሑፍ",
        "That is the most changes for one go. Generate these first.": "በአንድ ጊዜ የሚቻለው ከፍተኛ ለውጥ ይህ ነው። መጀመሪያ እነዚህን ያሠሩ።",
        "The changes could not be started. Try again.": "ለውጦቹ ሊጀመሩ አልቻሉም። እንደገና ይሞክሩ።",
        "The changes did not finish. Your credits were returned.": "ለውጦቹ አልተጠናቀቁም። ክሬዲትዎ ተመልሷል።",
        "The first voiceover of a session wakes the voice engine and takes about 2 extra minutes. After that it is much faster. You can leave this screen: it keeps going, and the result waits in your Library for 48 hours.":
            "የመጀመሪያው ትረካ የድምፅ ሞተሩን ስለሚያስነሳ ወደ 2 ደቂቃ ተጨማሪ ይወስዳል። ከዚያ በኋላ በጣም ፈጣን ነው። ከዚህ ገጽ መውጣት ይችላሉ፤ ሥራው ይቀጥላል፣ ውጤቱም ለ48 ሰዓት በማህደርዎ ይጠብቃል።",
        "These clips are an example reading and may not be in your own voice. Listening is free when the reading has been made before. Your changes are recorded in your voice when you generate them: 1.5 credits for all of them together.":
            "እነዚህ ክሊፖች የንባብ ምሳሌ ናቸው፤ በራስዎ ድምፅ ላይሆኑ ይችላሉ። ንባቡ ቀድሞ የተሠራ ከሆነ ማዳመጥ ነፃ ነው። ለውጦችዎ ሲያሠሯቸው በራስዎ ድምፅ ይቀዳሉ፤ ሁሉም በአንድ ላይ 1.5 ክሬዲት።",
        "This is taking longer than usual. It is still working. You can leave this screen and find it later in your Library.":
            "ከተለመደው በላይ እየቆየ ነው። አሁንም እየሠራ ነው። ከዚህ ገጽ ወጥተው በኋላ በማህደርዎ ማግኘት ይችላሉ።",
        "This makes the audio, about %@. Next you can turn it into a video.": "ይህ ድምፁን ይሠራል፣ ወደ %@። ቀጥሎ ወደ ቪዲዮ መቀየር ይችላሉ።",
        "This page is mine, or I have permission to use it": "ይህ ገጽ የእኔ ነው፣ ወይም ለመጠቀም ፈቃድ አለኝ",
        "This word is being voiced for the very first time, so it can take a minute or two. Everyone after you gets it instantly.":
            "ይህ ቃል ለመጀመሪያ ጊዜ እየተነበበ ስለሆነ አንድ ወይም ሁለት ደቂቃ ሊወስድ ይችላል። ከእርስዎ በኋላ የሚመጡ ሁሉ ወዲያውኑ ያገኙታል።",
        "Type how it should sound": "እንዴት መነበብ እንዳለበት ይጻፉ",
        "Use this when the words are right but the reading came out too slow, too fast or flat.": "ቃላቱ ትክክል ሆነው ንባቡ በጣም ቀርፋፋ፣ በጣም ፈጣን ወይም ደብዛዛ ሲሆን ይህን ይጠቀሙ።",
        "Use what I typed": "የጻፍኩትን ተጠቀም", "Video length": "የቪዲዮ ርዝመት", "Video style": "የቪዲዮ አጻጻፍ",
        "Voicing part %@ of %@": "ክፍል %@ ከ %@ እየተነበበ ነው", "Voicing your narration": "ትረካዎ እየተነበበ ነው",
        "Waiting in line": "በወረፋ እየጠበቀ ነው", "Waiting to be generated": "ለመሠራት እየጠበቁ ያሉ",
        "Write or paste your Amharic script here.": "የአማርኛ ስክሪፕትዎን እዚህ ይጻፉ ወይም ይለጥፉ።",
        "Write or paste your script here.": "ስክሪፕትዎን እዚህ ይጻፉ ወይም ይለጥፉ።",
        "Write the script": "ስክሪፕቱን ጻፍ",
        "Your Amharic script. Type in it to edit.": "የአማርኛ ስክሪፕትዎ። ለማረም በውስጡ ይጻፉ።",
        "Your English script. Type in it to edit.": "የእንግሊዝኛ ስክሪፕትዎ። ለማረም በውስጡ ይጻፉ።",
        "Your recent scripts": "የቅርብ ጊዜ ስክሪፕቶችዎ", "Your script": "የእርስዎ ስክሪፕት",
        "Your script · tap a sentence": "ስክሪፕትዎ · ዓረፍተ ነገር ይንኩ", "Your script · tap a word": "ስክሪፕትዎ · ቃል ይንኩ",
        "Your voice": "የእርስዎ ድምፅ",
        "Speak your script": "ስክሪፕትዎን ይናገሩ",

        // Build 7: one box, one button
        "%@ plan": "%@ ዕቅድ", "A word sounds wrong": "አንድ ቃል በትክክል አልተነበበም",
        "Add yourself as presenter": "ራስዎን እንደ አቅራቢ ይጨምሩ",
        "Apply %@ changes · 1.5 credits": "%@ ለውጦችን ተግብር · 1.5 ክሬዲት",
        "Back": "ተመለስ", "Back to my script": "ወደ ስክሪፕቴ ተመለስ", "Back to my voiceover": "ወደ ትረካዬ ተመለስ",
        "Back to the shots": "ወደ ትዕይንቶቹ ተመለስ", "Captions": "የግርጌ ጽሑፍ",
        "Change shots and make it again": "ትዕይንቶችን ቀይረህ እንደገና አዘጋጅ",
        "Done. Listen to the new take.": "ተጠናቋል። አዲሱን ቅጂ ያድምጡ።",
        "Each change costs about 1 credit. Undo brings the old script back.": "እያንዳንዱ ለውጥ ወደ 1 ክሬዲት ያስከፍላል። መልስ የቀድሞውን ስክሪፕት ይመልሳል።",
        "First, record your voice": "መጀመሪያ ድምፅዎን ይቅዱ",
        "Fix a word or change a sentence.": "ቃል ያስተካክሉ ወይም ዓረፍተ ነገር ይቀይሩ።",
        "Fix the voiceover": "ትረካውን አስተካክል", "For example: coffee cup": "ለምሳሌ፦ coffee cup",
        "From English text": "ከእንግሊዝኛ ጽሑፍ", "From a link": "ከሊንክ", "From an idea": "ከሐሳብ",
        "From any text": "ከማንኛውም ጽሑፍ", "Improve the script": "ስክሪፕቱን አሻሽል",
        "Improve the script, voiceover language, reading speed": "ስክሪፕት ማሻሻል፣ የትረካ ቋንቋ፣ የንባብ ፍጥነት",
        "Keep it close to the original": "ለዋናው የቀረበ ይሁን",
        "Kinbir writes the script. You can change it afterwards.": "ቅንብር ስክሪፕቱን ይጽፋል። ከዚያ በኋላ መቀየር ይችላሉ።",
        "Make my video": "ቪዲዮዬን አዘጋጅ", "More options": "ተጨማሪ አማራጮች", "My clip": "የእኔ ክሊፕ",
        "Off": "ጠፍቷል", "On": "በርቷል", "Part %@ again": "ክፍል %@ እንደገና", "Part %@ edited": "ክፍል %@ ታርሟል",
        "Paste English and get a natural Amharic script.": "እንግሊዝኛ ለጥፈው ተፈጥሯዊ የአማርኛ ስክሪፕት ያግኙ።",
        "Paste a link to an article.": "የጽሑፍ ሊንክ ይለጥፉ።",
        "Paste text and get a video script.": "ጽሑፍ ለጥፈው የቪዲዮ ስክሪፕት ያግኙ።",
        "Paste the English text": "የእንግሊዝኛውን ጽሑፍ ይለጥፉ", "Paste the link": "ሊንኩን ይለጥፉ", "Paste the text": "ጽሑፉን ይለጥፉ",
        "Pick as many changes as you like. They cost 1.5 credits together.": "የፈለጉትን ያህል ለውጦች ይምረጡ። በአንድ ላይ 1.5 ክሬዲት ያስከፍላሉ።",
        "Read a few lines on camera, about 30 seconds. After that, everything is in your voice.": "ጥቂት መስመሮችን በካሜራ ፊት ያንብቡ፣ 30 ሰከንድ ያህል። ከዚያ በኋላ ሁሉም ነገር በእርስዎ ድምፅ ይሆናል።",
        "Recent scripts": "የቅርብ ጊዜ ስክሪፕቶች", "Record my voice": "ድምፄን ቅዳ",
        "Recording your changes": "ለውጦችዎ እየተቀዱ ነው", "Review the shots first": "መጀመሪያ ትዕይንቶቹን ልይ",
        "Say what the video is about in one line.": "ቪዲዮው ስለ ምን እንደሆነ በአንድ መስመር ይንገሩ።",
        "Some shots have no footage yet, so the video was not made. Add footage to them, then tap Make video.":
            "አንዳንድ ትዕይንቶች ገና ምስል ስለሌላቸው ቪዲዮው አልተዘጋጀም። ምስል ይጨምሩላቸው፣ ከዚያ ቪዲዮ አዘጋጅን ይንኩ።",
        "Something sound wrong?": "የሆነ ነገር በትክክል አልተነበበም?",
        "Standing instructions for every script Kinbir writes.": "ቅንብር ለሚጽፈው እያንዳንዱ ስክሪፕት ቋሚ መመሪያዎች።",
        "Tap the part you want to change or hear again.": "መቀየር ወይም እንደገና መስማት የሚፈልጉትን ክፍል ይንኩ።",
        "Tap the word that sounds wrong.": "በትክክል ያልተነበበውን ቃል ይንኩ።",
        "That is the most changes for one go. Apply these first.": "በአንድ ጊዜ የሚቻለው ከፍተኛ ለውጥ ይህ ነው። መጀመሪያ እነዚህን ይተግብሩ።",
        "The first one of the day takes about 2 minutes longer. You can leave this screen. It will be in your Library.":
            "የቀኑ የመጀመሪያው ወደ 2 ደቂቃ ተጨማሪ ይወስዳል። ከዚህ ገጽ መውጣት ይችላሉ። በማህደርዎ ውስጥ ያገኙታል።",
        "The language the voice reads in. Your script must be in the same language.": "ድምፁ የሚያነብበት ቋንቋ። ስክሪፕትዎ በዚሁ ቋንቋ መሆን አለበት።",
        "The video could not be made. Your credits were returned.": "ቪዲዮው ሊዘጋጅ አልቻለም። ክሬዲትዎ ተመልሷል።",
        "The video was stopped and the credits were returned.": "ቪዲዮው ቆሟል፤ ክሬዲቱም ተመልሷል።",
        "This is taking longer than usual. Check your voiceover again in a few minutes.": "ከተለመደው በላይ እየቆየ ነው። ከጥቂት ደቂቃ በኋላ ትረካዎን እንደገና ይመልከቱ።",
        "This script is in Amharic. Switch the voiceover language to Amharic in More options.":
            "ይህ ስክሪፕት በአማርኛ ነው። በተጨማሪ አማራጮች ውስጥ የትረካ ቋንቋውን ወደ አማርኛ ይቀይሩ።",
        "This script is in English. Tap Write it for me to turn it into Amharic, or switch the voiceover language in More options.":
            "ይህ ስክሪፕት በእንግሊዝኛ ነው። ወደ አማርኛ ለመቀየር ጻፍልኝን ይንኩ፣ ወይም በተጨማሪ አማራጮች ውስጥ የትረካ ቋንቋውን ይቀይሩ።",
        "Track": "ሙዚቃ", "Uploading clip %@ of %@": "ክሊፕ %@ ከ %@ እየተጫነ ነው",
        "Video": "ቪዲዮ", "Voice": "ድምፅ", "Voice %@": "ድምፅ %@", "Voiceover": "ትረካ",
        "Voiceover language": "የትረካ ቋንቋ", "What is the video about?": "ቪዲዮው ስለ ምንድን ነው?",
        "What will you say?": "ምን ማለት ይፈልጋሉ?", "Write it for me": "ጻፍልኝ",
        "Writing your script": "ስክሪፕትዎ እየተጻፈ ነው", "Your changes": "ለውጦችዎ",
        "Tips": "ምክሮች",
        // Build 8
        "Your credits": "ክሬዲቶችዎ", "What things cost": "ዋጋዎች",
        "A one-minute voiceover": "የአንድ ደቂቃ ትረካ",
        "Kinbir writes or changes a script": "ቅንብር ስክሪፕት ሲጽፍ ወይም ሲቀይር",
        "Fixing words, all together": "ቃላትን ማስተካከል፣ ሁሉም በአንድ ላይ",
        "A finished video": "የተጠናቀቀ ቪዲዮ",
        "Free: listening, finding footage, changing shots, and speaking your script. You always see the price on the button before you spend. If something fails, the credits come back.":
            "ነፃ፦ ማዳመጥ፣ ቪዲዮ መፈለግ፣ ትዕይንት መቀየር እና ስክሪፕትዎን በድምፅ መናገር። ከመክፈልዎ በፊት ዋጋውን ሁልጊዜ በቁልፉ ላይ ያያሉ። የሆነ ነገር ካልሰራ ክሬዲቶቹ ይመለሳሉ።",
    ]
}

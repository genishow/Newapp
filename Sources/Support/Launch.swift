import Foundation

/// Launch arguments. Only the end-to-end UI tests pass these.
enum Launch {
    private static let args = ProcessInfo.processInfo.arguments

    static let isMock = args.contains("-uiTestMock")
    static let mockNoVoice = args.contains("-mockNoVoice")
    static let mockNoCredits = args.contains("-mockNoCredits")
    static let mockStockLimit = args.contains("-mockStockLimit")
    /// The UI tests normally start past the first-launch language question.
    static let mockAskLanguage = args.contains("-mockAskLanguage")

    /// How often the app asks the server about a running job.
    static var jobPollSeconds: Double { isMock ? 0.3 : 3.0 }
    static var demoPollSeconds: Double { isMock ? 0.3 : 2.0 }
}

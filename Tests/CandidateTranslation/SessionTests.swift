import Foundation

@main
struct SessionTests {
    static func main() {
        var session = RoTypeCandidateTranslationSession()
        let first = RoTypeCandidateSnapshot(rawInput: "lixian", source: "李先", identity: "0:6:0", scope: "whole")
        let second = RoTypeCandidateSnapshot(rawInput: "lixian", source: "离线", identity: "0:6:1", scope: "whole")
        let old = session.observe(first)!
        let current = session.observe(second)!
        precondition(!session.receive("Mr. Li", for: old), "old selection must not overwrite new selection")
        precondition(session.commit == nil, "loading must not submit stale translation")
        precondition(session.receive("Offline", for: current))
        precondition(session.commit?.text == "Offline")
        precondition(session.commit?.snapshot == second, "Tab can directly submit the current result")
        precondition(session.observe(second) == nil, "reading the result must not request a reverse translation")
        session.invalidate()
        precondition(session.commit == nil)
        precondition(!session.receive("Late result", for: current))
        let failed = session.observe(second)!
        precondition(session.fail("temporary failure", for: failed))
        precondition(session.observe(second) == nil, "redraw must not automatically retry")
        guard let retried = session.retry() else { fatalError("the user can retry the same failed candidate") }
        precondition(retried.generation > failed.generation)
        precondition(session.retry() == nil, "only one attempt may be in flight")
        precondition(session.commit == nil)
        precondition(!session.receive("Old attempt", for: failed))
        precondition(session.receive("Offline", for: retried))
        precondition(!session.fail("late failure", for: retried), "a second terminal reply must be ignored")
        precondition(session.commit?.text == "Offline")
        precondition(session.retry() == nil, "a ready result should commit, not retry")
        session.invalidate()
        precondition(session.retry() == nil)
        let permanent = session.observe(second)!
        precondition(session.fail("prepare language pack", for: permanent, retryable: false))
        precondition(!session.canRetry && session.retry() == nil)
        precondition(!session.receive("late success", for: permanent))
        for failure in [CandidateTranslationFailure.languagePackMissing, .requiresMacOS26, .incompatibleVersion,
                        .invalidResponse, .unauthorized, .cancelled, .unsupportedLanguage] {
            let wireError = failure as NSError
            precondition(CandidateTranslationFailure.from(wireError) == failure)
            precondition(!failure.canRetry)
        }
        precondition(CandidateTranslationFailure.timedOut.canRetry)
        precondition(CandidateTranslationFailure.serviceUnavailable.canRetry)
        precondition(CandidateTranslationFailure.from(CancellationError()) == .cancelled)
        let greeting = RoTypeCandidateSnapshot(rawInput: "nihao", source: "你好", identity: "0:5:0", scope: "whole")
        let unsupported = session.observe(greeting)!
        precondition(session.fail(.requiresMacOS26, for: unsupported))
        precondition(session.commit?.text == "hello", "unsupported system can submit a matching static translation")
        precondition(session.commit?.snapshot == greeting)
        precondition(!session.isLoading && !session.canRetry)
        let accented = RoTypeCandidateSnapshot(rawInput: "cafe", source: "café", identity: "0:4:0", scope: "whole")
        let candidateRequest = accented.translationRequest!
        precondition(candidateRequest.direction == .englishToChinese)
        precondition(candidateRequest.accepts(source: "café", direction: "en-zh"))
        precondition(!candidateRequest.accepts(source: "café", direction: "zh-en"), "wrong direction cannot be committed")
        precondition(!candidateRequest.accepts(source: "cafe", direction: "en-zh"), "input code cannot replace source")
        precondition(second.translationRequest?.direction == .chineseToEnglish)
        verifyStaticFallback()
        print("candidate selection, direct submission, source validation, static fallback, retry and cancellation passed")
    }

    static func verifyStaticFallback() {
        let known = RoTypeCandidateSnapshot(rawInput: "nihao", source: "你好", identity: "0:5:0", scope: "whole")
        for failure in [CandidateTranslationFailure.requiresMacOS26, .languagePackMissing, .serviceUnavailable, .timedOut] {
            var session = RoTypeCandidateTranslationSession()
            let request = session.observe(known)!
            precondition(session.fail(failure, for: request))
            precondition(session.commit?.text == "hello")
            precondition(!session.receive("Late dynamic result", for: request))
            session.invalidate()
            precondition(session.commit == nil)
        }
        for failure in [CandidateTranslationFailure.cancelled, .unauthorized, .incompatibleVersion,
                        .invalidResponse, .invalidRequest, .unsupportedLanguage] {
            var session = RoTypeCandidateTranslationSession()
            let request = session.observe(known)!
            precondition(session.fail(failure, for: request))
            precondition(session.commit == nil, "static fallback must not mask security/protocol failures")
        }
        var session = RoTypeCandidateTranslationSession()
        let old = session.observe(known)!
        let unknown = RoTypeCandidateSnapshot(rawInput: "nihao", source: "你号", identity: "0:5:1", scope: "whole")
        let current = session.observe(unknown)!
        precondition(!session.fail(.timedOut, for: old), "an old failure cannot restore the previous word's fallback")
        precondition(session.fail(.timedOut, for: current))
        precondition(session.commit == nil && session.canRetry, "same pinyin must not imply same translation")

        let partial = RoTypeCandidateSnapshot(rawInput: "nihaoshijie", source: "你好", identity: "0:5:0", scope: "segment")
        let partialRequest = session.observe(partial)!
        precondition(session.fail(.languagePackMissing, for: partialRequest))
        precondition(session.commit?.text == "hello" && session.commit?.snapshot == partial)
        let whole = RoTypeCandidateSnapshot(rawInput: "nihaoshijie", source: "你好世界", identity: "0:11:0", scope: "whole")
        let wholeRequest = session.observe(whole)!
        precondition(session.fail(.requiresMacOS26, for: wholeRequest))
        precondition(session.commit == nil && !session.canRetry, "do not stitch words into an invented sentence translation")
        precondition(session.failure?.contains("无匹配的静态译文") == true)

        let pairs = [("你好", "hello"), ("谢谢", "thanks"), ("早上好", "good morning"),
                     ("晚安", "good night"), ("再见", "goodbye"), ("世界", "world"),
                     ("输入法", "input method"), ("中文", "Chinese"), ("英文", "English"), ("测试", "test")]
        for (chinese, english) in pairs {
            for (source, expected) in [(chinese, english), (english.uppercased(), chinese)] {
                let snapshot = RoTypeCandidateSnapshot(rawInput: "x", source: source, identity: "0:1:0", scope: "whole")
                let request = session.observe(snapshot)!
                precondition(session.fail(.requiresMacOS26, for: request))
                precondition(session.commit?.text == expected)
            }
        }
        let flypy = RoTypeCandidateSnapshot(rawInput: "nihc", source: "你好", identity: "0:4:0", scope: "whole")
        let flypyRequest = session.observe(flypy)!
        precondition(session.fail(.requiresMacOS26, for: flypyRequest))
        precondition(session.commit?.text == "hello", "fallback is independent of the input scheme")
    }
}

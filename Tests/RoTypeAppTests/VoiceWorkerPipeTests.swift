import Foundation
import XCTest
@testable import RoTypeApp

final class VoiceWorkerPipeTests: XCTestCase {
    func testReadyReplyIsDeliveredWithoutWaitingFor64KBOrEOF() throws {
        let pipe = Pipe()
        let received = expectation(description: "short ready reply arrives while worker stays running")
        let finished = expectation(description: "reader exits")
        let message = Data("ROTYPE_VOICE:{\"event\":\"ready\"}\n".utf8)
        DispatchQueue.global().async {
            let data = VoiceWorkerClient.readOutput(pipe.fileHandleForReading)
            XCTAssertEqual(data, message)
            received.fulfill()
            finished.fulfill()
        }
        try pipe.fileHandleForWriting.write(contentsOf: message)
        let result = XCTWaiter.wait(for: [received], timeout: 0.3)
        try pipe.fileHandleForWriting.close() // Also releases a broken, fixed-length reader.
        XCTAssertEqual(result, .completed, "Worker ready reply must not wait for a full 64KB buffer")
        wait(for: [finished], timeout: 1)
    }
}

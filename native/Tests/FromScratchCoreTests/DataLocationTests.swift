import Foundation
import Testing
@testable import FromScratchCore

@Suite struct DataLocationTests {
    let home = URL(fileURLWithPath: "/Users/tester")

    @Test func releaseUsesDotFromscratch() {
        let url = DataLocation.directory(
            environment: ["FROMSCRATCH_DATA_DIR": "/tmp/x"], isDebug: false, home: home)
        #expect(url.path == "/Users/tester/.fromscratch")
    }

    @Test func debugUsesDevSubfolder() {
        let url = DataLocation.directory(environment: [:], isDebug: true, home: home)
        #expect(url.path == "/Users/tester/.fromscratch/dev")
    }

    @Test func debugHonoursOverride() {
        let url = DataLocation.directory(
            environment: ["FROMSCRATCH_DATA_DIR": "/tmp/x"], isDebug: true, home: home)
        #expect(url.path == "/tmp/x")
    }
}

import Foundation
import Testing
@testable import FromScratchCore

@Suite struct UpdateCheckTests {
    @Test func newerPatchIsReportedWithoutThePrefix() {
        #expect(UpdateCheck.newerVersion(latestTag: "v3.0.1", current: "3.0.0") == "3.0.1")
    }

    @Test func sameOrOlderIsNil() {
        #expect(UpdateCheck.newerVersion(latestTag: "v3.0.0", current: "3.0.0") == nil)
        #expect(UpdateCheck.newerVersion(latestTag: "v2.9.9", current: "3.0.0") == nil)
        #expect(UpdateCheck.newerVersion(latestTag: "v2.2.1", current: "3.0.0") == nil)
    }

    @Test func comparesNumericallyNotAsText() {
        #expect(UpdateCheck.newerVersion(latestTag: "v3.10.0", current: "3.9.0") == "3.10.0")
        #expect(UpdateCheck.newerVersion(latestTag: "v3.9.0", current: "3.10.0") == nil)
    }

    @Test func missingComponentsCountAsZero() {
        #expect(UpdateCheck.newerVersion(latestTag: "v3.1", current: "3.0.5") == "3.1")
        #expect(UpdateCheck.newerVersion(latestTag: "v3.0", current: "3.0.0") == nil)
    }

    @Test func tagWithoutPrefixAlsoWorks() {
        #expect(UpdateCheck.newerVersion(latestTag: "4.0.0", current: "3.0.0") == "4.0.0")
    }

    @Test(arguments: ["garbage", "", "v", "v3.1.0-beta", "v3.1.0-beta.2", "v3..1", "v3.x.0", "v3.0.0+build", "vv3.1.0"])
    func nonNumericOrPreReleaseTagsAreNil(_ tag: String) {
        #expect(UpdateCheck.newerVersion(latestTag: tag, current: "3.0.0") == nil)
    }

    @Test func nonNumericCurrentVersionIsNil() {
        #expect(UpdateCheck.newerVersion(latestTag: "v9.0.0", current: "3.0.0-dev") == nil)
    }

    // MARK: fetchLatestTag, with the network replaced by a URLProtocol

    @Test func fetchReadsTagNameAndSendsTheAcceptHeader() async {
        let (session, stub) = Self.session(status: 200, body: #"{"tag_name":"v3.2.0","name":"x"}"#)
        let tag = await UpdateCheck.fetchLatestTag(session: session)
        #expect(tag == "v3.2.0")
        #expect(stub.lastAccept == "application/vnd.github+json")
        #expect(stub.lastURL == UpdateCheck.releasesAPI)
    }

    @Test func fetchIsSilentOnFailures() async {
        for (status, body) in [(404, #"{"message":"Not Found"}"#), (403, "{}"), (200, "not json"),
                               (200, #"{"tag_name":""}"#), (200, #"{"other":1}"#), (200, #"{"tag_name":5}"#)] {
            let (session, _) = Self.session(status: status, body: body)
            #expect(await UpdateCheck.fetchLatestTag(session: session) == nil, "\(status) \(body)")
        }
    }

    @Test func fetchIsSilentWhenTheNetworkFails() async {
        let (session, _) = Self.session(status: 0, body: "", fail: true)
        #expect(await UpdateCheck.fetchLatestTag(session: session) == nil)
    }

    private static func session(status: Int, body: String, fail: Bool = false) -> (URLSession, Stub) {
        let stub = Stub(status: status, body: body, fail: fail)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Stub-Id": stub.id]
        Stub.all.withLock { $0[stub.id] = stub }
        return (URLSession(configuration: configuration), stub)
    }
}

/// One canned response, looked up by an id header so parallel tests do not share state.
private final class Stub: @unchecked Sendable {
    static let all = Lock<[String: Stub]>([:])
    let id = UUID().uuidString
    let status: Int
    let body: String
    let fail: Bool
    private let lock = NSLock()
    private var _accept: String?
    private var _url: URL?
    var lastAccept: String? { lock.withLock { _accept } }
    var lastURL: URL? { lock.withLock { _url } }

    init(status: Int, body: String, fail: Bool) {
        self.status = status
        self.body = body
        self.fail = fail
    }

    func record(_ request: URLRequest) {
        lock.withLock {
            _accept = request.value(forHTTPHeaderField: "Accept")
            _url = request.url
        }
    }
}

private struct Lock<Value: Sendable>: Sendable {
    private let storage: NSLock = NSLock()
    private let box: Box
    private final class Box: @unchecked Sendable { var value: Any; init(_ v: Any) { value = v } }
    init(_ value: Value) { box = Box(value) }
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        storage.lock()
        defer { storage.unlock() }
        var v = box.value as! Value
        let r = body(&v)
        box.value = v
        return r
    }
}

private final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Stub-Id") ?? ""
        guard let stub = Stub.all.withLock({ $0[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        stub.record(request)
        if stub.fail {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

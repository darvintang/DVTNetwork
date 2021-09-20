@testable import DVTNetwork

#if canImport(DVTObjectMapper)
    @testable import DVTObjectMapper
#endif

import XCTest

class SessionTest: Session {
    required init?(_ scheme: Scheme?, host: String?, baseUrl: String?) {
        super.init(scheme, host: host, baseUrl: baseUrl)
    }
}

class RequestTest: Request {
    required init(_ session: Session? = nil) {
        super.init(session)
    }
}

class ResultTest: ResultMappable {
    required init?(JSONString: String) {}
    required init?(JSON: [String: Any]) {}

    required init?(map: Map) { }
    func mapping(map: Map) { }
}

final class DVTNetworkTests: XCTestCase {
    func testExample() throws {
        if let session = Session("https://httpbin.org") {
            Session.setDefault(session)
        }
        Session.send(path: "post", completed: { value, error, isCache in
            print(value as Any, error as Any, isCache as Any)
        })
    }
}

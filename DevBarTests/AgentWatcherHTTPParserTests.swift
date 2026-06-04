import Foundation
import Testing
@testable import DevBar

struct AgentWatcherHTTPParserTests {
    @Test func waitsForCompleteBodyBeforeProducingRequest() {
        var parser = LocalHTTPRequestParser()

        #expect(parser.append(Data("POST /agent/events HTTP/1.1\r\nContent-Length: 5\r\n\r\n12".utf8)) == .incomplete)
        let result = parser.append(Data("345".utf8))

        guard case let .request(request) = result else {
            Issue.record("Expected a complete request")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/agent/events")
        #expect(request.bodyString == "12345")
    }

    @Test func contentLengthHeaderIsCaseInsensitive() {
        var parser = LocalHTTPRequestParser()

        let result = parser.append(Data("POST /agent/events HTTP/1.1\r\ncontent-length: 2\r\n\r\n{}".utf8))

        guard case let .request(request) = result else {
            Issue.record("Expected a complete request")
            return
        }
        #expect(request.bodyString == "{}")
    }

    @Test func rejectsInvalidContentLength() {
        var parser = LocalHTTPRequestParser()

        #expect(parser.append(Data("POST /agent/events HTTP/1.1\r\nContent-Length: nope\r\n\r\n{}".utf8)) == .invalid)
    }
}

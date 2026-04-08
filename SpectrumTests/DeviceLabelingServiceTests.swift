import XCTest
@testable import Spectrum

final class DeviceLabelingServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testGenerateLabelBuildsExpectedResponsesRequest() async throws {
        let expectation = expectation(description: "request")
        StubURLProtocol.requestHandler = { [self] request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

            let body = try XCTUnwrap(self.requestBody(from: request))
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(payload?["model"] as? String, "gpt-5.4-mini")
            XCTAssertEqual(payload?["instructions"] as? String, OpenAIResponsesDeviceLabelingService.promptTemplate)
            XCTAssertEqual(payload?["input"] as? String, "AA:BB:CC:DD:EE:FF")
            XCTAssertEqual(payload?["max_output_tokens"] as? Int, 25_000)

            let reasoning = payload?["reasoning"] as? [String: Any]
            XCTAssertEqual(reasoning?["effort"] as? String, "medium")

            let tools = payload?["tools"] as? [[String: Any]]
            XCTAssertEqual(tools?.count, 1)
            XCTAssertEqual(tools?.first?["type"] as? String, "web_search")

            expectation.fulfill()
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                #"{"output_text":"```text\nApple iPhone\n```"}"#.data(using: .utf8)!
            )
        }

        let service = OpenAIResponsesDeviceLabelingService(
            session: makeSession(),
            endpoint: URL(string: "https://example.com/v1/responses")!
        )

        let label = try await service.generateLabel(
            for: "AA:BB:CC:DD:EE:FF",
            model: "gpt-5.4-mini",
            apiKey: "sk-test",
            maxOutputTokens: 25_000
        )

        XCTAssertEqual(label, "Apple iPhone")
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testParseLabelExtractsFencedText() throws {
        let label = try OpenAIResponsesDeviceLabelingService.parseLabel(
            from: """
            ```text
            Apple iPhone
            ```
            """
        )

        XCTAssertEqual(label, "Apple iPhone")
    }

    func testParseLabelFallsBackToPlainText() throws {
        let label = try OpenAIResponsesDeviceLabelingService.parseLabel(from: "Private Device")

        XCTAssertEqual(label, "Private Device")
    }

    func testParseLabelRejectsEmptyAndTooLongValues() {
        XCTAssertThrowsError(try OpenAIResponsesDeviceLabelingService.parseLabel(from: "   "))
        XCTAssertThrowsError(try OpenAIResponsesDeviceLabelingService.parseLabel(from: "This Label Is Definitely Longer Than Thirty Characters"))
    }

    func testGenerateLabelIncludesRawResponseWhenOutputIsUnreadable() async {
        StubURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                #"{"status":"completed","output":[]}"#.data(using: .utf8)!
            )
        }

        let service = OpenAIResponsesDeviceLabelingService(
            session: makeSession(),
            endpoint: URL(string: "https://example.com/v1/responses")!
        )

        do {
            _ = try await service.generateLabel(
                for: "AA:BB:CC:DD:EE:FF",
                model: "gpt-5.4-mini",
                apiKey: "sk-test",
                maxOutputTokens: 25_000
            )
            XCTFail("Expected invalid response error")
        } catch let error as DeviceLabelingServiceError {
            XCTAssertEqual(error.errorDescription, "OpenAI returned an unreadable response.")
            XCTAssertEqual(error.debugDetails, #"{"status":"completed","output":[]}"#)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }

        return data.isEmpty ? nil : data
    }
}

private final class StubURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

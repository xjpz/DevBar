import Foundation
import Testing
@testable import DevBarCore

@Test
func hermesAPIClientNormalizesChatURLFromBaseURL() throws {
    let url = try #require(HermesAPIClient.chatURL(from: " https://hermes.example.com/api/ "))

    #expect(url.absoluteString == "https://hermes.example.com/api/chat/completions")
}

@Test
func hermesAPIClientKeepsExplicitChatCompletionsURL() throws {
    let url = try #require(HermesAPIClient.chatURL(from: "https://hermes.example.com/v1/chat/completions"))

    #expect(url.absoluteString == "https://hermes.example.com/v1/chat/completions")
}

@Test
func hermesAPIClientRejectsInvalidBaseURL() {
    #expect(HermesAPIClient.chatURL(from: "not a url") == nil)
}

@Test
func hermesAPIClientDecodesOpenAICompatibleTextResponse() throws {
    let json = """
    {
      "choices": [
        {
          "message": {
            "role": "assistant",
            "content": "部署问题检查完成"
          }
        }
      ]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(HermesChatResponse.self, from: json)

    #expect(response.assistantContent == "部署问题检查完成")
}

@Test
func hermesAPIClientParsesSSETextDeltas() {
    let stream = """
    data: {"choices":[{"delta":{"content":"你好"}}]}

    data: {"choices":[{"delta":{"content":"，Hermes"}}]}

    data: [DONE]

    """

    #expect(HermesAPIClient.parseStreamDeltas(from: stream) == ["你好", "，Hermes"])
}

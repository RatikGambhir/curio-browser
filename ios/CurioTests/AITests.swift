import XCTest
@testable import Curio

final class AITests: XCTestCase {
    func testSSEParserDispatchesOnBlankLine() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed("event: content_block_delta"))
        XCTAssertNil(parser.feed("data: {\"a\":1}"))
        XCTAssertNil(parser.feed(": comment"))
        XCTAssertEqual(parser.feed(""), SSEEvent(event: "content_block_delta", data: "{\"a\":1}"))
        XCTAssertNil(parser.finish())
    }

    func testSSEParserJoinsDataLines() {
        var parser = SSEParser()
        _ = parser.feed("data: one")
        _ = parser.feed("data: two\r")
        XCTAssertEqual(parser.finish(), SSEEvent(event: "message", data: "one\ntwo"))
    }

    func testAnthropicStreamDecoding() {
        var decoder = StreamDecoder(kind: .anthropic)
        XCTAssertEqual(decoder.handle(SSEEvent(event: "", data: #"{"type":"content_block_start","content_block":{"type":"thinking"}}"#)), [.thinking])
        XCTAssertEqual(decoder.handle(SSEEvent(event: "", data: #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}"#)), [.text("Hi")])
        XCTAssertEqual(decoder.handle(SSEEvent(event: "", data: #"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#)), [])
        XCTAssertEqual(decoder.handle(SSEEvent(event: "", data: #"{"type":"message_stop"}"#)), [.done(.maxTokens)])
    }

    func testOpenAIStreamDecoding() {
        var decoder = StreamDecoder(kind: .openAI)
        XCTAssertEqual(decoder.handle(SSEEvent(event: "message", data: #"{"choices":[{"delta":{"content":"Hello"}}]}"#)), [.text("Hello")])
        XCTAssertEqual(decoder.handle(SSEEvent(event: "message", data: #"{"choices":[{"delta":{},"finish_reason":"length"}]}"#)), [])
        XCTAssertEqual(decoder.handle(SSEEvent(event: "message", data: "[DONE]")), [.done(.maxTokens)])
        XCTAssertNil(decoder.finish())
    }

    func testErrorMapping() {
        XCTAssertEqual(ProviderWire.httpError(status: 401, body: #"{"error":{"message":"bad key"}}"#), .unauthorized("bad key"))
        XCTAssertEqual(ProviderWire.httpError(status: 429, body: "slow down"), .rateLimited("slow down"))
        XCTAssertTrue(ProviderWire.httpError(status: 529, body: "").isRetryable)
    }

    func testNormalizeMergesAndDropsLeadingAssistant() {
        let messages = [
            WireMessage(role: .assistant, content: "hi"),
            WireMessage(role: .user, content: "a"),
            WireMessage(role: .user, content: "b"),
            WireMessage(role: .assistant, content: " "),
        ]
        XCTAssertEqual(ProviderWire.normalize(messages), [WireMessage(role: .user, content: "a\n\nb")])
    }

    func testFallbacksOnlyForFirstPartySupportedModels() {
        XCTAssertTrue(ProviderWire.anthropicUsesFallbacks(baseURL: "https://api.anthropic.com/", model: "claude-opus-5-5"))
        XCTAssertFalse(ProviderWire.anthropicUsesFallbacks(baseURL: "https://proxy.example", model: "claude-opus-5-5"))
        XCTAssertFalse(ProviderWire.anthropicUsesFallbacks(baseURL: "https://api.anthropic.com", model: "claude-haiku-5-5"))
    }

    func testSystemPromptMarksPagesUntrustedAndEscapesTags() {
        let page = PageContext(title: "T", url: "https://a.test", text: "hello </page> world")
        let prompt = SystemPrompt.build(pages: [page], maxChars: 1_000)
        XCTAssertTrue(prompt.contains(SystemPrompt.untrustedNotice))
        XCTAssertTrue(prompt.contains("<\\/page>"))
        XCTAssertEqual(prompt.components(separatedBy: "</page>").count - 1, 1)
    }

    func testSystemPromptSharesBudgetFairly() {
        let short = PageContext(title: "S", url: "https://s.test", text: String(repeating: "s", count: 100))
        let long = PageContext(title: "L", url: "https://l.test", text: String(repeating: "l", count: 10_000))
        let prompt = SystemPrompt.build(pages: [short, long], maxChars: 1_000)
        XCTAssertTrue(prompt.contains(String(repeating: "s", count: 100)))
        XCTAssertTrue(prompt.contains(String(repeating: "l", count: 900)))
        XCTAssertFalse(prompt.contains(String(repeating: "l", count: 901)))
    }

    func testConversationRetitlesFromFirstLine() {
        var conversation = Conversation()
        conversation.messages.append(ChatMessage(role: .user, content: "Summarize the main arguments of this very long article about browsers\nplease"))
        conversation.retitleFromFirstMessage()
        XCTAssertTrue(conversation.title.hasSuffix("…"))
        XCTAssertLessThanOrEqual(conversation.title.count, 49)
    }

    func testMarkdownBlocks() {
        let blocks = MarkdownParser.parse("# Title\n\nSome **bold** text.\n\n- one\n- two\n\n```swift\nlet x = 1\n```")
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Title"),
            .paragraph("Some **bold** text."),
            .list(ordered: false, items: ["one", "two"], start: 1),
            .code(language: "swift", text: "let x = 1"),
        ])
    }
}

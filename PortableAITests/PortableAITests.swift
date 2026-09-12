import Foundation
import Testing
@testable import PortableAI

struct PortableAITests {
    @Test func personasDecodeContractShape() throws {
        let json = """
        [
          {
            "id": "assistant",
            "display_name": "Assistant",
            "is_default": true,
            "icon": "message",
            "base_model": "llama3.2:3b",
            "system_preview": "You are helpful",
            "parameters": { "temperature": 0.7, "num_ctx": 4096 }
          },
          {
            "id": "broken-persona",
            "display_name": "Broken Persona",
            "is_default": false,
            "icon": "message",
            "error": "parse fail"
          }
        ]
        """.data(using: .utf8)!
        let personas = try JSONDecoder().decode([Persona].self, from: json)
        #expect(personas.count == 2)
        #expect(personas[0].id == "assistant")
        #expect(personas[0].displayName == "Assistant")
        #expect(personas[0].isDefault == true)
        #expect(personas[0].base_model == "llama3.2:3b")
        #expect(personas[0].parameters?["temperature"] == .number(0.7))
        #expect(personas[1].error == "parse fail")
        #expect(personas[1].base_model == nil)
    }

    @Test func chatResponseDecodesContractShape() throws {
        let json = """
        {"reply":"hi","latency_ms":42,"model_used":"assistant","conversation_id":"abc"}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ChatResponse.self, from: json)
        #expect(response.reply == "hi")
        #expect(response.latency_ms == 42)
        #expect(response.model_used == "assistant")
        #expect(response.conversation_id == "abc")
    }

    @Test func conversationListRowDecodesContractShape() throws {
        let json = """
        [{
          "id": "uuid-1",
          "owner_id": "tok",
          "persona": "assistant",
          "model_used": "assistant",
          "title": null,
          "created_at": 1732650000.0,
          "updated_at": 1732650001.0,
          "archived": 0
        }]
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode([ConversationSummary].self, from: json)
        #expect(rows.count == 1)
        #expect(rows[0].displayTitle == "New chat")
        #expect(rows[0].archived == 0)
        #expect(rows[0].persona == "assistant")
    }

    @Test func conversationDetailDecodesMessagesWithoutIds() throws {
        let json = """
        {
          "id": "uuid-1",
          "owner_id": "tok",
          "persona": "assistant",
          "model_used": "assistant",
          "title": "Hello",
          "created_at": 1732650000.0,
          "updated_at": 1732650001.0,
          "archived": 0,
          "messages": [
            {"role":"user","content":"Hi","latency_ms":null,"created_at":1732650000.5},
            {"role":"assistant","content":"Hey","latency_ms":10,"created_at":1732650001.2}
          ]
        }
        """.data(using: .utf8)!
        let detail = try JSONDecoder().decode(ConversationDetail.self, from: json)
        #expect(detail.displayTitle == "Hello")
        #expect(detail.chatMessages.count == 2)
        #expect(detail.chatMessages[0].role == "user")
        #expect(detail.chatMessages[1].content == "Hey")
    }
}

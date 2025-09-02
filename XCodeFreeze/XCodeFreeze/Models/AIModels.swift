import Foundation

// MARK: - AI Tool Data Structures

struct AITool: Codable {
    let type: String
    let function: AIFunction
}

struct AIFunction: Codable {
    let name: String
    let description: String
    let parameters: AIFunctionParameters?
}

struct AIFunctionParameters: Codable {
    let type: String
    let properties: [String: AIPropertyDefinition]
    let required: [String]?
}

struct AIPropertyDefinition: Codable {
    let type: String
    let description: String?
    let enumValues: [String]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }
}

struct ToolCall: Codable {
    let id: String
    let type: String
    let function: ToolCallFunction
}

struct ToolCallFunction: Codable {
    let name: String
    let arguments: String
}

// MARK: - AI Model Data Structures

struct AIModel: Codable, Identifiable, Hashable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case ownedBy = "owned_by"
    }
}

struct AIModelsResponse: Codable {
    let object: String
    let data: [AIModel]
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatCompletionMessage]
    let temperature: Double
    let maxTokens: Int?
    let stream: Bool
    let tools: [AITool]?
    let toolChoice: String?
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case tools
        case toolChoice = "tool_choice"
    }
}

struct ChatCompletionMessage: Codable {
    let role: String
    let content: String?
    let toolCalls: [ToolCall]?
    let toolCallId: String?
    
    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
    
    init(role: String, content: String) {
        self.role = role
        self.content = content
        self.toolCalls = nil
        self.toolCallId = nil
    }
    
    init(role: String, toolCalls: [ToolCall]) {
        self.role = role
        self.content = nil
        self.toolCalls = toolCalls
        self.toolCallId = nil
    }
    
    init(role: String, content: String, toolCallId: String) {
        self.role = role
        self.content = content
        self.toolCalls = nil
        self.toolCallId = toolCallId
    }
}

struct ChatCompletionResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatCompletionChoice]
    let usage: ChatCompletionUsage?
}

struct ChatCompletionChoice: Codable {
    let index: Int
    let message: ChatCompletionMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

struct ChatCompletionUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - AI Chat Message Extensions

extension ChatMessage {
    var isFromAI: Bool {
        return sender == "AI" || sender.contains("qwen") || sender.contains("llama") || sender.contains("gpt")
    }
    
    var isUserMessage: Bool {
        return sender == "You" && !isFromServer && !isFromAI
    }
}
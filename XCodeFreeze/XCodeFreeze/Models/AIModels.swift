import Foundation

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
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

struct ChatCompletionMessage: Codable {
    let role: String
    let content: String
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
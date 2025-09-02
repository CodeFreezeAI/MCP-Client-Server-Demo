import Foundation
import SwiftUI

// MARK: - AI Service for Local LLM Communication

@MainActor
class AIService: ObservableObject {
    static let shared = AIService()
    
    @Published var availableModels: [AIModel] = []
    @Published var selectedModel: AIModel?
    @Published var isConnected = false
    @Published var isLoading = false
    
    private let baseURL = "http://192.168.1.135:11434"
    private let session = URLSession.shared
    
    private init() {}
    
    // MARK: - Model Management
    
    func fetchAvailableModels() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let url = URL(string: "\(baseURL)/v1/models") else {
            print("Invalid URL for models endpoint")
            return
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    let modelsResponse = try decoder.decode(AIModelsResponse.self, from: data)
                    
                    availableModels = modelsResponse.data
                    isConnected = true
                    
                    // Auto-select qwen3-coder model if available
                    if selectedModel == nil {
                        selectedModel = availableModels.first { $0.id.contains("qwen3-coder") } ?? availableModels.first
                    }
                    
                    print("Successfully fetched \(availableModels.count) models")
                } else {
                    print("HTTP Error: \(httpResponse.statusCode)")
                    isConnected = false
                }
            }
        } catch {
            print("Failed to fetch models: \(error)")
            isConnected = false
        }
    }
    
    // MARK: - Chat Completion
    
    func sendChatCompletion(messages: [ChatCompletionMessage]) async -> String? {
        guard let selectedModel = selectedModel else {
            print("No model selected")
            return nil
        }
        
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            print("Invalid URL for chat completions endpoint")
            return nil
        }
        
        let request = ChatCompletionRequest(
            model: selectedModel.id,
            messages: messages,
            temperature: 0.7,
            maxTokens: 4000,
            stream: false,
            tools: nil,
            toolChoice: nil
        )
        
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(request)
            
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = jsonData
            
            let (data, response) = try await session.data(for: urlRequest)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    let completionResponse = try decoder.decode(ChatCompletionResponse.self, from: data)
                    
                    return completionResponse.choices.first?.message.content
                } else {
                    print("HTTP Error: \(httpResponse.statusCode)")
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Error response: \(errorString)")
                    }
                }
            }
        } catch {
            print("Failed to send chat completion: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Convenience Methods
    
    func sendMessage(_ content: String, includeThinking: Bool = true, availableTools: [MCPTool] = []) async -> String? {
        var messages = [ChatCompletionMessage]()
        
        if includeThinking {
            // Add system message for thinking capability and tool usage
            messages.append(ChatCompletionMessage(
                role: "system",
                content: """
You are an expert coding assistant integrated into XCodeFreeze. You have access to MCP (Model Context Protocol) tools that can help you with various software engineering tasks.

Available MCP Tools:
\(availableTools.map { "- \($0.name): \($0.description)" }.joined(separator: "\n"))

When solving complex problems, use <thinking> tags to show your reasoning process before providing the final answer.

Example:
<thinking>
Let me analyze this request...
The user wants me to...
I should use the appropriate tool...
</thinking>

Then provide your response.

Use the available tools when they can help answer the user's question or complete their request. Be helpful, accurate, and concise in your responses.
"""
            ))
        }
        
        messages.append(ChatCompletionMessage(role: "user", content: content))
        
        // Convert MCP tools to AI function format
        let aiTools = availableTools.map { mcpTool in
            AITool(
                type: "function",
                function: AIFunction(
                    name: mcpTool.name,
                    description: mcpTool.description,
                    parameters: createBasicFunctionParameters()
                )
            )
        }
        
        return await sendChatCompletionWithTools(messages: messages, tools: aiTools.isEmpty ? nil : aiTools)
    }
    
    // MARK: - Tool Integration
    
    private func sendChatCompletionWithTools(messages: [ChatCompletionMessage], tools: [AITool]?) async -> String? {
        guard let selectedModel = selectedModel else {
            print("No model selected")
            return nil
        }
        
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            print("Invalid URL for chat completions endpoint")
            return nil
        }
        
        let request = ChatCompletionRequest(
            model: selectedModel.id,
            messages: messages,
            temperature: 0.7,
            maxTokens: 4000,
            stream: false,
            tools: tools,
            toolChoice: tools?.isEmpty == false ? "auto" : nil
        )
        
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(request)
            
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = jsonData
            
            let (data, response) = try await session.data(for: urlRequest)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    let completionResponse = try decoder.decode(ChatCompletionResponse.self, from: data)
                    
                    // For now, just return the content - tool calling integration comes next
                    return completionResponse.choices.first?.message.content
                } else {
                    print("HTTP Error: \(httpResponse.statusCode)")
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Error response: \(errorString)")
                    }
                }
            }
        } catch {
            print("Failed to send chat completion with tools: \(error)")
        }
        
        return nil
    }
    
    private func createBasicFunctionParameters() -> AIFunctionParameters {
        // Create a basic function parameter structure for MCP tools
        // This allows the AI to call tools with text arguments
        return AIFunctionParameters(
            type: "object",
            properties: [
                "text": AIPropertyDefinition(
                    type: "string",
                    description: "The text argument or command for the tool",
                    enumValues: nil
                )
            ],
            required: ["text"]
        )
    }
    
    func getModelDisplayName(_ model: AIModel) -> String {
        // Clean up model names for display
        let name = model.id
            .replacingOccurrences(of: ":latest", with: "")
            .replacingOccurrences(of: ":30b-a3b-q8_0", with: "")
        
        return name.capitalized
    }
}
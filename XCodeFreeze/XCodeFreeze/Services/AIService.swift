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
    @Published var conversationHistory: [ChatCompletionMessage] = []
    
    @Published var baseURL = "http://192.168.1.135:11434"
    private let session = URLSession.shared
    
    private init() {}
    
    // MARK: - Server Configuration
    
    func updateServerAddress(_ address: String) {
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanAddress.hasPrefix("http://") || cleanAddress.hasPrefix("https://") {
            baseURL = cleanAddress
        } else {
            baseURL = "http://\(cleanAddress)"
        }
        
        // Reset connection status when server changes
        isConnected = false
        availableModels = []
        selectedModel = nil
    }
    
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
            // Add system message for thinking capability with detailed tool schemas
            let toolsList = availableTools.map { tool in
                var toolDescription = "- **\(tool.name)**: \(tool.description)"
                
                // Add parameter information if available
                if let schema = tool.inputSchema,
                   let properties = schema["properties"] as? [String: Any],
                   let required = schema["required"] as? [String] {
                    
                    let paramsList = properties.map { (key, value) in
                        let isRequired = required.contains(key)
                        let requiredStr = isRequired ? " (required)" : " (optional)"
                        
                        if let paramInfo = value as? [String: Any],
                           let type = paramInfo["type"] as? String,
                           let description = paramInfo["description"] as? String {
                            return "    • \(key): \(type)\(requiredStr) - \(description)"
                        } else {
                            return "    • \(key)\(requiredStr)"
                        }
                    }.joined(separator: "\n")
                    
                    if !paramsList.isEmpty {
                        toolDescription += "\n\(paramsList)"
                    }
                } else if let schema = tool.inputSchema {
                    // Simple schema without detailed properties
                    toolDescription += "\n    Parameters: \(schema)"
                }
                
                return toolDescription
            }.joined(separator: "\n\n")
            
            messages.append(ChatCompletionMessage(
                role: "system",
                content: """
You are an expert coding assistant integrated into XCodeFreeze. You can help with various software engineering tasks.

\(toolsList.isEmpty ? "" : """
Available MCP Tools (mention these by name when they would be helpful):

\(toolsList)

When you want to use a tool, simply mention it in your response like "Let me use the read_file tool to examine that file" or "I'll run the list_projects tool to see available projects". The system will automatically execute the tool for you.
""")

When solving complex problems, use <thinking> tags to show your reasoning process before providing the final answer.

Example:
<thinking>
Let me analyze this request...
The user wants me to...
I should use the read_file tool to examine the file first...
</thinking>

Then provide your response. If you need to use tools, mention them naturally in your response.

Be helpful, accurate, and concise in your responses.
"""
            ))
        }
        
        // Add recent conversation history (keep last 10 messages to manage token count)
        let recentHistory = conversationHistory.suffix(10)
        messages.append(contentsOf: recentHistory)
        
        // Add current user message
        let userMessage = ChatCompletionMessage(role: "user", content: content)
        messages.append(userMessage)
        
        // Send to LLM
        if let response = await sendChatCompletion(messages: messages) {
            // Add both user message and assistant response to history
            conversationHistory.append(userMessage)
            conversationHistory.append(ChatCompletionMessage(role: "assistant", content: response))
            
            // Keep history manageable (last 50 messages)
            if conversationHistory.count > 50 {
                conversationHistory.removeFirst(conversationHistory.count - 50)
            }
            
            return response
        }
        
        return nil
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
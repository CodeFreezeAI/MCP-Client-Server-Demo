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
    private let selectedModelKey = "AIService.selectedModel"
    
    // Callback to execute MCP tools
    var mcpToolExecutor: ((String, String) async -> String?)?
    
    func setMCPToolExecutor(_ executor: @escaping (String, String) async -> String?) {
        mcpToolExecutor = executor
    }
    
    private init() {
        loadSelectedModel()
    }
    
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
        // Don't reset selectedModel - preserve user's choice
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
                    
                    // Only auto-select if no model was saved in UserDefaults
                    if selectedModel == nil {
                        print("🔧 AIService: No saved model found, auto-selecting default")
                        let autoSelected = availableModels.first { $0.id.contains("qwen3-coder") } ?? availableModels.first
                        setSelectedModel(autoSelected)
                    } else {
                        print("✅ AIService: Using saved model from UserDefaults")
                    }
                    
                    // Debug: Show what models are available and what's selected
                    let availableIds = availableModels.map { $0.id }
                    print("🔍 AIService: Available model IDs: \(availableIds)")
                    if let currentModel = selectedModel {
                        print("🔍 AIService: Currently selected model ID: \(currentModel.id)")
                    } else {
                        print("🔍 AIService: No model currently selected")
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
            maxTokens: 25000,
            stream: false,
            tools: nil,
            toolChoice: nil
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted // For debugging
            let jsonData = try encoder.encode(request)
            
            // DEBUG: Log what we're sending
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("🔧 DEBUG: Sending to Ollama:")
                print(jsonString)
            }
            
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
        
        // Convert MCP tools to AI function tools
        let aiFunctions = convertMCPToolsToAIFunctions(availableTools)
        
        // Send to LLM with tools if available
        if let response = await sendChatCompletionWithTools(messages: messages, tools: aiFunctions) {
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
            maxTokens: 25000,
            stream: false,
            tools: tools,
            toolChoice: tools?.isEmpty == false ? "auto" : nil
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted // For debugging
            let jsonData = try encoder.encode(request)
            
            // DEBUG: Log what we're sending
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("🔧 DEBUG: Sending to Ollama:")
                print(jsonString)
            }
            
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = jsonData
            
            let (data, response) = try await session.data(for: urlRequest)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    // DEBUG: Log response
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("🔧 DEBUG: Response from Ollama:")
                        print(responseString)
                    }
                    
                    let decoder = JSONDecoder()
                    let completionResponse = try decoder.decode(ChatCompletionResponse.self, from: data)
                    
                    // Handle tool calls if present
                    if let message = completionResponse.choices.first?.message {
                        print("🔧 DEBUG: Message has tool_calls: \(message.toolCalls != nil)")
                        if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                            print("🚀 AI wants to call \(toolCalls.count) tool(s)")
                            // AI wants to call tools - execute them and continue conversation
                            return await handleToolCalls(toolCalls, messages: messages, tools: tools)
                        } else {
                            // Normal response without tool calls
                            print("📝 Normal response (no tool calls)")
                            return message.content
                        }
                    }
                } else {
                    print("HTTP Error: \(httpResponse.statusCode)")
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Error response: \(errorString)")
                        
                        // Check if model doesn't support tools - fall back to regular chat
                        if httpResponse.statusCode == 400 && 
                           errorString.contains("does not support tools") &&
                           tools?.isEmpty == false {
                            print("Model doesn't support tools, falling back to regular chat completion")
                            return await sendChatCompletion(messages: messages)
                        }
                    }
                }
            }
        } catch {
            print("Failed to send chat completion with tools: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Tool Call Handling
    
    private func handleToolCalls(_ toolCalls: [ToolCall], messages: [ChatCompletionMessage], tools: [AITool]?) async -> String? {
        var updatedMessages = messages
        
        // Add the assistant's tool call message to conversation
        updatedMessages.append(ChatCompletionMessage(role: "assistant", toolCalls: toolCalls))
        
        // Execute each tool call and collect results
        for toolCall in toolCalls {
            let toolName = toolCall.function.name
            let arguments = toolCall.function.arguments
            
            // Execute the MCP tool (you'll need to connect this to your MCP client)
            let result = await executeMCPTool(name: toolName, arguments: arguments)
            
            // Add tool result to conversation
            let toolResultMessage = ChatCompletionMessage(
                role: "tool", 
                content: result, 
                toolCallId: toolCall.id
            )
            updatedMessages.append(toolResultMessage)
        }
        
        // Send updated conversation back to AI to get final response
        return await sendChatCompletionWithTools(messages: updatedMessages, tools: tools)
    }
    
    internal func executeMCPTool(name: String, arguments: String) async -> String {
        // For MCP tools, we need to pass the full arguments JSON, not just a single text parameter
        // The MCP server will parse the JSON and extract the appropriate parameters
        
        // Execute via callback with full JSON arguments
        if let result = await mcpToolExecutor?(name, arguments) {
            return result
        } else {
            return "Error: MCP tool executor not available"
        }
    }
    
    // MARK: - MCP Tool Conversion
    
    internal func convertMCPToolsToAIFunctions(_ mcpTools: [MCPTool]) -> [AITool]? {
        guard !mcpTools.isEmpty else { return nil }
        
        return mcpTools.map { mcpTool in
            let function = AIFunction(
                name: mcpTool.name,
                description: mcpTool.description,
                parameters: createParametersFromMCPTool(mcpTool)
            )
            
            return AITool(
                type: "function",
                function: function
            )
        }
    }
    
    internal func createParametersFromMCPTool(_ mcpTool: MCPTool) -> AIFunctionParameters? {
        // Return the schema directly as-is if it exists
        // The schema is already in the correct format from the MCP server
        if let inputSchema = mcpTool.inputSchema {
            // The schema should already be properly formatted after our fix in ClientServerService
            print("🔧 DEBUG: Tool \(mcpTool.name) has schema: \(inputSchema)")
            
            // Extract properties and required fields directly
            let properties = inputSchema["properties"] as? [String: Any] ?? [:]
            let required = inputSchema["required"] as? [String] ?? []
            
            print("🔧 DEBUG: Tool \(mcpTool.name) properties extracted: \(properties.keys.joined(separator: ", "))")
            print("🔧 DEBUG: Tool \(mcpTool.name) required fields: \(required.joined(separator: ", "))")
            
            // Convert properties to AIPropertyDefinition format
            var aiProperties: [String: AIPropertyDefinition] = [:]
            for (propName, propValue) in properties {
                if let propDict = propValue as? [String: Any] {
                    let type = propDict["type"] as? String ?? "string"
                    let description = propDict["description"] as? String
                    aiProperties[propName] = AIPropertyDefinition(
                        type: type,
                        description: description,
                        enumValues: nil
                    )
                    print("🔧 DEBUG: Added parameter '\(propName)' of type '\(type)' to tool \(mcpTool.name)")
                }
            }
            
            let params = AIFunctionParameters(
                type: "object",
                properties: aiProperties,
                required: required
            )
            
            print("🔧 DEBUG: Final parameters for \(mcpTool.name): \(aiProperties.count) properties")
            return params
        }
        
        // No schema - return minimal parameters
        print("🔧 DEBUG: Tool \(mcpTool.name) has NO schema, using empty parameters")
        return AIFunctionParameters(
            type: "object",
            properties: [:],
            required: []
        )
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
    
    // MARK: - Model Selection Persistence
    
    func setSelectedModel(_ model: AIModel?) {
        print("🔧 AIService: setSelectedModel called with: \(model?.id ?? "nil")")
        selectedModel = model
        saveSelectedModel()
        print("🔧 AIService: setSelectedModel completed")
    }
    
    private func saveSelectedModel() {
        if let model = selectedModel {
            if let encoded = try? JSONEncoder().encode(model) {
                UserDefaults.standard.set(encoded, forKey: selectedModelKey)
                print("💾 AIService: Saved model to UserDefaults: \(model.id)")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: selectedModelKey)
            print("💾 AIService: Removed saved model from UserDefaults")
        }
    }
    
    private func loadSelectedModel() {
        if let data = UserDefaults.standard.data(forKey: selectedModelKey),
           let model = try? JSONDecoder().decode(AIModel.self, from: data) {
            print("🔄 AIService: Loaded saved model from UserDefaults: \(model.id)")
            selectedModel = model
        } else {
            print("🔄 AIService: No saved model found in UserDefaults")
        }
    }
}

import Foundation
import Combine

/// NOTICE: This service is currently not integrated into the main app.
/// The app uses AIService instead for AI integration.
/// This implementation provides enhanced MCP tool calling but needs integration work.
///
/// Enhanced AI integration service for seamless MCP tool calling
/// Provides Claude Code / Cursor-like experience with automatic tool execution
@MainActor
public class MCPAIIntegrationService: ObservableObject {
    
    // MARK: - Message Types
    
    public struct AIMessage {
        public let role: Role
        public let content: String
        public let toolCalls: [ToolCall]?
        public let toolCallId: String?
        public let timestamp = Date()
        
        public enum Role: String {
            case system
            case user
            case assistant
            case tool
        }
        
        public struct ToolCall {
            public let id: String
            public let name: String
            public let arguments: [String: Any]
        }
    }
    
    public struct AIResponse {
        public let content: String
        public let toolsExecuted: [String]
        public let thinking: String?
        public let confidence: Double
    }
    
    // MARK: - Properties
    
    @Published public private(set) var isProcessing = false
    @Published public private(set) var currentTask: String?
    @Published public private(set) var conversationHistory: [AIMessage] = []
    @Published public private(set) var lastError: String?
    
    private let toolDiscovery: MCPToolDiscoveryService
    private let communicationService: MCPCommunicationService
    private let aiEndpoint: String
    private var currentModel: String = "claude-3-opus"
    
    private let session = URLSession.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Tool execution strategy
    private var autoExecuteTools = true
    private var requireConfirmation = false
    private let maxToolIterations = 5
    
    // MARK: - Initialization
    
    public init(
        toolDiscovery: MCPToolDiscoveryService,
        communicationService: MCPCommunicationService,
        aiEndpoint: String = "http://localhost:11434/v1"
    ) {
        self.toolDiscovery = toolDiscovery
        self.communicationService = communicationService
        self.aiEndpoint = aiEndpoint
        
        setupSystemPrompt()
    }
    
    // MARK: - System Prompt
    
    private func setupSystemPrompt() {
        let systemPrompt = """
        You are an expert AI assistant integrated with XCodeFreeze, a powerful macOS development environment.
        You have access to MCP (Model Context Protocol) tools that allow you to interact with Xcode and the file system.
        
        IMPORTANT CAPABILITIES:
        - You can read, write, and modify files
        - You can build and run Xcode projects
        - You can analyze Swift code and suggest improvements
        - You can execute system commands safely
        
        TOOL USAGE:
        - When you need to use a tool, I will automatically execute it for you
        - You can chain multiple tool calls to accomplish complex tasks
        - Always verify the results of tool executions before proceeding
        
        THINKING PROCESS:
        - Use <thinking> tags to show your reasoning when solving complex problems
        - Break down tasks into smaller steps
        - Consider edge cases and error handling
        
        RESPONSE STYLE:
        - Be concise and direct
        - Provide code examples when relevant
        - Explain your actions clearly
        - Ask for clarification when needed
        """
        
        let systemMessage = AIMessage(
            role: .system,
            content: systemPrompt,
            toolCalls: nil,
            toolCallId: nil
        )
        
        conversationHistory.append(systemMessage)
    }
    
    // MARK: - Message Processing
    
    /// Process a user message with automatic tool execution
    public func processMessage(_ content: String) async -> AIResponse {
        isProcessing = true
        currentTask = "Processing your message..."
        lastError = nil
        
        defer {
            isProcessing = false
            currentTask = nil
        }
        
        // Add user message to history
        let userMessage = AIMessage(
            role: .user,
            content: content,
            toolCalls: nil,
            toolCallId: nil
        )
        conversationHistory.append(userMessage)
        
        // Get available tools
        let tools = toolDiscovery.exportForOpenAI()
        
        // Process with tool iteration
        var toolsExecuted: [String] = []
        var iterations = 0
        var finalResponse = ""
        var thinking: String? = nil
        
        while iterations < maxToolIterations {
            iterations += 1
            currentTask = iterations == 1 ? "Analyzing request..." : "Processing tool results..."
            
            // Send to AI with tools
            let response = await sendToAI(withTools: tools)
            
            // Extract thinking if present
            if let thinkingContent = extractThinking(from: response.content) {
                thinking = thinkingContent
            }
            
            // Check for tool calls
            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                currentTask = "Executing tools..."
                
                // Execute tools and collect results
                for toolCall in toolCalls {
                    let result = await executeToolCall(toolCall)
                    toolsExecuted.append(toolCall.name)
                    
                    // Add tool result to conversation
                    let toolMessage = AIMessage(
                        role: .tool,
                        content: result,
                        toolCalls: nil,
                        toolCallId: toolCall.id
                    )
                    conversationHistory.append(toolMessage)
                }
                
                // Continue iteration to process tool results
                continue
            } else {
                // No more tool calls, we have the final response
                finalResponse = cleanResponse(response.content)
                
                // Add assistant response to history
                let assistantMessage = AIMessage(
                    role: .assistant,
                    content: finalResponse,
                    toolCalls: nil,
                    toolCallId: nil
                )
                conversationHistory.append(assistantMessage)
                break
            }
        }
        
        // Calculate confidence based on iterations and tools used
        let confidence = calculateConfidence(iterations: iterations, toolsUsed: toolsExecuted.count)
        
        return AIResponse(
            content: finalResponse,
            toolsExecuted: toolsExecuted,
            thinking: thinking,
            confidence: confidence
        )
    }
    
    // MARK: - AI Communication
    
    private func sendToAI(withTools tools: [[String: Any]]) async -> (content: String, toolCalls: [AIMessage.ToolCall]?) {
        // Prepare messages for API
        let apiMessages = conversationHistory.map { message in
            var msgDict: [String: Any] = [
                "role": message.role.rawValue,
                "content": message.content
            ]
            
            if let toolCalls = message.toolCalls {
                msgDict["tool_calls"] = toolCalls.map { toolCall in
                    [
                        "id": toolCall.id,
                        "type": "function",
                        "function": [
                            "name": toolCall.name,
                            "arguments": try? JSONSerialization.data(
                                withJSONObject: toolCall.arguments,
                                options: []
                            ).base64EncodedString()
                        ]
                    ]
                }
            }
            
            if let toolCallId = message.toolCallId {
                msgDict["tool_call_id"] = toolCallId
            }
            
            return msgDict
        }
        
        // Create request
        let requestBody: [String: Any] = [
            "model": currentModel,
            "messages": apiMessages,
            "tools": tools,
            "tool_choice": "auto",
            "temperature": 0.7,
            "max_tokens": 25000
        ]
        
        guard let url = URL(string: "\(aiEndpoint)/chat/completions"),
              let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return ("Failed to prepare request", nil)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        do {
            let (data, _) = try await session.data(for: request)
            
            // Parse response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any] {
                
                let content = message["content"] as? String ?? ""
                
                // Parse tool calls if present
                var toolCalls: [AIMessage.ToolCall]? = nil
                if let rawToolCalls = message["tool_calls"] as? [[String: Any]] {
                    toolCalls = rawToolCalls.compactMap { toolCallDict in
                        guard let id = toolCallDict["id"] as? String,
                              let function = toolCallDict["function"] as? [String: Any],
                              let name = function["name"] as? String,
                              let argumentsStr = function["arguments"] as? String,
                              let argumentsData = Data(base64Encoded: argumentsStr),
                              let arguments = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] else {
                            return nil
                        }
                        
                        return AIMessage.ToolCall(
                            id: id,
                            name: name,
                            arguments: arguments
                        )
                    }
                }
                
                return (content, toolCalls)
            }
        } catch {
            lastError = error.localizedDescription
        }
        
        return ("Error communicating with AI", nil)
    }
    
    // MARK: - Tool Execution
    
    private func executeToolCall(_ toolCall: AIMessage.ToolCall) async -> String {
        // Check if confirmation is required
        if requireConfirmation && !autoExecuteTools {
            // In production, this would trigger a UI confirmation dialog
            return "Tool execution skipped (confirmation required)"
        }
        
        // Find the tool
        guard let tool = toolDiscovery.tool(named: toolCall.name) else {
            return "Error: Tool '\(toolCall.name)' not found"
        }
        
        do {
            // Execute the tool
            currentTask = "Executing \(toolCall.name)..."
            let result = try await toolDiscovery.executeTool(tool, arguments: toolCall.arguments)
            return result
        } catch {
            return "Error executing tool: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Response Processing
    
    private func extractThinking(from content: String) -> String? {
        let pattern = "<thinking>(.*?)</thinking>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return nil
        }
        
        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, range: range) else {
            return nil
        }
        
        let thinkingRange = Range(match.range(at: 1), in: content)!
        return String(content[thinkingRange])
    }
    
    private func cleanResponse(_ content: String) -> String {
        // Remove thinking tags and clean up the response
        var cleaned = content
        
        // Remove thinking tags
        let thinkingPattern = "<thinking>.*?</thinking>"
        if let regex = try? NSRegularExpression(pattern: thinkingPattern, options: .dotMatchesLineSeparators) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }
        
        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    private func calculateConfidence(iterations: Int, toolsUsed: Int) -> Double {
        // Simple confidence calculation based on complexity
        let baseConfidence = 0.95
        let iterationPenalty = Double(iterations - 1) * 0.05
        let toolBonus = min(Double(toolsUsed) * 0.02, 0.1)
        
        return min(max(baseConfidence - iterationPenalty + toolBonus, 0.0), 1.0)
    }
    
    // MARK: - Configuration
    
    public func setModel(_ model: String) {
        currentModel = model
    }
    
    public func setAutoExecuteTools(_ enabled: Bool) {
        autoExecuteTools = enabled
    }
    
    public func setRequireConfirmation(_ required: Bool) {
        requireConfirmation = required
    }
    
    // MARK: - History Management
    
    public func clearHistory() {
        conversationHistory.removeAll()
        setupSystemPrompt()
    }
    
    public func exportHistory() -> String {
        return conversationHistory.map { message in
            "\(message.role.rawValue.uppercased()): \(message.content)"
        }.joined(separator: "\n\n")
    }
    
    // MARK: - Streaming Support
    
    /// Process a message with streaming response
    public func streamMessage(_ content: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                // Add user message
                let userMessage = AIMessage(
                    role: .user,
                    content: content,
                    toolCalls: nil,
                    toolCallId: nil
                )
                conversationHistory.append(userMessage)
                
                // Stream tokens (simplified version)
                let response = await processMessage(content)
                
                // Simulate streaming by sending chunks
                let chunks = response.content.split(separator: " ")
                for chunk in chunks {
                    continuation.yield(String(chunk) + " ")
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
                }
                
                continuation.finish()
            }
        }
    }
}

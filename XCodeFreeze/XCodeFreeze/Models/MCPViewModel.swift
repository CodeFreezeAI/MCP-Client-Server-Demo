//
//  MCPViewModel.swift
//  XCodeFreeze
//
//  Created by Todd Bruss on 5/14/25.
//

import SwiftUI
import MCP
import Logging
import Foundation
import AppKit
import System

// MARK: - View Model
class MCPViewModel: ObservableObject, ClientServerServiceMessageHandler {
    @Published var messages: [ChatMessage] = []
    @Published var isConnected = false
    @Published var statusMessage = "Initializing..."
    @Published var availableTools: [MCPTool] = []
    @Published var serverSubtools: [String] = []
    @Published var isAIProcessing = false
    
    // AI Service integration - accessed via MainActor
    
    // Use lazy initialization to avoid self being used before fully initialized
    private lazy var clientServerService: ClientServerService = {
        return ClientServerService(messageHandler: self)
    }()
    
    // MARK: - Server Connection
    
    func startClientServer(configPath: String? = nil) async {
        // Delegate to service
        await clientServerService.startClientServer(configPath: configPath)
    }
    
    func callTool(name: String, text: String) async {
        // Delegate to service
        await clientServerService.callTool(name: name, text: text)
    }
    
    func stopClientServer() {
        Task {
            await clientServerService.stopClientServer()
            
            await MainActor.run {
                self.isConnected = false
                self.serverSubtools = []
            }
        }
    }
    
    // MARK: - ClientServerServiceMessageHandler Protocol Implementation
    
    func addMessage(content: String, isFromServer: Bool) async {
        await MainActor.run {
            // If it's a JSON-RPC message with direction indicators, override the sender label
            var sender = isFromServer ? "Server" : "You"
            
            // Check for JSON-RPC message direction indicators
            if content.contains("[→]") {
                // Right arrow indicates message coming from Client
                sender = "Client"
            } else if content.contains("[←]") {
                // Left arrow indicates message coming from Server
                sender = "Server"
            }
            
            let message = ChatMessage(
                sender: sender,
                content: content,
                timestamp: Date(),
                isFromServer: isFromServer
            )
            
            // Add the message to the messages array
            messages.append(message)
            
            // Check for subtool updates in server response messages
            if isFromServer && (content.contains("actions by typing") || content.contains("subtool") || 
                               content.contains("Available tools")) {
                updateServerSubtools()
            }
        }
    }
    
    func updateStatus(_ status: ClientServerStatus) async {
        await MainActor.run {
            statusMessage = status.description
            
            // Update connection status based on the status enum
            switch status {
            case .connected:
                isConnected = true
                updateServerSubtools()
            case .disconnected, .error:
                isConnected = false
                serverSubtools = []
            case .connecting:
                // Keep previous connection state during reconnection attempts
                break
            }
        }
    }
    
    func updateTools(_ tools: [MCPTool]) async {
        await MainActor.run {
            availableTools = tools
            // Update subtools whenever tools are updated
            updateServerSubtools()
        }
    }
    
    // MARK: - Debug Features
    
    // Public method to add an informational message
    func addInfoMessage(_ content: String) {
        Task {
            await addMessage(content: content, isFromServer: true)
        }
    }
    
    // Debug feature to test and diagnose connection
    func getDiagnostics() async {
        await clientServerService.getDiagnostics()
    }
    
    // Debug feature to send an echo request-response to test communication
    func startDebugMessageTest() async {
        await clientServerService.startDebugMessageTest()
    }
    
    // MARK: - AI Integration
    
    /// Send a message to the AI service with proper MCP integration
    func sendToAI(_ content: String, includeThinking: Bool = true) async {
        await MainActor.run {
            isAIProcessing = true
        }
        
        defer { 
            Task { @MainActor in
                isAIProcessing = false
            }
        }
        
        // Add user message to chat
        await addMessage(content: content, isFromServer: false)
        
        // FIRST: Check if USER is directly requesting a tool (like Cursor AI/Claude Code)
        let currentTools = await MainActor.run { availableTools }
        
        // Check for exact tool match OR tool command
        for tool in currentTools {
            let contentLower = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let toolLower = tool.name.lowercased()
            
            // Direct tool invocation patterns
            if contentLower == toolLower ||
               contentLower == "use \(toolLower)" ||
               contentLower == "use_\(toolLower)" ||
               contentLower.hasPrefix("\(toolLower) ") ||
               contentLower.hasPrefix("run \(toolLower)") ||
               contentLower.hasPrefix("execute \(toolLower)") ||
               contentLower.hasPrefix("call \(toolLower)") {
                
                // Extract parameters if any
                let params = extractParametersFromUserInput(content, toolName: tool.name)
                
                // Execute tool directly
                await addMessage(content: "🚀 Executing: \(tool.name) \(params)", isFromServer: true)
                await callTool(name: tool.name, text: params)
                return // Don't send to AI, we handled it directly
            }
        }
        
        // Send to AI service with available tools
        let aiService = await AIService.shared
        
        if let response = await aiService.sendMessage(content, includeThinking: includeThinking, availableTools: currentTools) {
            // Determine sender name based on selected model
            let senderName: String
            if let selectedModel = await aiService.selectedModel {
                senderName = await aiService.getModelDisplayName(selectedModel)
            } else {
                senderName = "AI"
            }
            
            // Check if AI is suggesting tool usage
            let (finalResponse, shouldExecuteTools) = await parseAIResponseForToolSuggestions(response)
            
            // Add AI response to chat
            let aiMessage = ChatMessage(
                sender: senderName,
                content: finalResponse,
                timestamp: Date(),
                isFromServer: false
            )
            
            await MainActor.run {
                messages.append(aiMessage)
            }
            
            // If AI suggested tools, execute them and continue the conversation
            if shouldExecuteTools {
                await executeToolsFromAISuggestion(finalResponse, senderName: senderName)
            }
            
        } else {
            await addMessage(content: "❌ Failed to get response from AI", isFromServer: true)
        }
    }
    
    /// Initialize AI service and fetch models
    func initializeAI() async {
        let aiService = await AIService.shared
        await aiService.fetchAvailableModels()
        
        // Set up MCP tool executor callback
        await aiService.setMCPToolExecutor { [weak self] toolName, arguments in
            guard let self = self else { return nil }
            
            // Use ToolDiscoveryService to execute the tool and get the result
            if case let toolDiscovery = self.clientServerService.getToolDiscoveryService() {
                return await toolDiscovery.callTool(name: toolName, text: arguments)
            } else {
                return "Error: Tool discovery service not available"
            }
        }
    }
    
    // MARK: - MCP Integration Helpers
    
    /// Parse AI response for tool suggestions using patterns
    private func parseAIResponseForToolSuggestions(_ response: String) async -> (String, Bool) {
        // AGGRESSIVE CURSOR AI / CLAUDE CODE MODE - Execute tools automatically!
        let toolTriggerPatterns = [
            // Explicit mentions
            "let me", "i'll", "i will", "using",
            "need to", "going to", "want to",
            "should", "would", "could",
            "let's", "checking", "looking",
            "examining", "analyzing", "reading",
            "opening", "viewing", "listing",
            // Action words
            "execute", "fetch", "retrieve", "access",
            "examine", "check", "read", "analyze",
            "look at", "see", "show", "view",
            // Tool-specific triggers
            "file", "project", "code", "directory",
            "folder", "document", "analyze", "help"
        ]
        
        let lowerResponse = response.lowercased()
        
        // Check if ANY tool is mentioned in the response
        let currentTools = await MainActor.run { availableTools }
        let mentionsAnyTool = currentTools.contains { tool in
            // Check for tool name or common variations
            let toolLower = tool.name.lowercased()
            return lowerResponse.contains(toolLower) ||
                   lowerResponse.contains(toolLower.replacingOccurrences(of: "_", with: " "))
        }
        
        // Check for trigger patterns
        let containsToolTrigger = toolTriggerPatterns.contains { pattern in
            lowerResponse.contains(pattern)
        }
        
        // DISABLE aggressive mode - it's executing wrong tools!
        // Only execute if AI EXPLICITLY says it will use a tool
        let shouldExecute = false  // DISABLED - let the AI decide via tool_calls!
        
        return (response, shouldExecute)
    }
    
    /// Execute tools based on AI suggestions
    private func executeToolsFromAISuggestion(_ aiResponse: String, senderName: String) async {
        // INTELLIGENT parameter extraction from AI response
        let currentTools = await MainActor.run { availableTools }
        let lowerResponse = aiResponse.lowercased()
        
        // Execute ALL mentioned tools (like Cursor AI does)
        var toolsExecuted = 0
        
        for tool in currentTools {
            let toolNameLower = tool.name.lowercased()
            let toolNameSpaced = toolNameLower.replacingOccurrences(of: "_", with: " ")
            
            if lowerResponse.contains(toolNameLower) || lowerResponse.contains(toolNameSpaced) {
                // Extract parameters intelligently from the AI response
                let parameters = extractParametersForTool(tool: tool, from: aiResponse)
                
                // Show what we're executing with parameters
                let execMsg = parameters.isEmpty ? 
                    "🔧 Executing: \(tool.name)" : 
                    "🔧 Executing: \(tool.name) \(parameters)"
                await addMessage(content: execMsg, isFromServer: true)
                
                // Execute the MCP tool
                let toolDiscovery = clientServerService.getToolDiscoveryService()
                if let toolResult = await toolDiscovery.callTool(name: tool.name, text: parameters) {
                    // Add result to chat
                    await addMessage(content: toolResult, isFromServer: true)
                    toolsExecuted += 1
                    
                    // If we executed tools, send combined results back to AI
                    if toolsExecuted == 1 {
                        // For first tool, send result back to AI for analysis
                        await sendToolResultToAI(toolResult: toolResult, toolName: tool.name, senderName: senderName)
                    }
                } else {
                    await addMessage(content: "❌ Failed to execute: \(tool.name)", isFromServer: true)
                }
            }
        }
        
        if toolsExecuted == 0 {
            // No specific tools found, but AI mentioned tool-like actions
            // Try to be smart about what they want
            await addMessage(content: "ℹ️ No specific tools identified. Please specify which tool to use.", isFromServer: true)
        }
    }
    
    /// Extract parameters from user's direct input
    private func extractParametersFromUserInput(_ input: String, toolName: String) -> String {
        let toolLower = toolName.lowercased()
        let inputLower = input.lowercased()
        
        // Remove the tool name and common prefixes
        var params = input
        let prefixes = [
            "\(toolName) ", "use \(toolName) ", "use_\(toolName) ",
            "run \(toolName) ", "execute \(toolName) ", "call \(toolName) ",
            "\(toolLower) ", "use \(toolLower) ", "use_\(toolLower) ",
            "run \(toolLower) ", "execute \(toolLower) ", "call \(toolLower) "
        ]
        
        for prefix in prefixes {
            if inputLower.hasPrefix(prefix) {
                params = String(input.dropFirst(prefix.count))
                break
            }
        }
        
        // If we stripped everything, return empty
        if params == toolName || params == toolLower {
            return ""
        }
        
        return params.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Extract parameters for a tool from AI response text
    private func extractParametersForTool(tool: MCPTool, from response: String) -> String {
        // Look for common parameter patterns in the response
        
        // Check for file paths (common for read_file, open_doc, etc.)
        let filePathPattern = #"[\/\w\-\.]+\.(swift|json|plist|txt|md|h|m|mm|cpp|c|js|ts|py|rb|go|rs|xml|html|css)"#
        if let regex = try? NSRegularExpression(pattern: filePathPattern, options: .caseInsensitive) {
            let range = NSRange(response.startIndex..., in: response)
            if let match = regex.firstMatch(in: response, range: range) {
                return String(response[Range(match.range, in: response)!])
            }
        }
        
        // Check for quoted strings (often parameters)
        if response.contains("\"") {
            let components = response.components(separatedBy: "\"")
            if components.count >= 3 {
                return components[1] // Return first quoted string
            }
        }
        
        // Check for directory paths
        if tool.name.contains("dir") || tool.name.contains("folder") {
            let dirPattern = #"[\/\w\-\.]+"#
            if let regex = try? NSRegularExpression(pattern: dirPattern) {
                let range = NSRange(response.startIndex..., in: response)
                if let match = regex.firstMatch(in: response, range: range) {
                    let path = String(response[Range(match.range, in: response)!])
                    if path.hasPrefix("/") {
                        return path
                    }
                }
            }
        }
        
        // Check for numbers (for select_project, line numbers, etc.)
        if tool.name.contains("select") || tool.name.contains("line") {
            let numberPattern = #"\d+"#
            if let regex = try? NSRegularExpression(pattern: numberPattern) {
                let range = NSRange(response.startIndex..., in: response)
                if let match = regex.firstMatch(in: response, range: range) {
                    return String(response[Range(match.range, in: response)!])
                }
            }
        }
        
        // No parameters found
        return ""
    }
    
    /// Send MCP tool results back to AI for processing and response
    private func sendToolResultToAI(toolResult: String, toolName: String, senderName: String) async {
        // Create a context message for the AI about the tool execution
        let contextMessage = """
        Tool execution result for \(toolName):

        \(toolResult)

        Based on this data and our conversation, please provide a helpful response to the user.
        """
        
        // Add the tool result as a system/tool message to maintain conversation context
        // This ensures the AI remembers the full conversation when processing the result
        let aiService = await AIService.shared
        
        // Add tool execution message to AI's conversation history
        let toolResultMessage = ChatCompletionMessage(role: "system", content: contextMessage)
        await MainActor.run {
            // Add to AI service conversation history so it remembers context
            aiService.conversationHistory.append(toolResultMessage)
        }
        
        // Now ask AI to respond based on the tool result and conversation history
        let currentTools = await MainActor.run { availableTools }
        let followUpMessage = "Please respond to the user based on the tool execution results above."
        
        if await aiService.sendMessage(followUpMessage, includeThinking: false, availableTools: currentTools) != nil {
            // The AI response is already added to chat by sendMessage, so we don't need to add it again
            // Just log success
            print("AI processed tool result successfully")
        } else {
            // Fallback: show raw results if AI fails
            await addMessage(content: "Tool result: \(toolResult)", isFromServer: true)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Updates the server subtools array from the ToolRegistry
    @MainActor private func updateServerSubtools() {
        if let subtools = ToolRegistry.shared.getSubTools(for: MCP_SERVER_NAME) {
            // Only update if there's a change to avoid unnecessary UI updates
            if Set(subtools) != Set(serverSubtools) {
                serverSubtools = subtools
            }
        }
    }
}

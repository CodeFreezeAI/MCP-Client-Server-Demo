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
        
        // Send to AI service with available tools
        let aiService = await AIService.shared
        let currentTools = await MainActor.run { availableTools }
        
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
    }
    
    // MARK: - MCP Integration Helpers
    
    /// Parse AI response for tool suggestions using patterns
    private func parseAIResponseForToolSuggestions(_ response: String) async -> (String, Bool) {
        // Only execute tools if AI explicitly says it will use a tool
        let explicitToolPatterns = [
            "let me use the",
            "i'll use the", 
            "i will use the",
            "let me run",
            "i'll run",
            "i will run"
        ]
        
        let lowerResponse = response.lowercased()
        let containsExplicitToolRequest = explicitToolPatterns.contains { pattern in
            lowerResponse.contains(pattern)
        }
        
        // DISABLED: Don't auto-execute based on tool name mentions alone
        // This was too aggressive and executed tools when AI was just discussing them
        
        return (response, containsExplicitToolRequest)
    }
    
    /// Execute tools based on AI suggestions
    private func executeToolsFromAISuggestion(_ aiResponse: String, senderName: String) async {
        // Simple pattern matching to extract tool commands from AI response
        let currentTools = await MainActor.run { availableTools }
        
        for tool in currentTools {
            if aiResponse.lowercased().contains(tool.name.lowercased()) {
                // Show what we're about to execute
                await addMessage(content: "🔧 Executing: \(tool.name)", isFromServer: true)
                
                // Execute the MCP tool
                await callTool(name: tool.name, text: "")
                
                // Note: In a more sophisticated implementation, we would:
                // 1. Parse the AI response for specific arguments
                // 2. Extract parameters for the tool call
                // 3. Handle multiple tool calls
                // 4. Send results back to AI for further processing
                
                break // Execute only first found tool for now
            }
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

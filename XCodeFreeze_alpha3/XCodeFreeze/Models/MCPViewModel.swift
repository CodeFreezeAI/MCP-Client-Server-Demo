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
    
    func updateStatus(_ status: String) async {
        await MainActor.run {
            statusMessage = status
            
            // Update connection status based on the message
            isConnected = !status.lowercased().contains("error") && 
                          !status.lowercased().contains("disconnect")
            
            // Update subtools when connection status changes
            if isConnected {
                updateServerSubtools()
            } else {
                serverSubtools = []
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

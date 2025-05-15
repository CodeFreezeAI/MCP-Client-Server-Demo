
import SwiftUI
import MCP
import Logging
import Foundation
import AppKit
import System

// MARK: - View Model
class MCPViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isConnected = false
    @Published var statusMessage = "Initializing..."
    @Published var availableTools: [MCPTool] = []
    
    private var serviceManager: MCPServiceManager
    
    init() {
        // First initialize the service manager with empty callbacks
        serviceManager = MCPServiceManager(
            statusCallback: { _ in },
            messageCallback: { _, _ in }
        )
        
        // Then update the callbacks after serviceManager has been initialized
        serviceManager.statusCallback = { [weak self] status in
            Task { @MainActor in
                self?.statusMessage = status
            }
        }
        
        serviceManager.messageCallback = { [weak self] content, isFromServer in
            Task { @MainActor in
                self?.addMessage(content: content, isFromServer: isFromServer)
            }
        }
        
        // Override the connection established method to update view model state
        serviceManager.onConnectionEstablished = { [weak self] tools in
            Task { @MainActor in
                self?.isConnected = true
                self?.availableTools = tools
            }
        }
    }
    
    // MARK: - Public Methods
    
    func startClientServer(configPath: String? = nil) async {
        await serviceManager.startServer(configPath: configPath)
    }
    
    func stopClientServer() {
        serviceManager.stopServer()
        
        Task { @MainActor in
            self.isConnected = false
            self.statusMessage = "Disconnected"
        }
    }
    
    func callTool(name: String, text: String) async {
        await serviceManager.callTool(name: name, text: text)
    }
    
    func getDiagnostics() async {
        await serviceManager.getDiagnostics()
    }
    
    func startDebugMessageTest() async {
        await serviceManager.startDebugMessageTest()
    }
    
    // Public method to add an informational message
    func addInfoMessage(_ content: String) {
        Task {
            await addMessage(content: content, isFromServer: true)
        }
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func addMessage(content: String, isFromServer: Bool) {
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
        
        // Force UI update by reassigning to trigger change notifications
        let currentMessages = messages
        messages = currentMessages
    }
}

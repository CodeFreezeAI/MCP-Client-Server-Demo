import Foundation
import MCP
import Logging
import System
import SwiftUI

// MARK: - Client Server Status
enum ClientServerStatus {
    case disconnected
    case connecting
    case connected(serverName: String, version: String)
    case error(message: String)
    
    var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected(let serverName, let version):
            return "Connected to: \(serverName) v\(version)"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

// MARK: - Content Type for JSON Serialization
enum ContentType {
    case text(value: String)
    case image(data: String = "<binary data>")
    case audio(data: String = "<binary data>")
    case resource(uri: String)
    case unknown(value: String = "<unknown content type>")
    
    func toJSONString(indentLevel: Int = 1) -> String {
        let indent = String(repeating: "  ", count: indentLevel)
        let result = """
        \(indent){
        \(indent)  "type": "\(typeString)",
        \(indent)  \(valueField)
        \(indent)}
        """
        return result
    }
    
    private var typeString: String {
        switch self {
        case .text: return "text"
        case .image: return "image"
        case .audio: return "audio"
        case .resource: return "resource"
        case .unknown: return "unknown"
        }
    }
    
    private var valueField: String {
        switch self {
        case .text(let value):
            return "\"value\": \"\(value)\""
        case .image(let data):
            return "\"data\": \"\(data)\""
        case .audio(let data):
            return "\"data\": \"\(data)\""
        case .resource(let uri):
            return "\"uri\": \"\(uri)\""
        case .unknown(let value):
            return "\"value\": \"\(value)\""
        }
    }
}

// MARK: - Tool JSON Serialization
enum ToolJSON {
    case tool(name: String, description: String, schema: String?)
    
    func toJSONString(indentLevel: Int = 1) -> String {
        let indent = String(repeating: "  ", count: indentLevel)
        var result = """
        \(indent){
        \(indent)  "name": "\(name)",
        \(indent)  "description": "\(description)"
        """
        
        if let schema = schema {
            result += ",\n\(indent)  \"inputSchema\": \(schema)"
        }
        
        result += "\n\(indent)}"
        return result
    }
    
    private var name: String {
        switch self {
        case .tool(let name, _, _):
            return name
        }
    }
    
    private var description: String {
        switch self {
        case .tool(_, let description, _):
            return description
        }
    }
    
    private var schema: String? {
        switch self {
        case .tool(_, _, let schema):
            return schema
        }
    }
}

// MARK: - Client Server Service Message Handler
protocol ClientServerServiceMessageHandler: AnyObject {
    func addMessage(content: String, isFromServer: Bool) async
    func updateStatus(_ status: ClientServerStatus) async
    func updateTools(_ tools: [MCPTool]) async
}

// MARK: - Client Server Service
class ClientServerService {
    private var client: Client?
    private let transportService = TransportService()
    private let toolDiscoveryService = ToolDiscoveryService()
    private weak var messageHandler: ClientServerServiceMessageHandler?
    
    var isConnected: Bool {
        return client != nil
    }
    
    init(messageHandler: ClientServerServiceMessageHandler) {
        self.messageHandler = messageHandler
        // Set the client in tool discovery service when it's available
        toolDiscoveryService.setClientProvider { [weak self] in
            return self?.client
        }
    }
    
    // Message formatting is now handled by MessageFormatService
    private let formatter = MessageFormatService.shared
    private let logger = LoggingService.shared
    
    // MARK: - Server Connection
    
    func startClientServer(configPath: String? = nil) async {
        logger.info("Starting XCodeFreeze Client...")
        await messageHandler?.addMessage(content: formatter.formatSystemMessage("Starting XCodeFreeze Client..."), isFromServer: true)
        
        if let customPath = configPath, !customPath.isEmpty {
            logger.info("Using custom config file: \(customPath)")
            await messageHandler?.addMessage(content: formatter.formatSystemMessage("Using custom config file: \(customPath)"), isFromServer: true)
        }
        
        await messageHandler?.updateStatus(.connecting)
        
        // Start server and get transport
        transportService.startServer(configPath: configPath ?? "") { [weak self] result in
            guard let self = self else { return }
            
            Task {
                switch result {
                case .success(let (transport, _)):
                    await self.messageHandler?.updateStatus(.connecting)
                    await self.messageHandler?.addMessage(content: "Found \(MCP_SERVER_NAME) server configuration", isFromServer: true)
                    
                    // Create client with default version
                    let originalClient = Client(name: MCP_CLIENT_NAME, version: MCP_CLIENT_DEFAULT_VERSION)
                    self.client = originalClient
                    
                    LoggingService.shared.info(String(format: MCPConstants.Messages.ClientServer.attemptingToConnect, MCPConstants.Server.name))
                    
                    // Connect the transport first
                    do {
                        try await transport.connect()
                        LoggingService.shared.info(MCPConstants.Messages.ClientServer.transportConnected)
                        
                        // Test the transport connection with a ping message
                        let _ = try await self.transportService.testTransport()
                        
                        // Now connect the client using the transport
                        try await self.client?.connect(transport: transport)
                        LoggingService.shared.info(String(format: MCPConstants.Messages.ClientServer.clientConnected, MCPConstants.Server.name))
                        
                        // Initialize connection
                        await self.initializeClient()
                    } catch {
                        LoggingService.shared.error(String(format: MCPConstants.Messages.ClientServer.connectionFailed, MCPConstants.Server.name, error.localizedDescription))
                        
                        let errorMsg = "Error connecting to \(MCP_SERVER_NAME) server: \(error.localizedDescription)"
                        self.logger.error(errorMsg)
                        await self.messageHandler?.updateStatus(.error(message: errorMsg))
                        await self.messageHandler?.addMessage(content: self.formatter.formatErrorMessage(errorMsg), isFromServer: true)
                        
                        // Clean up server process
                        self.transportService.stopServer()
                        self.client = nil
                    }
                    
                case .failure(let error):
                    await self.messageHandler?.updateStatus(.error(message: error.localizedDescription))
                    await self.messageHandler?.addMessage(content: "Error: \(error.localizedDescription)", isFromServer: true)
                }
            }
        }
    }
    
    // MARK: - Client Initialization
    
    private func initializeClient() async {
        // Add JSON-RPC debug message for initialize
        await messageHandler?.addMessage(content: "[→] JSON-RPC: initialize(clientName: \"\(MCP_CLIENT_NAME)\", version: \"\(MCP_CLIENT_DEFAULT_VERSION)\")", isFromServer: true)
        
        // Initialize connection
        guard let client = self.client else {
            await messageHandler?.updateStatus(.error(message: "Client was not created properly"))
            await messageHandler?.addMessage(content: "Error: Failed to create client object", isFromServer: true)
            return
        }
        
        do {
            let result = try await client.initialize()
            
            // Capture server version for future use
            let serverVersion = result.serverInfo.version
            let serverName = result.serverInfo.name
            
            // Add JSON-RPC debug response
            await messageHandler?.addMessage(content: "[←] JSON-RPC Response: { \"serverInfo\": { \"name\": \"\(serverName)\", \"version\": \"\(serverVersion)\" } }", isFromServer: true)
            
            // Update the MCP_SERVER_NAME based on the actual server name from the response
            // This ensures we use the actual server name rather than the configured one
            if !serverName.isEmpty {
                // Special case for NPX filesystem server
                if serverName.lowercased() == "filesystem" && MCPConstants.Server.name.lowercased() != "filesystem" {
                    await messageHandler?.addMessage(content: String(format: MCPConstants.Messages.ClientServer.connectedToNPXFilesystem, MCPConstants.Server.name), isFromServer: true)
                    // Don't update the server name in this case to maintain compatibility
                } else {
                    MCPConstants.Server.name = serverName
                    LoggingService.shared.info(String(format: MCPConstants.Messages.ClientServer.settingServerName, serverName))
                }
            }
            
            await messageHandler?.updateStatus(.connected(serverName: serverName, version: serverVersion))
            await messageHandler?.addMessage(content: String(format: MCPConstants.Messages.Info.connectedToServer, serverName, serverVersion), isFromServer: true)
            
            // Add JSON-RPC debug message for listTools
            await messageHandler?.addMessage(content: "[→] JSON-RPC: listTools()", isFromServer: true)
            
            // List available tools
            let toolsResponse = try await client.listTools()
            
            // Format tools for debug display using JSONFormatter
            let toolsJson = JSONFormatter.formatArray(toolsResponse.tools) { tool in
                // Try to extract schema if available
                var schemaString: String? = nil
                if let inputSchema = tool.inputSchema, 
                   let objectValue = inputSchema.objectValue {
                    schemaString = objectValue.description
                    
                    // Attempt to extract parameter information from the schema
                    Task {
                        await self.toolDiscoveryService.extractParametersFromSchema(toolName: tool.name, schema: inputSchema)
                    }
                }
                
                let toolJSON = ToolJSON.tool(
                    name: tool.name,
                    description: tool.description,
                    schema: schemaString
                )
                return toolJSON.toJSONString()
            }
            
            // Add JSON-RPC debug response for tools
            await messageHandler?.addMessage(content: "[←] JSON-RPC Response: { \"tools\": \(toolsJson) }", isFromServer: true)
            
            // Convert to MCPTool models
            let tools = toolsResponse.tools.map {
                MCPTool(name: $0.name, description: $0.description)
            }
            
            // Update the tools in the UI
            await messageHandler?.updateTools(tools)
            
            // Register tools with the registry
            ToolRegistry.shared.registerTools(tools)
            
            await messageHandler?.addMessage(content: "Available tools: \(toolsResponse.tools.map { $0.name }.joined(separator: ", "))", isFromServer: true)
            
            // Automatically discover available tools and parameters
            await toolDiscoveryService.discoverToolsAndParameters()
            
            // Update available tools from registry after discovery
            let updatedTools = ToolRegistry.shared.getAvailableTools()
            await messageHandler?.updateTools(updatedTools)
            
            // If we found any server actions, let the user know they can use them
            if let serverActions = ToolRegistry.shared.getSubTools(for: MCP_SERVER_NAME), !serverActions.isEmpty {
                // Get the parameter name from the server's schema instead of hardcoding "action"
                let paramName = ToolRegistry.shared.getParameterName(for: MCP_SERVER_NAME)
                await messageHandler?.addMessage(content: String(format: MCPConstants.Messages.ClientServer.availableServerActions, MCPConstants.Server.name, MCPConstants.Server.name, paramName, paramName), isFromServer: true)
            }
            
        } catch {
            await messageHandler?.updateStatus(.error(message: String(format: MCPConstants.Messages.Errors.initializationError, error.localizedDescription)))
            await messageHandler?.addMessage(content: String(format: MCPConstants.Messages.Errors.initializationError, error.localizedDescription), isFromServer: true)
        }
    }
    
    // MARK: - Tool Calling
    
    func callTool(name: String, text: String) async {
        // Display the full command in the chat
        let displayText = text.isEmpty ? name : "\(name) \(text)"
        await messageHandler?.addMessage(content: displayText, isFromServer: false)
        
        guard let client = client, isConnected else {
            await messageHandler?.addMessage(content: MCPConstants.Messages.Errors.clientNotConnected, isFromServer: true)
            return
        }
        
        // Get the appropriate parameter name for this tool
        let argumentName = ToolRegistry.shared.getParameterName(for: name)
        let argumentValue = text
        
        // Add JSON-RPC debug message with the appropriate parameter name
        let paramSourceInfo = ToolRegistry.shared.getParameterSource(for: name)
        let callToolJson = """
        [→] JSON-RPC: callTool(
          "name": "\(name)",
          "arguments": {
            "\(argumentName)": "\(argumentValue)" \(paramSourceInfo)
          }
        )
        """
        await messageHandler?.addMessage(content: callToolJson, isFromServer: true)
        
        // For debugging, occasionally send the raw request for demonstration
        if Bool.random() { // Only do this occasionally to avoid duplication
            // Use JSONFormatter to create a properly formatted JSON-RPC request
            let id = UUID().uuidString
            let requestObj: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "method": "callTool",
                "params": [
                    "name": name,
                    "arguments": [
                        argumentName: argumentValue
                    ]
                ]
            ]
            
            let rawRequest = JSONFormatter.buildObject(requestObj)
            
            do {
                try await transportService.sendRawMessage(rawRequest)
            } catch {
                LoggingService.shared.error(String(format: MCPConstants.Messages.ClientServer.sendRawMsgFailed, error.localizedDescription))
                // Continue execution - this is just a debug feature
            }
        }
        
        do {
            // Call the tool with the appropriate parameter name
            let (content, isError) = try await client.callTool(
                name: name,
                arguments: [(argumentName): .string(argumentValue)]
            )
            
            // Format content for debug display using JSONFormatter
            let contentJson = JSONFormatter.formatArray(content) { item in
                let contentType: ContentType
                switch item {
                case .text(let textContent):
                    contentType = .text(value: textContent)
                case .image(data: _, mimeType: _, metadata: _):
                    contentType = .image()
                case .audio(data: _, mimeType: _):
                    contentType = .audio()
                case .resource(uri: let uri, mimeType: _, text: _):
                    contentType = .resource(uri: uri)
                @unknown default:
                    contentType = .unknown()
                }
                return contentType.toJSONString()
            }
            
            // Add JSON-RPC debug response
            let responseJson = """
            [←] JSON-RPC Response: {
              "content": \(contentJson),
              "isError": \(isError == true)
            }
            """
            await messageHandler?.addMessage(content: responseJson, isFromServer: true)
            
            // Process response
            if isError == true {
                await messageHandler?.addMessage(content: MCPConstants.Messages.Errors.errorFromServer, isFromServer: true)
                return
            }
            
            // Extract text response
            for item in content {
                if case .text(let responseText) = item {
                    await messageHandler?.addMessage(content: String(format: MCPConstants.Messages.Info.serverResponse, responseText), isFromServer: true)
                    
                    //MARK: - Subtools offline If this was the help command or list tools command, update available tools
//                    if name == MCPConstants.Commands.serverPrefixedCommand(MCPConstants.Commands.help) || name == MCPConstants.Commands.help ||
//                       name == MCPConstants.Commands.serverPrefixedCommand(MCPConstants.Commands.list) || name == MCPConstants.Commands.list {
//                        // Process tool/help output to ensure subtools are updated immediately
//                        if name.contains(MCPConstants.Commands.help) {
//                            await toolDiscoveryService.processHelpOutput(responseText)
//                        } else if name.contains(MCPConstants.Commands.list) {
//                            await toolDiscoveryService.processToolList(responseText)
//                        }
//                       
//                        // Update available tools from registry after discovery
//                        let updatedTools = ToolRegistry.shared.getAvailableTools()
//                        await messageHandler?.updateTools(updatedTools)
//                    }
                    
                    return
                }
            }
        } catch {
            await messageHandler?.addMessage(content: "Error: \(error.localizedDescription)", isFromServer: true)
        }
    }
    
    // MARK: - Stop Client Server
    
    func stopClientServer() async {
        // Disconnect client first
        if let client = client {
            await client.disconnect()
        }
        
        // Clean up client reference
        self.client = nil
        
        // Stop the server via the service
        transportService.stopServer()
        
        await messageHandler?.updateStatus(.disconnected)
    }
    
    // MARK: - Diagnostic Methods
    
    // Debug feature to test and diagnose connection
    func getDiagnostics() async {
        guard isConnected else {
            await messageHandler?.addMessage(content: "[DIAGNOSTICS] Client is not connected", isFromServer: true)
            return
        }
        
        await messageHandler?.addMessage(content: "[DIAGNOSTICS] Checking client-server connection...", isFromServer: true)
        
        // Check client
        if let client = client {
            await messageHandler?.addMessage(content: "[DIAGNOSTICS] Client exists (\(client.name) v\(client.version))", isFromServer: true)
        } else {
            await messageHandler?.addMessage(content: "[DIAGNOSTICS] Client is nil", isFromServer: true)
        }
        
        // Check available tools
        let toolCount = ToolRegistry.shared.getAvailableTools().count
        await messageHandler?.addMessage(content: "[DIAGNOSTICS] Available tools: \(toolCount)", isFromServer: true)
        
        // Test client with a ping if available
        if let client = client {
            await messageHandler?.addMessage(content: "[DIAGNOSTICS] Testing client with ping...", isFromServer: true)
            do {
                _ = try await client.ping()
                await messageHandler?.addMessage(content: "[DIAGNOSTICS] Ping successful", isFromServer: true)
            } catch {
                await messageHandler?.addMessage(content: "[DIAGNOSTICS] Ping failed: \(error.localizedDescription)", isFromServer: true)
            }
        }
    }
    
    // Debug feature to send an echo request-response to test communication
    func startDebugMessageTest() async {
        guard let client = client, isConnected else {
            await messageHandler?.addMessage(content: MCPConstants.Messages.Errors.clientNotConnected, isFromServer: true)
            return
        }
        
        await messageHandler?.addMessage(content: "[DEBUG] Sending ping message to test communication", isFromServer: true)
        
        // Add JSON-RPC debug message
        await messageHandler?.addMessage(content: "[→] JSON-RPC: ping()", isFromServer: true)
        
        do {
            // Send ping request to test the transport
            _ = try await client.ping()
            
            // Success response
            await messageHandler?.addMessage(content: "[←] JSON-RPC Response: { \"result\": {} }", isFromServer: true)
            await messageHandler?.addMessage(content: "[DEBUG] Ping successful! Communication with server is working.", isFromServer: true)
        } catch {
            await messageHandler?.addMessage(content: "[DEBUG] Error during ping test: \(error.localizedDescription)", isFromServer: true)
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Ensure server process is terminated
        transportService.stopServer()
    }
} 

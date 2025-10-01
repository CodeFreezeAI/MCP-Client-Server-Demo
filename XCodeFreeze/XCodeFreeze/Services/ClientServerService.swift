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
    
    func getToolDiscoveryService() -> ToolDiscoveryService {
        return toolDiscoveryService
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
        await messageHandler?.addMessage(content: formatter.formatSystemMessage("Starting XCodeFreeze Client..."), isFromServer: true)
        
        if let customPath = configPath, !customPath.isEmpty {
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
                    
                    // Connection status shown via UI messages
                    
                    // Connect the transport first
                    do {
                        try await transport.connect()
                        // Transport status shown via UI messages
                        
                        // Test the transport connection with a ping message
                        let _ = try await self.transportService.testTransport()
                        
                        // Now connect the client using the transport
                        try await self.client?.connect(transport: transport)
                        // Client connection status shown via UI messages
                        
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
    
    // MARK: - Helper Methods
    
    /// Check if a tool requires parameters based on its schema
    internal func toolNeedsParameters(toolName: String) -> Bool {
        guard let tool = ToolRegistry.shared.getAvailableTools().first(where: { $0.name == toolName }),
              let schema = tool.inputSchema else {
            // If no schema found, assume it needs parameters (safer default)
            return true
        }
        
        // Check if schema has properties or required fields
        let hasProperties = schema["properties"] != nil
        let hasRequired = schema["required"] != nil
        
        // If no properties and no required fields, the tool doesn't need parameters
        return hasProperties || hasRequired
    }
    
    /// Convert schema object to dictionary for easier access
    internal func convertSchemaToDict(_ objectValue: [String: Value]) -> [String: Any] {
        // Convert Value objects to their actual values recursively
        var result: [String: Any] = [:]
        
        for (key, value) in objectValue {
            result[key] = convertValueToAny(value)
        }
        
        return result
    }
    
    /// Convert a Value enum to a plain Swift type
    internal func convertValueToAny(_ value: Value) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .int(let i):
            return i
        case .double(let d):
            return d
        case .string(let s):
            return s
        case .data(_, let data):
            return data
        case .array(let arr):
            return arr.map { convertValueToAny($0) }
        case .object(let obj):
            var dict: [String: Any] = [:]
            for (key, val) in obj {
                dict[key] = convertValueToAny(val)
            }
            return dict
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
            // Note: initialize() is deprecated and happens automatically during connect()
            // Get server info from the connected client instead
            let serverName = "xcf" // Will be updated from actual server response
            let serverVersion = "unknown" // Will be updated from actual server response
            
            // Server info will be available after connection is established
            
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
                if case let inputSchema = tool.inputSchema,
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
            var tools: [MCPTool] = []
            for tool in toolsResponse.tools {
                // Extract inputSchema as dictionary
                var schemaDict: [String: Any]? = nil
                if case let inputSchema = tool.inputSchema,
                   let objectValue = inputSchema.objectValue {
                    // Convert the schema to a dictionary for easier access
                    schemaDict = convertSchemaToDict(objectValue)
                    print("DEBUG: Tool '\(tool.name)' has schema: \(objectValue)")
                } else {
                    print("DEBUG: Tool '\(tool.name)' has NO SCHEMA")
                }
                
                tools.append(MCPTool(name: tool.name, description: tool.description, inputSchema: schemaDict))
            }
            
            // Update the tools in the UI
            await messageHandler?.updateTools(tools)
            
            // Register tools with the registry
            ToolRegistry.shared.registerTools(tools)
            
            // Register parameter information from schemas  
            for tool in tools {
                if let schema = tool.inputSchema,
                   let properties = schema["properties"] as? [String: Any] {
                    // Extract parameter info from schema
                    var parameterInfos: [ToolParameterInfo] = []
                    let requiredParams = schema["required"] as? [String] ?? []
                    
                    for (paramName, paramDefinition) in properties {
                        if let paramDef = paramDefinition as? [String: Any] {
                            let type = paramDef["type"] as? String ?? "string"
                            let description = paramDef["description"] as? String
                            let isRequired = requiredParams.contains(paramName)
                            
                            parameterInfos.append(ToolParameterInfo(
                                name: paramName,
                                isRequired: isRequired,
                                type: type,
                                description: description
                            ))
                        }
                    }
                    
                    // Register the parameter info
                    ToolRegistry.shared.registerParameterInfo(for: tool.name, parameters: parameterInfos)
                    print("DEBUG: Registered \(parameterInfos.count) parameters for tool '\(tool.name)'")
                }
            }
            
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
        
        // Check if tool needs parameters
        let toolHasParameters = toolNeedsParameters(toolName: name)
        
        // Get parameter info only if tool needs parameters
        let argumentName: String
        let typedArgumentValue: Value
        
        if toolHasParameters {
            argumentName = ToolRegistry.shared.getParameterName(for: name)
            let argumentValue = text
            
            // Convert the argument value to the correct type
            typedArgumentValue = convertArgumentToCorrectType(
                value: argumentValue,
                for: name,
                parameter: argumentName
            )
        } else {
            // For tools with no parameters, use empty parameters
            argumentName = ""
            typedArgumentValue = .string("")
        }
        
        // Format the argument value for display
        let displayValue: String
        switch typedArgumentValue {
        case .int(let intVal):
            displayValue = "\(intVal)"
        case .bool(let boolVal):
            displayValue = "\(boolVal)"
        case .string(let stringVal):
            displayValue = "\"\(stringVal)\""
        default:
            displayValue = "\"\(typedArgumentValue)\""
        }
        
        // Add JSON-RPC debug message with the appropriate parameter name and type
        let paramSourceInfo = ToolRegistry.shared.getParameterSource(for: name)
        let callToolJson = """
        [→] JSON-RPC: callTool(
          "name": "\(name)",
          "arguments": {
            "\(argumentName)": \(displayValue) \(paramSourceInfo)
          }
        )
        """
        await messageHandler?.addMessage(content: callToolJson, isFromServer: true)
        
        // For debugging, occasionally send the raw request for demonstration
        if Bool.random() { // Only do this occasionally to avoid duplication
            // Use JSONFormatter to create a properly formatted JSON-RPC request
            let id = UUID().uuidString
            
            // Convert Value to the appropriate JSON type for display
            let jsonArgumentValue: Any
            switch typedArgumentValue {
            case .int(let intVal):
                jsonArgumentValue = intVal
            case .bool(let boolVal):
                jsonArgumentValue = boolVal
            case .string(let stringVal):
                jsonArgumentValue = stringVal
            default:
                jsonArgumentValue = "\(typedArgumentValue)"
            }
            
            let requestObj: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "method": "callTool",
                "params": [
                    "name": name,
                    "arguments": [
                        argumentName: jsonArgumentValue
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
            // Call the tool with appropriate arguments
            let (content, isError) = if toolHasParameters {
                // Call with parameters
                try await client.callTool(
                    name: name,
                    arguments: [(argumentName): typedArgumentValue]
                )
            } else {
                // Call with no parameters
                try await client.callTool(
                    name: name,
                    arguments: [:]
                )
            }
            
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
                    // Show the actual response from the server without wrapping
                    await messageHandler?.addMessage(content: responseText, isFromServer: true)
                    
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
    
    // MARK: - Argument Type Conversion
    
    /// Convert a string argument to the correct MCP Value type based on the tool's schema
    private func convertArgumentToCorrectType(value: String, for toolName: String, parameter parameterName: String) -> Value {
        print("DEBUG: Converting argument '\(value)' for tool '\(toolName)', parameter '\(parameterName)'")
        
        // Declare paramType at function scope
        var paramType: String? = nil
        
        // Get the tool's schema to determine the parameter type
        if let tool = ToolRegistry.shared.getAvailableTools().first(where: { $0.name == toolName }),
           let schema = tool.inputSchema {
            
            // Debug the schema structure
            print("DEBUG: Schema structure for tool '\(toolName)': \(schema)")
            print("DEBUG: Schema keys: \(schema.keys)")
            if let properties = schema["properties"] {
                print("DEBUG: Properties found: \(properties)")
            } else {
                print("DEBUG: No 'properties' key found in schema")
            }
            
            
            // Continue to detailed debug section if initial extraction failed
            if paramType == nil {
                print("DEBUG: Could not extract parameter type for '\(parameterName)' from schema - checking detailed debug info")
                
                // Handle the array of key-value pairs format: ["type": "integer", "description": "..."]
                print("DEBUG: Attempting to cast schema['properties'] as [String: Any]")
                
                // Handle MCP Value type properly
                if let propertiesValue = schema["properties"] as? Value,
                   let propertiesObj = propertiesValue.objectValue {
                    print("DEBUG: Successfully got MCP Value properties: \(propertiesObj)")
                    
                    if let paramInfoValue = propertiesObj[parameterName] {
                        print("DEBUG: Parameter info value type: \(type(of: paramInfoValue))")
                        print("DEBUG: Parameter info value: \(paramInfoValue)")
                        
                        if let paramInfoArray = paramInfoValue.arrayValue {
                            print("DEBUG: Got parameter info array: \(paramInfoArray)")
                            
                            // Look for "type" key and get the following value in MCP Value array
                            for i in 0..<paramInfoArray.count-1 {
                                if let key = paramInfoArray[i].stringValue, key == "type",
                                   let type = paramInfoArray[i+1].stringValue {
                                    paramType = type
                                    print("DEBUG: Found type '\(type)' for parameter '\(parameterName)' from MCP Value array format")
                                    break
                                }
                            }
                        } else if let paramInfoObj = paramInfoValue.objectValue,
                                  let typeValue = paramInfoObj["type"],
                                  let type = typeValue.stringValue {
                            paramType = type
                            print("DEBUG: Found type '\(type)' for parameter '\(parameterName)' from MCP Value object format")
                        } else {
                            print("DEBUG: Could not cast paramInfoValue to arrayValue or objectValue")
                        }
                    }
                } else {
                    print("DEBUG: Could not cast properties to MCP Value")
                }
            }
        } else {
            print("DEBUG: No schema found for tool '\(toolName)' - using string")
        }
        
        // Now check if we found a parameter type and convert accordingly
        if let type = paramType {
            switch type.lowercased() {
            case "integer":
                if let intValue = Int(value) {
                    print("DEBUG: Successfully converted '\(value)' to integer \(intValue)")
                    return .int(intValue)
                }
                // Fallback to string if conversion fails
                print("DEBUG: Failed to convert '\(value)' to integer, using string")
                return .string(value)
                
            case "number":
                if let doubleValue = Double(value) {
                    return .int(Int(doubleValue)) // MCP uses Int for numbers
                }
                // Fallback to string if conversion fails
                return .string(value)
                
            case "boolean":
                let lowerValue = value.lowercased()
                if lowerValue == "true" || lowerValue == "1" || lowerValue == "yes" {
                    return .bool(true)
                } else if lowerValue == "false" || lowerValue == "0" || lowerValue == "no" {
                    return .bool(false)
                }
                // Fallback to string if conversion fails
                return .string(value)
                
            default:
                // Default to string for unknown types or "string" type
                return .string(value)
            }
        }
        
        // Fallback to string if no schema information is available
        print("DEBUG: Falling back to string for '\(value)'")
        return .string(value)
    }
    
    deinit {
        // Ensure server process is terminated
        transportService.stopServer()
    }
} 

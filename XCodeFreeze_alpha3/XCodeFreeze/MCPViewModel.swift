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
class MCPViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isConnected = false
    @Published var statusMessage = "Initializing..."
    @Published var availableTools: [MCPTool] = []
    
    private var client: Client?
    private var serverProcess: Process?
    private var transport: StdioTransport?
    
    // MARK: - Server Connection
    
    func startClientServer(configPath: String? = nil) async {
        await addMessage(content: "Starting XCodeFreeze Client Demo...", isFromServer: true)
        
        if let customPath = configPath, !customPath.isEmpty {
            await addMessage(content: "Using custom config file: \(customPath)", isFromServer: true)
        }
        
        do {
            var clientCreated = false
            
            // First try to find configuration in the custom path
            do {
                let config = try MCPConfig.loadConfig(customPath: configPath)
                
                // Check if there's a server configured for our MCP_SERVER_NAME
                if let serverConfig = config.mcpServers[MCP_SERVER_NAME] {
                    // Get the server type (default to stdio if not specified)
                    let serverType = serverConfig.type ?? "stdio"
                    
                    // Only use external server if it's a stdio type
                    if serverType == "stdio" {
                        // Get the command and use it as the executable path
                        let executablePath = serverConfig.command
                        
                        // Get any additional arguments from the config
                        var arguments: [String] = []
                        if let configArgs = serverConfig.args {
                            arguments = configArgs
                        }
                        
                        await updateStatus("Found \(MCP_SERVER_NAME) server configuration")
                        await addMessage(content: "Found \(MCP_SERVER_NAME) server: \(executablePath)", isFromServer: true)
                        
                        print("Will use \(MCP_SERVER_NAME) server from config: \(executablePath)")
                        if !arguments.isEmpty {
                            print("With arguments: \(arguments.joined(separator: " "))")
                        }
                        
                        // Launch MCP server process
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: executablePath)
                        
                        // Set arguments from the config
                        process.arguments = arguments
                        
                        // Set environment variables if provided
                        if let env = serverConfig.env {
                            var currentEnv = ProcessInfo.processInfo.environment
                            for (key, value) in env {
                                currentEnv[key] = value
                            }
                            process.environment = currentEnv
                        }
                        
                        // Create pipes for bidirectional communication
                        let serverInput = Pipe()
                        let serverOutput = Pipe()
                        let serverError = Pipe()
                        
                        process.standardInput = serverInput
                        process.standardOutput = serverOutput
                        process.standardError = serverError
                        
                        // Set up async error reading
                        Task {
                            let errorHandle = serverError.fileHandleForReading
                            let errorData = errorHandle.readDataToEndOfFile()
                            if !errorData.isEmpty, let errorString = String(data: errorData, encoding: .utf8) {
                                print("\(MCP_SERVER_NAME) Server stderr: \(errorString)")
                                await addMessage(content: "\(MCP_SERVER_NAME) Server error: \(errorString)", isFromServer: true)
                            }
                        }
                        
                        // Start MCP server
                        do {
                            try process.run()
                            print("\(MCP_SERVER_NAME) Server process started with PID: \(process.processIdentifier)")
                            serverProcess = process
                        } catch {
                            let errorMessage = "Failed to start \(MCP_SERVER_NAME) server: \(error.localizedDescription)"
                            print(errorMessage)
                            await updateStatus(errorMessage)
                            await addMessage(content: errorMessage, isFromServer: true)
                            return
                        }
                        
                        await updateStatus("\(MCP_SERVER_NAME) Server started, connecting client...")
                        
                        // Create client with default version
                        let originalClient = Client(name: MCP_CLIENT_NAME, version: MCP_CLIENT_DEFAULT_VERSION)
                        
                        self.client = originalClient
                        
                        // Create FileDescriptors for transport from the pipes
                        let inputFD = FileDescriptor(rawValue: serverOutput.fileHandleForReading.fileDescriptor)
                        let outputFD = FileDescriptor(rawValue: serverInput.fileHandleForWriting.fileDescriptor)
                        
                        // Use StdioTransport with explicit FileDescriptors
                        let transport = StdioTransport(input: inputFD, output: outputFD, logger: nil)
                        self.transport = transport
                        
                        print("Attempting to connect client to \(MCP_SERVER_NAME) server")
                        
                        // Connect the transport first
                        do {
                            try await transport.connect()
                            print("Transport connected successfully")
                            
                            // Test the transport connection with a ping message
                            let pingMessage = "{\"jsonrpc\": \"2.0\", \"method\": \"ping\", \"id\": \"transport-test\"}"
                            print("Sending transport test message: \(pingMessage)")
                            
                            // Send the test message
                            guard let pingData = pingMessage.data(using: .utf8) else {
                                await updateStatus("Error: Failed to encode ping message")
                                await addMessage(content: "Error: Failed to encode ping message", isFromServer: true)
                                return
                            }
                            
                            try await transport.send(pingData)
                            print("Transport test message sent successfully")
                            
                            // Now connect the client using the transport
                            try await client?.connect(transport: transport)
                            print("Client successfully connected to \(MCP_SERVER_NAME) server")
                            clientCreated = true
                            
                        } catch {
                            print("Failed to connect client to \(MCP_SERVER_NAME) server: \(error.localizedDescription)")
                            await updateStatus("Error connecting to \(MCP_SERVER_NAME) server: \(error.localizedDescription)")
                            await addMessage(content: "Error connecting to \(MCP_SERVER_NAME) server: \(error.localizedDescription)", isFromServer: true)
                            
                            // Clean up server process
                            serverProcess?.terminate()
                            serverProcess = nil
                            self.client = nil
                            
                            return
                        }
                    } else {
                        print("\(MCP_SERVER_NAME) server type \(serverType) is not supported, using built-in server")
                        await addMessage(content: "\(MCP_SERVER_NAME) server type \(serverType) is not supported, using built-in server", isFromServer: true)
                    }
                } else {
                    await addMessage(content: "Error: No server configuration found for \(MCP_SERVER_NAME) in config file.", isFromServer: true)
                    await updateStatus("No server configuration found")
                    return
                }
            } catch {
                print("Error loading MCP config: \(error.localizedDescription)")
                await addMessage(content: "Error loading config: \(error.localizedDescription)", isFromServer: true)
                await updateStatus("Config error: \(error.localizedDescription)")
                return
            }
            
            // Verify that client was created successfully
            guard client != nil && clientCreated else {
                await addMessage(content: "Error: Failed to create MCP client", isFromServer: true)
                await updateStatus("Client creation failed")
                return
            }
            
            // Common code for both server types
            
            // Add JSON-RPC debug message for initialize
            await addMessage(content: "[→] JSON-RPC: initialize(clientName: \"\(MCP_CLIENT_NAME)\", version: \"\(MCP_CLIENT_DEFAULT_VERSION)\")", isFromServer: true)
            
            // Initialize connection
            guard let client = self.client else {
                await updateStatus("Error: Client was not created properly")
                await addMessage(content: "Error: Failed to create client object", isFromServer: true)
                return
            }
            
            let result = try await client.initialize()
            
            // Capture server version for future use
            let serverVersion = result.serverInfo.version
            let serverName = result.serverInfo.name
            
            // Add JSON-RPC debug response
            await addMessage(content: "[←] JSON-RPC Response: { \"serverInfo\": { \"name\": \"\(serverName)\", \"version\": \"\(serverVersion)\" } }", isFromServer: true)
            
            // Update the MCP_SERVER_NAME based on the actual server name from the response
            // This ensures we use the actual server name rather than the configured one
            if !serverName.isEmpty {
                // Special case for NPX filesystem server
                if serverName.lowercased() == "filesystem" && MCP_SERVER_NAME.lowercased() != "filesystem" {
                    await addMessage(content: "Connected to NPX Filesystem server. Note: Using configured name '\(MCP_SERVER_NAME)' for server commands.", isFromServer: true)
                    // Don't update the server name in this case to maintain compatibility
                } else {
                    MCP_SERVER_NAME = serverName
                    print("Setting MCP_SERVER_NAME to: \(serverName) (from server response)")
                }
            }
            
            await updateStatus("Connected to: \(serverName) v\(serverVersion)")
            await addMessage(content: "Connected to server: \(serverName) v\(serverVersion)", isFromServer: true)
            
            // Add JSON-RPC debug message for listTools
            await addMessage(content: "[→] JSON-RPC: listTools()", isFromServer: true)
            
            // List available tools
            let toolsResponse = try await client.listTools()
            
            // Format tools for debug display
            var toolsJson = "[\n"
            for tool in toolsResponse.tools {
                toolsJson += "  {\n"
                toolsJson += "    \"name\": \"\(tool.name)\",\n"
                toolsJson += "    \"description\": \"\(tool.description)\"\n"
                
                // Try to extract and log inputSchema if available
                if let inputSchema = tool.inputSchema {
                    // For logging, attempt to convert the inputSchema to a human-readable string
                    if let objectValue = inputSchema.objectValue {
                        let schemaString = objectValue.description
                        toolsJson += "    ,\"inputSchema\": \(schemaString)\n"
                    }
                    
                    // Attempt to extract parameter information from the schema
                    await extractParametersFromSchema(toolName: tool.name, schema: inputSchema)
                }
                
                toolsJson += "  },\n"
            }
            if !toolsResponse.tools.isEmpty {
                toolsJson = String(toolsJson.dropLast(2))
            }
            toolsJson += "\n]"
            
            // Add JSON-RPC debug response for tools
            await addMessage(content: "[←] JSON-RPC Response: { \"tools\": \(toolsJson) }", isFromServer: true)
            
            await MainActor.run {
                self.isConnected = true
                self.availableTools = toolsResponse.tools.map {
                    MCPTool(name: $0.name, description: $0.description)
                }
            }
            
            await addMessage(content: "Available tools: \(toolsResponse.tools.map { $0.name }.joined(separator: ", "))", isFromServer: true)
            
            // Automatically discover available tools and parameters
            await discoverToolsAndParameters()
            
        } catch {
            await updateStatus("Error: \(error.localizedDescription)")
            await addMessage(content: "Error: \(error.localizedDescription)", isFromServer: true)
        }
    }
    
    // Automatically discover tools and their parameters
    private func discoverToolsAndParameters() async {
        // First try active schema discovery for all tools using their inputSchema
        await discoverParametersFromToolSchemas()
        
        // Then, get help info to discover server actions
        if self.availableTools.contains(where: { $0.name == "help" || $0.name == "mcp_\(MCP_SERVER_NAME)_help" }) {
            await addMessage(content: "Querying for available \(MCP_SERVER_NAME) actions...", isFromServer: true)
            
            // Try with mcp_xcf_help first, then fall back to help
            if self.availableTools.contains(where: { $0.name == "mcp_\(MCP_SERVER_NAME)_help" }) {
                await callTool(name: "mcp_\(MCP_SERVER_NAME)_help", text: "")
            } else if self.availableTools.contains(where: { $0.name == "help" }) {
                await callTool(name: "help", text: "")
            }
        }
        
        // Finally, query for tool list to understand available tools
        if self.availableTools.contains(where: { $0.name == "list" || $0.name == "mcp_\(MCP_SERVER_NAME)_list" }) {
            await addMessage(content: "Querying for available tools...", isFromServer: true)
            
            // Try with mcp_xcf_list first, then fall back to list
            if self.availableTools.contains(where: { $0.name == "mcp_\(MCP_SERVER_NAME)_list" }) {
                await callTool(name: "mcp_\(MCP_SERVER_NAME)_list", text: "")
            } else if self.availableTools.contains(where: { $0.name == "list" }) {
                await callTool(name: "list", text: "")
            }
        }
        
        // If we found any server actions, let the user know they can use them
        if let serverActions = ToolRegistry.shared.getSubTools(for: MCP_SERVER_NAME), !serverActions.isEmpty {
            await addMessage(content: "You can use \(MCP_SERVER_NAME) actions by typing '\(MCP_SERVER_NAME) <action>' or just the action name directly.", isFromServer: true)
        }
    }
    
    // New method to proactively discover parameters from schemas in all tools
    private func discoverParametersFromToolSchemas() async {
        // Go through all available tools and try to extract schema info
        for tool in self.availableTools {
            // Skip tools that already have parameter info registered
            if ToolRegistry.shared.hasDiscoveredSchema(for: tool.name) {
                continue
            }
            
            // Try to get schema information through client
            if self.client != nil {
                // Get and examine tool schema (we'd need to add a method to get individual tool schema)
                // For now we'll work with what we have
            }
        }
    }
    
    func callTool(name: String, text: String) async {
        // Display the full command in the chat
        let displayText = text.isEmpty ? name : "\(name) \(text)"
        await addMessage(content: displayText, isFromServer: false)
        
        guard let client = client, isConnected else {
            await addMessage(content: "Error: Client not connected", isFromServer: true)
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
        await addMessage(content: callToolJson, isFromServer: true)
        
        // For debugging, also send the raw request if transport is available
        if let transport = self.transport {
            let id = UUID().uuidString
            let rawRequest = """
            {
                "jsonrpc": "2.0",
                "id": "\(id)",
                "method": "callTool",
                "params": {
                    "name": "\(name)",
                    "arguments": {
                        "\(argumentName)": "\(argumentValue)"
                    }
                }
            }
            """
            
            // Log that we're sending a raw message for debugging
            print("DEBUG: Sending raw request via transport")
            
            // This is just for debugging - the client will handle the actual request
            if Bool.random() { // Only do this occasionally to avoid duplication
                do {
                    try await sendRawMessage(rawRequest)
                } catch {
                    print("Failed to send raw debug message: \(error.localizedDescription)")
                    // Continue execution - this is just a debug feature
                }
            }
        }
        
        do {
            // Call the tool with the appropriate parameter name
            let (content, isError) = try await client.callTool(
                name: name,
                arguments: [(argumentName): .string(argumentValue)]
            )
            
            // Format content for debug display
            var contentJson = "[\n"
            for item in content {
                switch item {
                case .text(let textContent):
                    contentJson += "  {\n"
                    contentJson += "    \"type\": \"text\",\n"
                    contentJson += "    \"value\": \"\(textContent)\"\n"
                    contentJson += "  },\n"
                case .image(data: _, mimeType: _, metadata: _):
                    contentJson += "  {\n"
                    contentJson += "    \"type\": \"image\",\n"
                    contentJson += "    \"data\": \"<binary data>\"\n"
                    contentJson += "  },\n"
                case .audio(data: _, mimeType: _):
                    contentJson += "  {\n"
                    contentJson += "    \"type\": \"audio\",\n"
                    contentJson += "    \"data\": \"<binary data>\"\n"
                    contentJson += "  },\n"
                case .resource(uri: let uri, mimeType: _, text: _):
                    contentJson += "  {\n"
                    contentJson += "    \"type\": \"resource\",\n"
                    contentJson += "    \"uri\": \"\(uri)\"\n"
                    contentJson += "  },\n"
                @unknown default:
                    contentJson += "  {\n"
                    contentJson += "    \"type\": \"unknown\",\n"
                    contentJson += "    \"value\": \"<unknown content type>\"\n"
                    contentJson += "  },\n"
                }
            }
            if !content.isEmpty {
                contentJson = String(contentJson.dropLast(2))
            }
            contentJson += "\n]"
            
            // Add JSON-RPC debug response
            let responseJson = """
            [←] JSON-RPC Response: {
              "content": \(contentJson),
              "isError": \(isError == true)
            }
            """
            await addMessage(content: responseJson, isFromServer: true)
            
            // Process response
            if isError == true {
                await addMessage(content: "Error from server", isFromServer: true)
                return
            }
            
            // Extract text response
            for item in content {
                if case .text(let responseText) = item {
                    await addMessage(content: "Result: \(responseText)", isFromServer: true)
                    
                    // If this was the help command or list tools command, try to extract tool info
                    if name == "mcp_\(MCP_SERVER_NAME)_help" || name == "help" {
                        await processHelpOutput(responseText)
                    } else if name == "mcp_\(MCP_SERVER_NAME)_list" || name == "list" {
                        await processToolList(responseText)
                    }
                    
                    return
                }
            }
        } catch {
            await addMessage(content: "Error: \(error.localizedDescription)", isFromServer: true)
        }
    }
    
    // Process the help output to extract tool information - improved version
    private func processHelpOutput(_ helpText: String) async {
        let lines = helpText.components(separatedBy: .newlines)
        var serverActions: [String] = []
        var currentAction: String? = nil
        var actionDescriptions: [String: String] = [:]
        
        // Extract server actions from help text with improved pattern matching
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Start of an action definition
            if trimmed.hasPrefix("-") {
                let components = trimmed.dropFirst(2).components(separatedBy: ":")
                if components.count > 0 {
                    let actionName = components[0].trimmingCharacters(in: .whitespaces)
                    if !actionName.isEmpty {
                        serverActions.append(actionName)
                        currentAction = actionName
                        
                        // If there's a description after the colon, capture it
                        if components.count > 1 {
                            let description = components[1].trimmingCharacters(in: .whitespaces)
                            if !description.isEmpty {
                                actionDescriptions[actionName] = description
                            }
                        }
                    }
                }
            }
            // Continuation line that might have additional details about the current action
            else if let action = currentAction, !trimmed.isEmpty, !trimmed.hasPrefix("-") {
                // Append to existing description or create a new one
                if var existing = actionDescriptions[action] {
                    existing += " " + trimmed
                    actionDescriptions[action] = existing
                } else {
                    actionDescriptions[action] = trimmed
                }
            }
        }
        
        if !serverActions.isEmpty {
            let actionNames = serverActions.joined(separator: ", ")
            await addMessage(content: "Available \(MCP_SERVER_NAME) actions: \(actionNames)", isFromServer: true)
            
            // Register server sub-tools
            ToolRegistry.shared.registerSubTools(for: MCP_SERVER_NAME, subTools: serverActions)
            
            // Register the parameter info for each server action
            for action in serverActions {
                // Try to discover parameter name for this server
                // First, look for matching server tools that might have schema info
                if let schema = ToolRegistry.shared.getToolSchema(for: MCP_SERVER_NAME), !schema.isEmpty {
                    // Use the first parameter name from the server's schema
                    if let firstParamName = schema.keys.first {
                        let description = actionDescriptions[action]
                        let paramInfo = ToolParameterInfo(
                            name: firstParamName,
                            isRequired: true,
                            type: "string",
                            description: description
                        )
                        ToolRegistry.shared.registerParameterInfo(for: action, parameters: [paramInfo])
                    }
                } else {
                    // If no schema is found, register with a generic parameter name
                    // This will be updated later if schema is discovered
                    let description = actionDescriptions[action]
                    let paramInfo = ToolParameterInfo(
                        name: "text",
                        isRequired: true,
                        type: "string",
                        description: description
                    )
                    ToolRegistry.shared.registerParameterInfo(for: action, parameters: [paramInfo])
                }
            }
            
            // Create local copies to avoid Swift 6 concurrency issues
            let actionsCopy = Array(serverActions)
            let descriptionsCopy = actionDescriptions
            
            // Update the available tools display with improved descriptions
            await MainActor.run {
                for tool in actionsCopy {
                    // If the tool is already in our list but might need description update
                    if let index = self.availableTools.firstIndex(where: { $0.name == tool }),
                       let betterDescription = descriptionsCopy[tool],
                       !betterDescription.isEmpty {
                        // Only update if the current description is generic or empty
                        let currentDescription = self.availableTools[index].description
                        if currentDescription.isEmpty ||
                           currentDescription == "\(MCP_SERVER_NAME) action" {
                            self.availableTools[index] = MCPTool(name: tool, description: betterDescription)
                        }
                    }
                    // If the tool is not in our list yet
                    else if !self.availableTools.contains(where: { $0.name == tool }) {
                        let description = descriptionsCopy[tool] ?? tool
                        self.availableTools.append(MCPTool(name: tool, description: description))
                    }
                }
            }
        } else {
            print("\n===== \(MCP_SERVER_NAME) ACTIONS ERROR =====")
            print("Could not parse \(MCP_SERVER_NAME) actions from help text")
            print(helpText)
            print("==============================\n")
        }
    }
    
    // Process tool list output to extract available tools and parameter info - improved version
    private func processToolList(_ listText: String) async {
        let lines = listText.components(separatedBy: .newlines)
        var tools: [String] = []
        var toolDescriptions: [String: String] = [:]
        var currentTool: String? = nil
        
        // Extract tools from list text with improved pattern matching
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Start of a tool definition
            if trimmed.hasPrefix("- ") {
                let components = trimmed.dropFirst(2).components(separatedBy: ":")
                if components.count > 0 {
                    let toolName = components[0].trimmingCharacters(in: .whitespaces)
                    if !toolName.isEmpty {
                        tools.append(toolName)
                        currentTool = toolName
                        
                        // If there's a description after the colon, capture it
                        if components.count > 1 {
                            let description = components[1].trimmingCharacters(in: .whitespaces)
                            if !description.isEmpty {
                                toolDescriptions[toolName] = description
                            }
                        }
                    }
                }
            }
            // Continuation line that might have additional details about the current tool
            else if let tool = currentTool, !trimmed.isEmpty, !trimmed.hasPrefix("-") {
                // Check for parameter information in the line
                let paramPattern = #"(\w+)(?:\s+\((\w+)\))?(?:\s*:\s*(.+))?"#
                guard let regex = try? NSRegularExpression(pattern: paramPattern),
                      let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                      match.range(at: 1).location != NSNotFound,
                      let range = Range(match.range(at: 1), in: trimmed) else {
                    // Otherwise, append to the tool description
                    if var existing = toolDescriptions[tool] {
                        existing += " " + trimmed
                        toolDescriptions[tool] = existing
                    } else {
                        toolDescriptions[tool] = trimmed
                    }
                    continue
                }

                let paramName = String(trimmed[range])

                // Try to get parameter type
                var paramType = "string" // Default type
                if match.range(at: 2).location != NSNotFound,
                   let typeRange = Range(match.range(at: 2), in: trimmed) {
                    paramType = String(trimmed[typeRange])
                }

                // Try to get parameter description
                var paramDescription: String? = nil
                if match.range(at: 3).location != NSNotFound,
                   let descRange = Range(match.range(at: 3), in: trimmed) {
                    paramDescription = String(trimmed[descRange])
                }

                // Create and register parameter info
                let paramInfo = ToolParameterInfo(
                    name: paramName,
                    isRequired: false, // Can't determine from here
                    type: paramType,
                    description: paramDescription
                )

                // Register this parameter for the tool
                if var existingParams = ToolRegistry.shared.getParameterInfo(for: tool) {
                    existingParams.append(paramInfo)
                    ToolRegistry.shared.registerParameterInfo(for: tool, parameters: existingParams)
                } else {
                    ToolRegistry.shared.registerParameterInfo(for: tool, parameters: [paramInfo])
                }
            }
        }
        
        if !tools.isEmpty {
            // Check for server-related tools and try to extract their schema
            if tools.contains(MCP_SERVER_NAME) || tools.contains(where: { $0.lowercased().hasPrefix("mcp_\(MCP_SERVER_NAME.lowercased())_") }) {
                // If we find a tool that matches the server name, examine its schema
                for tool in tools {
                    if tool == MCP_SERVER_NAME || tool.lowercased().hasPrefix("mcp_\(MCP_SERVER_NAME.lowercased())_") {
                        // Try to extract param info if available in the description
                        if let description = toolDescriptions[tool],
                           description.contains("inputSchema") {
                            // Look for parameter names in the schema
                            let schemaPattern = #"(?:inputSchema|parameters|properties).*?["'](\w+)["']"#
                            
                            guard let regex = try? NSRegularExpression(pattern: schemaPattern),
                                  let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
                                  match.range(at: 1).location != NSNotFound,
                                  let paramNameRange = Range(match.range(at: 1), in: description) else {
                                continue
                            }
                            
                            let paramName = String(description[paramNameRange])
                            
                            // Register this parameter name for the server
                            let schema = [paramName: "string"]
                            ToolRegistry.shared.registerToolSchema(for: tool, schema: schema)
                            
                            print("Extracted server parameter name from schema: \(paramName)")
                        }
                    }
                }
            }
            
            // For each tool, check if it already has schema or parameter info
            for tool in tools {
                // Skip if we already have schema info for this tool
                if ToolRegistry.shared.hasDiscoveredSchema(for: tool) ||
                   ToolRegistry.shared.getParameterInfo(for: tool) != nil {
                    continue
                }
                
                // For tools without explicit schema, register with default parameter
                let paramName = "text" // Default parameter name
                let description = toolDescriptions[tool]
                let paramInfo = ToolParameterInfo(
                    name: paramName,
                    isRequired: true,
                    type: "string",
                    description: description
                )
                ToolRegistry.shared.registerParameterInfo(for: tool, parameters: [paramInfo])
            }
            
            // Create local copies to avoid Swift 6 concurrency issues
            let toolsCopy = Array(tools)
            let descriptionsCopy = toolDescriptions
            
            // Update the available tools display with improved descriptions
            await MainActor.run {
                for tool in toolsCopy {
                    // If the tool is already in our list but might need description update
                    if let index = self.availableTools.firstIndex(where: { $0.name == tool }),
                       let betterDescription = descriptionsCopy[tool],
                       !betterDescription.isEmpty {
                        // Only update if the current description is generic or empty
                        let currentDescription = self.availableTools[index].description
                        if currentDescription.isEmpty ||
                           currentDescription == "\(MCP_SERVER_NAME) action" {
                            self.availableTools[index] = MCPTool(name: tool, description: betterDescription)
                        }
                    }
                    // If the tool is not in our list yet
                    else if !self.availableTools.contains(where: { $0.name == tool }) {
                        let description = descriptionsCopy[tool] ?? tool
                        self.availableTools.append(MCPTool(name: tool, description: description))
                    }
                }
            }
        }
    }
    
    func stopClientServer() {
        Task {
            // Disconnect client first
            if let client = client {
                await client.disconnect()
            }
            
            // Clean up transport
            self.transport = nil
            
            // Clean up client reference
            self.client = nil
            
            // Terminate server process
            serverProcess?.terminate()
            serverProcess = nil
            
            await MainActor.run {
                self.isConnected = false
                self.statusMessage = "Disconnected"
            }
        }
    }
    
    // Send a raw message directly through the transport
    func sendRawMessage(_ message: String) async throws {
        guard let transport = transport, isConnected else {
            throw NSError(domain: "XCodeFreeze", code: 400, userInfo: [NSLocalizedDescriptionKey: "Transport not connected"])
        }
        
        guard let data = message.data(using: .utf8) else {
            throw NSError(domain: "XCodeFreeze", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to encode message"])
        }
        
        print("Sending raw message: \(message)")
        try await transport.send(data)
        print("Raw message sent successfully")
    }
    
    // Debug feature to test and diagnose connection
    func getDiagnostics() async {
        guard isConnected else {
            await addMessage(content: "[DIAGNOSTICS] Client is not connected", isFromServer: true)
            return
        }
        
        await addMessage(content: "[DIAGNOSTICS] Checking client-server connection...", isFromServer: true)
        
        // Check transport
        if let _ = transport {
            await addMessage(content: "[DIAGNOSTICS] Transport exists", isFromServer: true)
        } else {
            await addMessage(content: "[DIAGNOSTICS] Transport is nil", isFromServer: true)
        }
        
        // Check client
        if let client = client {
            await addMessage(content: "[DIAGNOSTICS] Client exists (\(client.name) v\(client.version))", isFromServer: true)
        } else {
            await addMessage(content: "[DIAGNOSTICS] Client is nil", isFromServer: true)
        }
        
        // Check server process
        if let process = serverProcess {
            let isRunning = process.isRunning
            await addMessage(content: "[DIAGNOSTICS] Server process exists (PID: \(process.processIdentifier), Running: \(isRunning))", isFromServer: true)
        } else {
            await addMessage(content: "[DIAGNOSTICS] Server process is nil", isFromServer: true)
        }
        
        // Check available tools
        await addMessage(content: "[DIAGNOSTICS] Available tools: \(availableTools.count)", isFromServer: true)
        
        // Test client with a ping if available
        if let client = client {
            await addMessage(content: "[DIAGNOSTICS] Testing client with ping...", isFromServer: true)
            do {
                _ = try await client.ping()
                await addMessage(content: "[DIAGNOSTICS] Ping successful", isFromServer: true)
            } catch {
                await addMessage(content: "[DIAGNOSTICS] Ping failed: \(error.localizedDescription)", isFromServer: true)
            }
        }
    }
    
    // Debug feature to send an echo request-response to test communication
    func startDebugMessageTest() async {
        guard let client = client, isConnected else {
            await addMessage(content: "Error: Client not connected", isFromServer: true)
            return
        }
        
        await addMessage(content: "[DEBUG] Sending ping message to test communication", isFromServer: true)
        
        // Add JSON-RPC debug message
        await addMessage(content: "[→] JSON-RPC: ping()", isFromServer: true)
        
        do {
            // Send ping request to test the transport
            _ = try await client.ping()
            
            // Success response
            await addMessage(content: "[←] JSON-RPC Response: { \"result\": {} }", isFromServer: true)
            await addMessage(content: "[DEBUG] Ping successful! Communication with server is working.", isFromServer: true)
        } catch {
            await addMessage(content: "[DEBUG] Error during ping test: \(error.localizedDescription)", isFromServer: true)
        }
    }
    
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
    
    @MainActor
    private func updateStatus(_ status: String) {
        statusMessage = status
    }
    
    // Public method to add an informational message
    func addInfoMessage(_ content: String) {
        Task {
            await addMessage(content: content, isFromServer: true)
        }
    }
    
    // Improved parameter extraction from schemas
    private func extractParametersFromSchema(toolName: String, schema: Value) async {
        print("Examining schema for tool: \(toolName)")
        
        var foundParameters = false
        var parameterMap: [String: String] = [:]
        var requiredParams: [String] = []
        var paramDescriptions: [String: String] = [:]
        var paramExamples: [String: String] = [:]
        
        // Debug - output raw schema for inspection
        print("Raw schema for \(toolName): \(schema)")
        
        // Try different schema formats to extract parameter info
        if let objectValue = schema.objectValue {
            // Extract required parameters array
            if let requiredArray = objectValue["required"]?.arrayValue {
                for item in requiredArray {
                    if let paramName = item.stringValue {
                        requiredParams.append(paramName)
                    }
                }
            }
            
            // Format 1: Direct properties at the top level
            for (key, value) in objectValue {
                if value.objectValue?["type"] != nil {
                    // This looks like a parameter definition
                    if let paramType = value.objectValue?["type"]?.stringValue {
                        parameterMap[key] = paramType
                        
                        // Try to extract description and examples too
                        if let description = value.objectValue?["description"]?.stringValue {
                            paramDescriptions[key] = description
                        }
                        
                        if let example = value.objectValue?["example"]?.stringValue ??
                                          value.objectValue?["default"]?.stringValue {
                            paramExamples[key] = example
                        }
                        
                        print("  Found direct parameter: \(key), Type: \(paramType)")
                        foundParameters = true
                    }
                }
            }
            
            // Format 2: "properties" object that defines parameters
            if let properties = objectValue["properties"]?.objectValue {
                for (paramName, paramValue) in properties {
                    // Store parameter name and type if available
                    if let paramType = paramValue.objectValue?["type"]?.stringValue {
                        parameterMap[paramName] = paramType
                        
                        // Try to extract description and examples too
                        if let description = paramValue.objectValue?["description"]?.stringValue {
                            paramDescriptions[paramName] = description
                        }
                        
                        if let example = paramValue.objectValue?["example"]?.stringValue ??
                                         paramValue.objectValue?["default"]?.stringValue {
                            paramExamples[paramName] = example
                        }
                        
                        print("  Found parameter in properties: \(paramName), Type: \(paramType)")
                        foundParameters = true
                    }
                }
            }
            
            // Format 3: "params" or "parameters" object
            for key in ["params", "parameters"] {
                if let params = objectValue[key]?.objectValue {
                    for (paramName, paramValue) in params {
                        if let paramType = paramValue.objectValue?["type"]?.stringValue {
                            parameterMap[paramName] = paramType
                            
                            // Try to extract description and examples too
                            if let description = paramValue.objectValue?["description"]?.stringValue {
                                paramDescriptions[paramName] = description
                            }
                            
                            if let example = paramValue.objectValue?["example"]?.stringValue ??
                                             paramValue.objectValue?["default"]?.stringValue {
                                paramExamples[paramName] = example
                            }
                            
                            print("  Found parameter in \(key): \(paramName), Type: \(paramType)")
                            foundParameters = true
                        }
                    }
                }
            }
            
            // Format 4: Extract from items for array types
            if let items = objectValue["items"]?.objectValue,
               objectValue["type"]?.stringValue == "array" {
                if let itemsProperties = items["properties"]?.objectValue {
                    for (propName, propValue) in itemsProperties {
                        if let propType = propValue.objectValue?["type"]?.stringValue {
                            let paramName = "items.\(propName)"
                            parameterMap[paramName] = "array<\(propType)>"
                            
                            if let description = propValue.objectValue?["description"]?.stringValue {
                                paramDescriptions[paramName] = description
                            }
                            
                            print("  Found array item property: \(propName), Type: array<\(propType)>")
                            foundParameters = true
                        }
                    }
                }
            }
            
            // Format 5: Handle oneOf, anyOf, allOf schema constructs
            for schemaType in ["oneOf", "anyOf", "allOf"] {
                if let options = objectValue[schemaType]?.arrayValue {
                    for (index, option) in options.enumerated() {
                        if let optProps = option.objectValue?["properties"]?.objectValue {
                            for (propName, propValue) in optProps {
                                if let propType = propValue.objectValue?["type"]?.stringValue {
                                    let paramName = "\(schemaType)[\(index)].\(propName)"
                                    parameterMap[paramName] = propType
                                    
                                    if let description = propValue.objectValue?["description"]?.stringValue {
                                        paramDescriptions[paramName] = description
                                    }
                                    
                                    print("  Found \(schemaType) option property: \(propName), Type: \(propType)")
                                    foundParameters = true
                                }
                            }
                        }
                    }
                }
            }
        } else if let arrayValue = schema.arrayValue {
            // Handle schema that's provided as an array of key-value pairs
            // Special case handling for formatted array schema like ["required": ["action"], "properties": ["action": ["type": "string"]]]
            if !arrayValue.isEmpty {
                // Try to interpret array elements
                for (index, item) in arrayValue.enumerated() {
                    if let itemArray = item.arrayValue, itemArray.count >= 2 {
                        if let key = itemArray[0].stringValue, key == "required" {
                            // This is a required parameter array
                            if let requiredList = itemArray[1].arrayValue {
                                for reqItem in requiredList {
                                    if let paramName = reqItem.stringValue {
                                        requiredParams.append(paramName)
                                        print("  Found required parameter: \(paramName)")
                                    }
                                }
                            } else if let paramName = itemArray[1].stringValue {
                                requiredParams.append(paramName)
                                print("  Found required parameter: \(paramName)")
                            }
                        } else if let key = itemArray[0].stringValue, key == "properties" {
                            // This is a properties object
                            if let propsArray = itemArray[1].arrayValue {
                                for propItem in propsArray {
                                    if let propArray = propItem.arrayValue, propArray.count >= 2 {
                                        if let paramName = propArray[0].stringValue {
                                            // Look for type definition
                                            if let paramProps = propArray[1].arrayValue {
                                                for propDef in paramProps {
                                                    if let propDefArray = propDef.arrayValue, propDefArray.count >= 2,
                                                        let propKey = propDefArray[0].stringValue, propKey == "type",
                                                        let propType = propDefArray[1].stringValue {
                                                        
                                                        parameterMap[paramName] = propType
                                                        print("  Found parameter in array properties: \(paramName), Type: \(propType)")
                                                        foundParameters = true
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else if let stringValue = item.stringValue {
                        // Sometimes input schema is provided as serialized JSON strings
                        if stringValue == "required" && index + 1 < arrayValue.count {
                            // Next item should be an array of required params
                            if let reqArray = arrayValue[index + 1].arrayValue {
                                for reqItem in reqArray {
                                    if let paramName = reqItem.stringValue {
                                        requiredParams.append(paramName)
                                        print("  Found required parameter from string format: \(paramName)")
                                    }
                                }
                            }
                        } else if stringValue == "properties" && index + 1 < arrayValue.count {
                            // Next item should be properties
                            if let propsArray = arrayValue[index + 1].arrayValue {
                                for (propIndex, propItem) in propsArray.enumerated() {
                                    if let paramName = propItem.stringValue, propIndex + 1 < propsArray.count {
                                        // Try to extract type from the next item
                                        if let typeObj = propsArray[propIndex + 1].objectValue,
                                           let paramType = typeObj["type"]?.stringValue {
                                            
                                            parameterMap[paramName] = paramType
                                            print("  Found parameter from string format: \(paramName), Type: \(paramType)")
                                            foundParameters = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // If we still don't have parameters, try parsing the description string
            if !foundParameters && toolName.contains(MCP_SERVER_NAME) {
                let descriptionStr = schema.description
                let schemaPattern = #"["'](\w+)["'](?:\s*:\s*["'](\w+)["'])?"#
                
                if let regex = try? NSRegularExpression(pattern: schemaPattern),
                   let match = regex.firstMatch(in: descriptionStr, range: NSRange(descriptionStr.startIndex..<descriptionStr.endIndex, in: descriptionStr)),
                   match.range(at: 1).location != NSNotFound,
                   let paramNameRange = Range(match.range(at: 1), in: descriptionStr) {
                    
                    let paramName = String(descriptionStr[paramNameRange])
                    
                    var paramType = "string" // Default
                    if match.range(at: 2).location != NSNotFound,
                       let paramTypeRange = Range(match.range(at: 2), in: descriptionStr) {
                        paramType = String(descriptionStr[paramTypeRange])
                    }
                    
                    parameterMap[paramName] = paramType
                    print("  Extracted parameter from description: \(paramName), Type: \(paramType)")
                    foundParameters = true
                }
            }
        }
        
        // If we still haven't found parameters and this is a server tool, look for 'action' as a fallback
        if !foundParameters && (toolName == MCP_SERVER_NAME || toolName.hasPrefix("mcp_\(MCP_SERVER_NAME)_")) {
            // Check the schema string representation for mentions of parameter names
            let descriptionStr = schema.description
            if descriptionStr.contains("action") {
                parameterMap["action"] = "string"
                print("  Extracted parameter 'action' from schema description")
                foundParameters = true
            }
        }
        
        // Register all the discovered information
        if !parameterMap.isEmpty {
            ToolRegistry.shared.registerToolSchema(for: toolName, schema: parameterMap)
            
            // Register descriptions if we found any
            if !paramDescriptions.isEmpty {
                ToolRegistry.shared.registerToolParameterDescriptions(for: toolName, descriptions: paramDescriptions)
            }
            
            // Register examples if we found any
            if !paramExamples.isEmpty {
                ToolRegistry.shared.registerToolParameterExamples(for: toolName, examples: paramExamples)
            }
            
            // Log discovery
            let paramNames = parameterMap.keys.joined(separator: ", ")
            await addMessage(content: "Discovered parameters for \(toolName): \(paramNames)", isFromServer: true)
            
            // Create ToolParameterInfo objects for these parameters
            var paramInfoList: [ToolParameterInfo] = []
            for (name, type) in parameterMap {
                let isRequired = requiredParams.contains(name)
                let description = paramDescriptions[name]
                let paramInfo = ToolParameterInfo(name: name, isRequired: isRequired, type: type, description: description)
                paramInfoList.append(paramInfo)
            }
            
            if !paramInfoList.isEmpty {
                ToolRegistry.shared.registerParameterInfo(for: toolName, parameters: paramInfoList)
            }
        } else if !foundParameters {
            print("  No parameters found in schema for \(toolName)")
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Ensure server process is terminated
        serverProcess?.terminate()
    }
}

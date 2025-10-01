import Foundation
import MCP
import Logging

// MARK: - Tool Discovery Service
class ToolDiscoveryService {
    private var clientProvider: (() -> Client?)?
    
    init(clientProvider: (() -> Client?)? = nil) {
        self.clientProvider = clientProvider
    }
    
    func setClient(_ client: Client?) {
        self.clientProvider = { client }
    }
    
    func setClientProvider(_ provider: @escaping () -> Client?) {
        self.clientProvider = provider
    }
    
    // Main method to discover tools and their parameters
    func discoverToolsAndParameters() async {
        // First try active schema discovery for all tools using their inputSchema
        await discoverParametersFromToolSchemas()
        
        // Then, get help info to discover server actions
//        if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == MCPConstants.Commands.help || $0.name == MCPConstants.Commands.serverPrefixedCommand(MCPConstants.Commands.help) }) {
//            
//            // Try with mcp_xcf_help first, then fall back to help
//            if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == MCPConstants.Commands.serverPrefixedCommand(MCPConstants.Commands.help) }) {
//                _ = await callTool(name: MCPConstants.Commands.serverPrefixedCommand(MCPConstants.Commands.help), text: "")
//            } else if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == MCPConstants.Commands.help }) {
//                _ = await callTool(name: MCPConstants.Commands.help, text: "")
//            }
//        }
        
        // Finally, query for tool list to understand available tools
        if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == MCPConstants.Commands.list || $0.name == MCPConstants.Commands.serverPrefixedCommand(MCPConstants.Commands.list) }) {
            
            // Try with mcp_xcf_list first, then fall back to list
            if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == MCPConstants.Commands.serverPrefixedCommand(MCPConstants.Commands.list) }) {
                _ = await callTool(name: MCPConstants.Commands.serverPrefixedCommand(MCPConstants.Commands.list), text: "")
            } else if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == MCPConstants.Commands.list }) {
                _ = await callTool(name: MCPConstants.Commands.list, text: "")
            }
        }
    }
    
    // Method to proactively discover parameters from schemas in all tools
    func discoverParametersFromToolSchemas() async {
        // Go through all available tools and try to extract schema info
        for tool in ToolRegistry.shared.getAvailableTools() {
            // Skip tools that already have parameter info registered
            if ToolRegistry.shared.hasDiscoveredSchema(for: tool.name) {
                continue
            }
        }
    }
    
    // Call a tool with JSON arguments (for AI integration)
    func callToolWithJSON(name: String, jsonArguments: String) async -> String? {
        guard let client = clientProvider?() else {
            return nil
        }
        
        // Parse JSON arguments
        guard let argumentsData = jsonArguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] else {
            // Fallback to single text parameter if JSON parsing fails
            return await callTool(name: name, text: jsonArguments)
        }
        
        // Convert JSON to MCP arguments
        var mcpArguments: [String: Value] = [:]
        for (key, value) in json {
            if let stringValue = value as? String {
                mcpArguments[key] = Value.string(stringValue)
            } else if let intValue = value as? Int {
                mcpArguments[key] = Value.int(intValue)
            } else if let doubleValue = value as? Double {
                mcpArguments[key] = Value.double(doubleValue)
            } else if let boolValue = value as? Bool {
                mcpArguments[key] = Value.bool(boolValue)
            } else if let arrayValue = value as? [Any] {
                // Convert array to JSON string for now
                if let jsonData = try? JSONSerialization.data(withJSONObject: arrayValue),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    mcpArguments[key] = Value.string(jsonString)
                }
            } else if let dictValue = value as? [String: Any] {
                // Convert dictionary to JSON string for now
                if let jsonData = try? JSONSerialization.data(withJSONObject: dictValue),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    mcpArguments[key] = Value.string(jsonString)
                }
            }
        }
        
        do {
            // Call the tool with parsed arguments
            let (content, isError) = try await client.callTool(
                name: name,
                arguments: mcpArguments
            )
            
            // Process response
            if isError == true {
                return "Error from server"
            }
            
            // Extract text response
            for item in content {
                if case .text(let responseText) = item {
                    return responseText
                }
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
        
        return nil
    }
    
    // Call a tool and return the response content (legacy single parameter version)
    func callTool(name: String, text: String) async -> String? {
        guard let client = clientProvider?() else {
            return nil
        }
        
        // Get the appropriate parameter name for this tool
        let argumentName = ToolRegistry.shared.getParameterName(for: name)
        let argumentValue = text
        
        do {
            // Call the tool with the appropriate parameter name
            let (content, isError) = try await client.callTool(
                name: name,
                arguments: [(argumentName): .string(argumentValue)]
            )
            
            // Process response
            if isError == true {
                return "Error from server"
            }
            
            // Extract text response
            for item in content {
                if case .text(let responseText) = item {
                    // If this was the help command or list tools command, try to extract tool info
                    if name == MCPConstants.Commands.serverPrefixedCommand(MCPConstants.Commands.help) || name == MCPConstants.Commands.help {
                        await processHelpOutput(responseText)
                    } else if name == MCPConstants.Commands.serverPrefixedCommand(MCPConstants.Commands.list) || name == MCPConstants.Commands.list {
                        await processToolList(responseText)
                    }
                    
                    return responseText
                }
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
        
        return nil
    }
    
    // Process the help output to extract tool information
    func processHelpOutput(_ helpText: String) async {
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
            // Register server sub-tools
            ToolRegistry.shared.registerSubTools(for: MCPConstants.Server.name, subTools: serverActions)
            
            // Get the server's parameter name - never hardcode "action" or "text"
            var serverParamName: String? = nil
            
            // First try to get the parameter name from the server's schema
            if let schema = ToolRegistry.shared.getToolSchema(for: MCPConstants.Server.name), !schema.isEmpty {
                if let firstParamName = schema.keys.first {
                    serverParamName = firstParamName
                    LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.usingServerParameter, firstParamName))
                }
            }
            
            // If we couldn't get it from schema, try to extract it from descriptions
            if serverParamName == nil {
                // Look for parameter patterns in action names to infer parameter name
                // For example, if there's an action named "search_code", "search" might be a parameter
                var actionNameComponents = Set<String>()
                for action in serverActions {
                    // Split action names by common separators
                    let components = action.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == "." })
                    components.forEach { actionNameComponents.insert(String($0).lowercased()) }
                }
                
                // Extract patterns that might indicate parameter names from action descriptions
                for (_, description) in actionDescriptions {
                    // Use a more comprehensive regex to find parameter-like patterns
                    let paramPatterns = [
                        #"using\s+(?:parameter|param|argument|arg)\s+["']?(\w+)["']?"#, // e.g. "using parameter 'query'"
                        #"with\s+(?:parameter|param|argument|arg)\s+["']?(\w+)["']?"#,  // e.g. "with parameter 'text'"
                        #"(?:parameter|param|argument|arg)(?:\s+name)?\s+is\s+["']?(\w+)["']?"# // e.g. "parameter name is 'action'"
                    ]
                    
                    for pattern in paramPatterns {
                        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                           let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
                           match.range(at: 1).location != NSNotFound,
                           let paramNameRange = Range(match.range(at: 1), in: description) {
                            
                            serverParamName = String(description[paramNameRange])
                            LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.extractedParameterName, serverParamName!))
                            break
                        }
                    }
                    
                    if serverParamName != nil {
                        break
                    }
                }
                
                // As absolute last resort, use a generic name
                if serverParamName == nil {
                    serverParamName = "input"
                    LoggingService.shared.warning(MCPConstants.Messages.ToolDiscovery.parameterNameWarning)
                }
            }
            
            // Register the parameter info for each server action
            let paramName = serverParamName!
            
            // Register this parameter for the server itself if not already registered
            if ToolRegistry.shared.getToolSchema(for: MCPConstants.Server.name) == nil {
                let schema = [paramName: "string"]
                ToolRegistry.shared.registerToolSchema(for: MCPConstants.Server.name, schema: schema)
                LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.registeredSchema, MCPConstants.Server.name, paramName))
            }
            
            // Register parameter info for each action
            for action in serverActions {
                let description = actionDescriptions[action]
                let paramInfo = ToolParameterInfo(
                    name: paramName,
                    isRequired: true,
                    type: "string",
                    description: description
                )
                ToolRegistry.shared.registerParameterInfo(for: action, parameters: [paramInfo])
            }
        } else {
            LoggingService.shared.error(String(format: MCPConstants.Messages.ToolDiscovery.actionsError, MCPConstants.Server.name))
            LoggingService.shared.error(String(format: MCPConstants.Messages.ToolDiscovery.couldNotParse, MCPConstants.Server.name))
            LoggingService.shared.error(helpText)
            LoggingService.shared.error("==============================\n")
        }
    }
    
    // Process tool list output to extract available tools and parameter info
    func processToolList(_ listText: String) async {
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
            if tools.contains(MCPConstants.Server.name) || tools.contains(where: { $0.lowercased().hasPrefix("mcp_\(MCPConstants.Server.name.lowercased())_") }) {
                // If we find a tool that matches the server name, examine its schema
                for tool in tools {
                    if tool == MCPConstants.Server.name || tool.lowercased().hasPrefix("mcp_\(MCPConstants.Server.name.lowercased())_") {
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
                            
                            LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.extractedServerParameterName, paramName))
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
                
                // For tools without explicit schema, try to intelligently determine parameter name
                var paramName: String? = nil
                
                // For server-related tools, use the server's parameter name if available
                if tool == MCPConstants.Server.name || tool.lowercased().hasPrefix("mcp_\(MCPConstants.Server.name.lowercased())_") {
                    // For server-related tools, try to determine the parameter name
                    // First check if the server itself has a schema
                    if let serverSchema = ToolRegistry.shared.getToolSchema(for: MCPConstants.Server.name),
                       let firstParam = serverSchema.keys.first {
                        paramName = firstParam
                    } 
                    // Look for hints in the description
                    else if let description = toolDescriptions[tool] {
                        let paramPattern = #"(?:param|parameter|arg|argument):?\s+["']?(\w+)["']?"#
                        if let regex = try? NSRegularExpression(pattern: paramPattern, options: .caseInsensitive),
                           let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
                           match.range(at: 1).location != NSNotFound,
                           let paramNameRange = Range(match.range(at: 1), in: description) {
                            paramName = String(description[paramNameRange])
                        }
                    }
                }
                
                // If no parameter name was found, use a reasonable default based on the tool name
                if paramName == nil {
                    // If there's any parameter info in the description, try to extract it
                    if let description = toolDescriptions[tool] {
                        // Use a regex pattern to identify parameter-like mentions
                        let paramPatterns = [
                            #"(?:parameter|param|argument|arg)(?:\s+name)?(?:\s+is)?\s+["']?(\w+)["']?"#,
                            #"takes\s+(?:a|an)\s+["']?(\w+)["']?\s+(?:parameter|param|argument|arg)"#,
                            #"using\s+(?:the|a|an)?\s+["']?(\w+)["']?\s+parameter"#
                        ]
                        
                        for pattern in paramPatterns {
                            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                               let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
                               match.range(at: 1).location != NSNotFound,
                               let paramNameRange = Range(match.range(at: 1), in: description) {
                                paramName = String(description[paramNameRange])
                                LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.extractedParameterName, paramName!))
                                break
                            }
                        }
                    }
                    
                    // If still no parameter name, check if this tool actually needs parameters
                    if paramName == nil {
                        // Check if this is a tool that likely doesn't need parameters based on common patterns
                        let noParamTools = ["list", "help", "xcf_help", "show_help", "tools", "show_env", "show_folder", 
                                          "show_current_project", "list_projects", "use_xcf", "grant_permission", 
                                          "run_project", "build_project"]
                        
                        // Check if this tool matches any no-parameter tool patterns
                        let toolLower = tool.lowercased()
                        let isNoParamTool = noParamTools.contains { noParamTool in
                            toolLower == noParamTool || toolLower.hasSuffix("_\(noParamTool)") || toolLower.hasPrefix("mcp_") && toolLower.contains("_\(noParamTool)")
                        }
                        
                        if isNoParamTool {
                            // This tool doesn't need parameters, register empty schema to mark as discovered
                            LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.noParametersNeeded, tool))
                            ToolRegistry.shared.registerToolSchema(for: tool, schema: [:])
                            continue
                        } else {
                            // Only create generic parameter for tools that likely need parameters
                            paramName = "input"
                            LoggingService.shared.warning(String(format: MCPConstants.Messages.ToolDiscovery.parameterNameWarning, tool))
                        }
                    }
                }
                
                // Only create parameter info if we determined the tool needs parameters
                if let paramName = paramName {
                    let description = toolDescriptions[tool]
                    let paramInfo = ToolParameterInfo(
                        name: paramName,
                        isRequired: true,
                        type: "string",
                        description: description
                    )
                    ToolRegistry.shared.registerParameterInfo(for: tool, parameters: [paramInfo])
                }
            }
        }
    }
    
    // Parameter extraction from schemas
    func extractParametersFromSchema(toolName: String, schema: Value) async {
        LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.examiningSchema, toolName))
        
        var foundParameters = false
        var parameterMap: [String: String] = [:]
        var requiredParams: [String] = []
        var paramDescriptions: [String: String] = [:]
        var paramExamples: [String: String] = [:]
        
        // Debug - output raw schema for inspection
        LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.rawSchema, toolName))
        
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
                        
                        LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.foundDirectParameter, key, paramType))
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
                        
                        LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.foundParameterInProperties, paramName, paramType))
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
                            
                            LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.foundParameterIn, key, paramName, paramType))
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
                            
                            LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.foundArrayItemProperty, propName, "array<\(propType)>"))
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
                                    
                                    LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.found, schemaType, index, propName, propType))
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
                                        LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.foundRequiredParameter, paramName))
                                    }
                                }
                            } else if let paramName = itemArray[1].stringValue {
                                requiredParams.append(paramName)
                                LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.foundRequiredParameter, paramName))
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
                                                        LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.foundParameterInArrayProperties, paramName, propType))
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
                                        LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.foundRequiredParameterFromStringFormat, paramName))
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
                                            LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.foundParameterFromStringFormat, paramName, paramType))
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
            if !foundParameters && toolName.contains(MCPConstants.Server.name) {
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
                    LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.extractedParameterFromDescription, paramName, paramType))
                    foundParameters = true
                }
            }
        }
        
        // If we still haven't found parameters and this is a server tool, examine more carefully
        if !foundParameters && (toolName == MCPConstants.Server.name || toolName.hasPrefix("mcp_\(MCPConstants.Server.name)_")) {
            // Check the schema string representation for mentions of parameter names
            let descriptionStr = schema.description
            
            // Extract parameter names using regex patterns that look for JSON schema structures
            // Look for patterns like "propertyName": { "type": "string" } or "properties": { "name": {
            
            // Pattern for JSON property names in quotes
            let jsonPropertyPattern = #"["'](\w+)["']\s*:\s*\{(?:[^{}]|\{[^{}]*\})*\}"#
            if let regex = try? NSRegularExpression(pattern: jsonPropertyPattern),
               let match = regex.firstMatch(in: descriptionStr, range: NSRange(descriptionStr.startIndex..<descriptionStr.endIndex, in: descriptionStr)),
               match.range(at: 1).location != NSNotFound,
               let paramNameRange = Range(match.range(at: 1), in: descriptionStr) {
                
                let extractedName = String(descriptionStr[paramNameRange])
                parameterMap[extractedName] = "string"
                LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.extractedParameterFromSchemaJSONStructure, extractedName))
                foundParameters = true
            }
            
            // If still not found, try a simpler pattern to find parameter names in quotes
            if !foundParameters {
                let simpleNamePattern = #"["'](\w+)["'](?:\s*:\s*["']?(?:string|object|array|boolean|number)["']?)?"#
                
                if let regex = try? NSRegularExpression(pattern: simpleNamePattern),
                   let match = regex.firstMatch(in: descriptionStr, range: NSRange(descriptionStr.startIndex..<descriptionStr.endIndex, in: descriptionStr)),
                   match.range(at: 1).location != NSNotFound,
                   let paramNameRange = Range(match.range(at: 1), in: descriptionStr) {
                    
                    let extractedName = String(descriptionStr[paramNameRange])
                    // Skip schema-related keywords that aren't actual parameters
                    let schemaKeywords = ["properties", "required", "type", "items", "oneOf", "anyOf", "allOf"]
                    if !schemaKeywords.contains(extractedName) {
                        parameterMap[extractedName] = "string"
                        LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.extractedParameterFromQuotedNameInSchema, extractedName))
                        foundParameters = true
                    }
                }
            }
            
            // If still not found, check if this tool actually needs parameters
            if !foundParameters {
                // Check if the schema is just an empty object type with no properties
                if let objectValue = schema.objectValue {
                    let hasProperties = objectValue["properties"] != nil
                    let hasRequired = objectValue["required"] != nil
                    let hasOtherParams = objectValue.keys.contains { key in
                        !["type", "properties", "required"].contains(key) && objectValue[key]?.objectValue?["type"] != nil
                    }
                    
                    // If it's just {"type": "object"} with no properties, required fields, or other parameters,
                    // then this tool doesn't need any parameters
                    if !hasProperties && !hasRequired && !hasOtherParams {
                        LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.noParametersNeeded, toolName))
                        // Register an empty schema to mark this tool as discovered but parameterless
                        ToolRegistry.shared.registerToolSchema(for: toolName, schema: [:])
                        return
                    }
                }
                
                // Only create generic parameter as absolute last resort for server tools that should have parameters
                if toolName == MCPConstants.Server.name || toolName.hasPrefix("mcp_\(MCPConstants.Server.name)_") {
                    parameterMap["input"] = "string"
                    LoggingService.shared.warning(MCPConstants.Messages.ToolDiscovery.unableToExtractParameterNameFromSchemaWarning)
                    foundParameters = true
                } else {
                    // For non-server tools, just register empty schema
                    LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.noParametersNeeded, toolName))
                    ToolRegistry.shared.registerToolSchema(for: toolName, schema: [:])
                    return
                }
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
            LoggingService.shared.debug(String(format: MCPConstants.Messages.ToolDiscovery.noParametersFound, toolName))
        }
    }
} 

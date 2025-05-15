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
        if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == "help" || $0.name == "mcp_\(MCP_SERVER_NAME)_help" }) {
            
            // Try with mcp_xcf_help first, then fall back to help
            if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == "mcp_\(MCP_SERVER_NAME)_help" }) {
                _ = await callTool(name: "mcp_\(MCP_SERVER_NAME)_help", text: "")
            } else if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == "help" }) {
                _ = await callTool(name: "help", text: "")
            }
        }
        
        // Finally, query for tool list to understand available tools
        if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == "list" || $0.name == "mcp_\(MCP_SERVER_NAME)_list" }) {
            
            // Try with mcp_xcf_list first, then fall back to list
            if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == "mcp_\(MCP_SERVER_NAME)_list" }) {
                _ = await callTool(name: "mcp_\(MCP_SERVER_NAME)_list", text: "")
            } else if ToolRegistry.shared.getAvailableTools().contains(where: { $0.name == "list" }) {
                _ = await callTool(name: "list", text: "")
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
    
    // Call a tool and return the response content
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
                    if name == "mcp_\(MCP_SERVER_NAME)_help" || name == "help" {
                        await processHelpOutput(responseText)
                    } else if name == "mcp_\(MCP_SERVER_NAME)_list" || name == "list" {
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
            ToolRegistry.shared.registerSubTools(for: MCP_SERVER_NAME, subTools: serverActions)
            
            // Get the server's parameter name - never hardcode "action" or "text"
            var serverParamName: String? = nil
            
            // First try to get the parameter name from the server's schema
            if let schema = ToolRegistry.shared.getToolSchema(for: MCP_SERVER_NAME), !schema.isEmpty {
                if let firstParamName = schema.keys.first {
                    serverParamName = firstParamName
                    print("Using server parameter name from schema: \(firstParamName)")
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
                            print("Extracted parameter name from description using pattern: \(serverParamName!)")
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
                    print("WARNING: Unable to determine parameter name, using generic 'input'")
                }
            }
            
            // Register the parameter info for each server action
            let paramName = serverParamName!
            
            // Register this parameter for the server itself if not already registered
            if ToolRegistry.shared.getToolSchema(for: MCP_SERVER_NAME) == nil {
                let schema = [paramName: "string"]
                ToolRegistry.shared.registerToolSchema(for: MCP_SERVER_NAME, schema: schema)
                print("Registered schema for \(MCP_SERVER_NAME) with parameter: \(paramName)")
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
            print("\n===== \(MCP_SERVER_NAME) ACTIONS ERROR =====")
            print("Could not parse \(MCP_SERVER_NAME) actions from help text")
            print(helpText)
            print("==============================\n")
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
                
                // For tools without explicit schema, try to intelligently determine parameter name
                var paramName: String? = nil
                
                // For server-related tools, use the server's parameter name if available
                if tool == MCP_SERVER_NAME || tool.lowercased().hasPrefix("mcp_\(MCP_SERVER_NAME.lowercased())_") {
                    // For server-related tools, try to determine the parameter name
                    // First check if the server itself has a schema
                    if let serverSchema = ToolRegistry.shared.getToolSchema(for: MCP_SERVER_NAME),
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
                                print("Extracted parameter name '\(paramName!)' from tool description")
                                break
                            }
                        }
                    }
                    
                    // If still no parameter name, use a generic one with warning
                    if paramName == nil {
                        paramName = "input"
                        print("WARNING: Unable to determine parameter name for tool \(tool), using generic 'input'")
                    }
                }
                
                let description = toolDescriptions[tool]
                let paramInfo = ToolParameterInfo(
                    name: paramName!,
                    isRequired: true,
                    type: "string",
                    description: description
                )
                ToolRegistry.shared.registerParameterInfo(for: tool, parameters: [paramInfo])
            }
        }
    }
    
    // Parameter extraction from schemas
    func extractParametersFromSchema(toolName: String, schema: Value) async {
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
        
        // If we still haven't found parameters and this is a server tool, examine more carefully
        if !foundParameters && (toolName == MCP_SERVER_NAME || toolName.hasPrefix("mcp_\(MCP_SERVER_NAME)_")) {
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
                print("  Extracted parameter '\(extractedName)' from schema JSON structure")
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
                        print("  Extracted parameter '\(extractedName)' from quoted name in schema")
                        foundParameters = true
                    }
                }
            }
            
            // Last resort - use a generic parameter name only if we truly can't extract anything
            // This is technically still a hardcoded fallback, but only used when we have no other options
            if !foundParameters {
                // Use a generic parameter name as absolute last resort
                parameterMap["input"] = "string"
                print("  WARNING: Unable to extract parameter name from schema, using generic 'input'")
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
} 
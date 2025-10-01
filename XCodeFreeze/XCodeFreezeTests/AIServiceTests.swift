//
//  AIServiceTests.swift
//  XCodeFreezeTests
//
//  Created by Test on 5/9/25.
//

import XCTest
@testable import XCodeFreeze

class AIServiceTests: XCTestCase {
    
    var sut: AIService!
    
    override func setUp() async throws {
        try await super.setUp()
        sut = await AIService.shared
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - MCP Tool Parameter Creation Tests
    
    func testCreateParametersFromMCPTool_WithFullSchema() async {
        // Given
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "filePath": [
                    "type": "string",
                    "description": "Path to the file"
                ],
                "lineNumber": [
                    "type": "integer",
                    "description": "Line number in the file"
                ],
                "verbose": [
                    "type": "boolean",
                    "description": "Enable verbose output"
                ]
            ],
            "required": ["filePath", "lineNumber"]
        ]
        
        let mcpTool = MCPTool(
            name: "test_tool",
            description: "A test tool",
            inputSchema: schema
        )
        
        // When
        let tools = await sut.convertMCPToolsToAIFunctions([mcpTool])
        
        // Then
        XCTAssertNotNil(tools)
        XCTAssertEqual(tools?.count, 1)
        
        let tool = tools?.first
        XCTAssertEqual(tool?.type, "function")
        XCTAssertEqual(tool?.function.name, "test_tool")
        XCTAssertEqual(tool?.function.description, "A test tool")
        
        let parameters = tool?.function.parameters
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?.type, "object")
        XCTAssertEqual(parameters?.properties.count, 3)
        
        // Check individual properties
        let filePathProp = parameters?.properties["filePath"]
        XCTAssertNotNil(filePathProp)
        XCTAssertEqual(filePathProp?.type, "string")
        XCTAssertEqual(filePathProp?.description, "Path to the file")
        
        let lineNumberProp = parameters?.properties["lineNumber"]
        XCTAssertNotNil(lineNumberProp)
        XCTAssertEqual(lineNumberProp?.type, "integer")
        XCTAssertEqual(lineNumberProp?.description, "Line number in the file")
        
        let verboseProp = parameters?.properties["verbose"]
        XCTAssertNotNil(verboseProp)
        XCTAssertEqual(verboseProp?.type, "boolean")
        XCTAssertEqual(verboseProp?.description, "Enable verbose output")
        
        // Check required fields
        XCTAssertEqual(parameters?.required.count, 2)
        XCTAssertTrue(parameters?.required.contains("filePath") ?? false)
        XCTAssertTrue(parameters?.required.contains("lineNumber") ?? false)
    }
    
    func testCreateParametersFromMCPTool_NoSchema() async {
        // Given
        let mcpTool = MCPTool(
            name: "simple_tool",
            description: "A simple tool without schema",
            inputSchema: nil
        )
        
        // When
        let tools = await sut.convertMCPToolsToAIFunctions([mcpTool])
        
        // Then
        XCTAssertNotNil(tools)
        XCTAssertEqual(tools?.count, 1)
        
        let tool = tools?.first
        let parameters = tool?.function.parameters
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?.type, "object")
        XCTAssertTrue(parameters?.properties.isEmpty ?? false)
        XCTAssertTrue(parameters?.required.isEmpty ?? false)
    }
    
    func testCreateParametersFromMCPTool_EmptySchema() async {
        // Given
        let mcpTool = MCPTool(
            name: "empty_schema_tool",
            description: "A tool with empty schema",
            inputSchema: [:]
        )
        
        // When
        let tools = await sut.convertMCPToolsToAIFunctions([mcpTool])
        
        // Then
        XCTAssertNotNil(tools)
        XCTAssertEqual(tools?.count, 1)
        
        let tool = tools?.first
        let parameters = tool?.function.parameters
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?.type, "object")
        XCTAssertTrue(parameters?.properties.isEmpty ?? false)
        XCTAssertTrue(parameters?.required.isEmpty ?? false)
    }
    
    func testCreateParametersFromMCPTool_NestedSchema() async {
        // Given
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "config": [
                    "type": "object",
                    "description": "Configuration object",
                    "properties": [
                        "enabled": [
                            "type": "boolean",
                            "description": "Enable feature"
                        ],
                        "timeout": [
                            "type": "integer",
                            "description": "Timeout in seconds"
                        ]
                    ]
                ],
                "name": [
                    "type": "string",
                    "description": "Name of the item"
                ]
            ],
            "required": ["config"]
        ]
        
        let mcpTool = MCPTool(
            name: "nested_tool",
            description: "A tool with nested schema",
            inputSchema: schema
        )
        
        // When
        let tools = await sut.convertMCPToolsToAIFunctions([mcpTool])
        
        // Then
        XCTAssertNotNil(tools)
        XCTAssertEqual(tools?.count, 1)
        
        let tool = tools?.first
        let parameters = tool?.function.parameters
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?.type, "object")
        XCTAssertEqual(parameters?.properties.count, 2)
        
        // Check config property (nested object)
        let configProp = parameters?.properties["config"]
        XCTAssertNotNil(configProp)
        XCTAssertEqual(configProp?.type, "object")
        XCTAssertEqual(configProp?.description, "Configuration object")
        
        // Check name property
        let nameProp = parameters?.properties["name"]
        XCTAssertNotNil(nameProp)
        XCTAssertEqual(nameProp?.type, "string")
        XCTAssertEqual(nameProp?.description, "Name of the item")
        
        // Check required fields
        XCTAssertEqual(parameters?.required.count, 1)
        XCTAssertTrue(parameters?.required.contains("config") ?? false)
    }
    
    // MARK: - Tool Execution Tests
    
    func testExecuteMCPTool_SimpleArguments() async {
        // Given
        let mockExecutor: (String, String) async -> String? = { name, args in
            XCTAssertEqual(name, "list_projects")
            XCTAssertEqual(args, "")
            return "Project 1, Project 2"
        }
        
        await sut.setMCPToolExecutor(mockExecutor)
        
        // When
        let result = await sut.executeMCPTool(name: "list_projects", arguments: "{}")
        
        // Then
        XCTAssertEqual(result, "Project 1, Project 2")
    }
    
    func testExecuteMCPTool_WithJSONArguments() async {
        // Given
        let mockExecutor: (String, String) async -> String? = { name, args in
            XCTAssertEqual(name, "read_file")
            XCTAssertEqual(args, "/path/to/file.txt")
            return "File contents"
        }
        
        await sut.setMCPToolExecutor(mockExecutor)
        
        let arguments = """
        {"filePath": "/path/to/file.txt"}
        """
        
        // When
        let result = await sut.executeMCPTool(name: "read_file", arguments: arguments)
        
        // Then
        XCTAssertEqual(result, "File contents")
    }
    
    func testExecuteMCPTool_WithComplexArguments() async {
        // Given
        let mockExecutor: (String, String) async -> String? = { name, args in
            XCTAssertEqual(name, "select_project")
            XCTAssertEqual(args, "2")
            return "Selected project 2"
        }
        
        await sut.setMCPToolExecutor(mockExecutor)
        
        let arguments = """
        {"projectNumber": 2}
        """
        
        // When
        let result = await sut.executeMCPTool(name: "select_project", arguments: arguments)
        
        // Then
        XCTAssertEqual(result, "Selected project 2")
    }
    
    func testExecuteMCPTool_WithMultipleParameters() async {
        // Given
        let mockExecutor: (String, String) async -> String? = { name, args in
            XCTAssertEqual(name, "complex_tool")
            // Multiple parameters should be joined with space
            XCTAssertTrue(args.contains("value1"))
            XCTAssertTrue(args.contains("42"))
            return "Success"
        }
        
        await sut.setMCPToolExecutor(mockExecutor)
        
        let arguments = """
        {"param1": "value1", "param2": 42, "param3": true}
        """
        
        // When
        let result = await sut.executeMCPTool(name: "complex_tool", arguments: arguments)
        
        // Then
        XCTAssertEqual(result, "Success")
    }
    
    func testExecuteMCPTool_NoExecutor() async {
        // Given
        await sut.setMCPToolExecutor(nil)
        
        // When
        let result = await sut.executeMCPTool(name: "test_tool", arguments: "{}")
        
        // Then
        XCTAssertEqual(result, "Error: MCP tool executor not available")
    }
    
    // MARK: - Multiple Tools Conversion
    
    func testConvertMultipleMCPTools() async {
        // Given
        let tools = [
            MCPTool(
                name: "tool1",
                description: "First tool",
                inputSchema: [
                    "type": "object",
                    "properties": ["param1": ["type": "string"]],
                    "required": ["param1"]
                ]
            ),
            MCPTool(
                name: "tool2",
                description: "Second tool",
                inputSchema: nil
            ),
            MCPTool(
                name: "tool3",
                description: "Third tool",
                inputSchema: [
                    "type": "object",
                    "properties": ["param2": ["type": "integer"]]
                ]
            )
        ]
        
        // When
        let aiTools = await sut.convertMCPToolsToAIFunctions(tools)
        
        // Then
        XCTAssertNotNil(aiTools)
        XCTAssertEqual(aiTools?.count, 3)
        
        XCTAssertEqual(aiTools?[0].function.name, "tool1")
        XCTAssertEqual(aiTools?[0].function.parameters?.properties.count, 1)
        XCTAssertEqual(aiTools?[0].function.parameters?.required.count, 1)
        
        XCTAssertEqual(aiTools?[1].function.name, "tool2")
        XCTAssertTrue(aiTools?[1].function.parameters?.properties.isEmpty ?? false)
        
        XCTAssertEqual(aiTools?[2].function.name, "tool3")
        XCTAssertEqual(aiTools?[2].function.parameters?.properties.count, 1)
        XCTAssertTrue(aiTools?[2].function.parameters?.required.isEmpty ?? false)
    }
}

// MARK: - AIService Extension for Testing

extension AIService {
    // Expose internal methods for testing
    func convertMCPToolsToAIFunctions(_ mcpTools: [MCPTool]) async -> [AITool]? {
        return convertMCPToolsToAIFunctions(mcpTools)
    }
    
    func executeMCPTool(name: String, arguments: String) async -> String {
        return await executeMCPTool(name: name, arguments: arguments)
    }
}
import XCTest
@testable import XCodeFreeze

class AIServiceParameterTests: XCTestCase {
    
    var aiService: AIService!
    
    override func setUp() async throws {
        aiService = await AIService.shared
    }
    
    override func tearDown() {
        aiService = nil
        super.tearDown()
    }
    
    // MARK: - MCP Tool Conversion Tests
    
    func testConvertMCPToolWithMultipleParameters() async {
        // Given
        let mcpTool = MCPTool(
            name: "create_doc",
            description: "Create a new document",
            inputSchema: [
                "type": "object",
                "properties": [
                    "filePath": [
                        "type": "string",
                        "description": "Path to the file"
                    ],
                    "content": [
                        "type": "string", 
                        "description": "Content to write"
                    ]
                ],
                "required": ["filePath"]
            ]
        )
        
        // When
        let aiTools = await aiService.convertMCPToolsToAIFunctions([mcpTool])
        
        // Then
        XCTAssertNotNil(aiTools)
        XCTAssertEqual(aiTools?.count, 1)
        
        if let firstTool = aiTools?.first {
            XCTAssertEqual(firstTool.type, "function")
            XCTAssertEqual(firstTool.function.name, "create_doc")
            XCTAssertEqual(firstTool.function.description, "Create a new document")
            
            if let params = firstTool.function.parameters {
                XCTAssertEqual(params.type, "object")
                XCTAssertEqual(params.properties.count, 2)
                XCTAssertNotNil(params.properties["filePath"])
                XCTAssertNotNil(params.properties["content"])
                XCTAssertEqual(params.required, ["filePath"])
            } else {
                XCTFail("Parameters should not be nil")
            }
        }
    }
    
    func testConvertMCPToolWithMixedParameterTypes() async {
        // Given
        let mcpTool = MCPTool(
            name: "analyze_swift_code",
            description: "Analyze Swift code",
            inputSchema: [
                "type": "object",
                "properties": [
                    "filePath": [
                        "type": "string",
                        "description": "Path to the file"
                    ],
                    "startLine": [
                        "type": "integer",
                        "description": "Starting line number"
                    ],
                    "endLine": [
                        "type": "integer",
                        "description": "Ending line number"
                    ],
                    "entireFile": [
                        "type": "boolean",
                        "description": "Analyze entire file"
                    ]
                ],
                "required": ["filePath"]
            ]
        )
        
        // When
        let aiTools = await aiService.convertMCPToolsToAIFunctions([mcpTool])
        
        // Then
        XCTAssertNotNil(aiTools)
        
        if let firstTool = aiTools?.first,
           let params = firstTool.function.parameters {
            XCTAssertEqual(params.properties.count, 4)
            
            // Check each parameter type
            XCTAssertEqual(params.properties["filePath"]?.type, "string")
            XCTAssertEqual(params.properties["startLine"]?.type, "integer")
            XCTAssertEqual(params.properties["endLine"]?.type, "integer")
            XCTAssertEqual(params.properties["entireFile"]?.type, "boolean")
        } else {
            XCTFail("Tool conversion failed")
        }
    }
    
    func testConvertMCPToolWithNoSchema() async {
        // Given
        let mcpTool = MCPTool(
            name: "simple_tool",
            description: "A simple tool",
            inputSchema: nil
        )
        
        // When
        let aiTools = await aiService.convertMCPToolsToAIFunctions([mcpTool])
        
        // Then
        XCTAssertNotNil(aiTools)
        
        if let firstTool = aiTools?.first,
           let params = firstTool.function.parameters {
            XCTAssertEqual(params.type, "object")
            XCTAssertEqual(params.properties.count, 0)
            XCTAssertEqual(params.required.count, 0)
        } else {
            XCTFail("Tool should have empty parameters")
        }
    }
    
    // MARK: - Execute MCP Tool Tests
    
    func testExecuteMCPToolPassesFullJSON() async {
        // Given
        var capturedToolName: String?
        var capturedArguments: String?
        
        await aiService.setMCPToolExecutor { toolName, arguments in
            capturedToolName = toolName
            capturedArguments = arguments
            return "Success"
        }
        
        let toolName = "create_doc"
        let jsonArgs = """
        {"filePath": "/test/file.swift", "content": "test content"}
        """
        
        // When
        let result = await aiService.executeMCPTool(name: toolName, arguments: jsonArgs)
        
        // Then
        XCTAssertEqual(result, "Success")
        XCTAssertEqual(capturedToolName, toolName)
        XCTAssertEqual(capturedArguments, jsonArgs)
    }
    
    func testExecuteMCPToolWithoutExecutor() async {
        // Given - no executor set
        await aiService.setMCPToolExecutor(nil)
        
        // When
        let result = await aiService.executeMCPTool(
            name: "test_tool",
            arguments: "{}"
        )
        
        // Then
        XCTAssertEqual(result, "Error: MCP tool executor not available")
    }
    
    func testCreateParametersFromMCPToolExtractsAllFields() async {
        // Given
        let mcpTool = MCPTool(
            name: "complex_tool",
            description: "Complex tool",
            inputSchema: [
                "type": "object",
                "properties": [
                    "stringParam": ["type": "string", "description": "A string"],
                    "numberParam": ["type": "number", "description": "A number"],
                    "boolParam": ["type": "boolean", "description": "A boolean"],
                    "arrayParam": ["type": "array", "description": "An array"]
                ],
                "required": ["stringParam", "numberParam"]
            ]
        )
        
        // When
        let params = await aiService.createParametersFromMCPTool(mcpTool)
        
        // Then
        XCTAssertNotNil(params)
        XCTAssertEqual(params?.type, "object")
        XCTAssertEqual(params?.properties.count, 4)
        XCTAssertEqual(params?.required, ["stringParam", "numberParam"])
        
        // Verify each property
        XCTAssertEqual(params?.properties["stringParam"]?.type, "string")
        XCTAssertEqual(params?.properties["stringParam"]?.description, "A string")
        
        XCTAssertEqual(params?.properties["numberParam"]?.type, "number")
        XCTAssertEqual(params?.properties["numberParam"]?.description, "A number")
        
        XCTAssertEqual(params?.properties["boolParam"]?.type, "boolean")
        XCTAssertEqual(params?.properties["boolParam"]?.description, "A boolean")
        
        XCTAssertEqual(params?.properties["arrayParam"]?.type, "array")
        XCTAssertEqual(params?.properties["arrayParam"]?.description, "An array")
    }
}
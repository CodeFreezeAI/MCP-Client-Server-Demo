//
//  ClientServerServiceTests.swift
//  XCodeFreezeTests
//
//  Created by Test on 5/9/25.
//

import XCTest
import MCP
@testable import XCodeFreeze

class ClientServerServiceTests: XCTestCase {
    
    var sut: ClientServerService!
    var mockMessageHandler: MockMessageHandler!
    
    override func setUp() {
        super.setUp()
        mockMessageHandler = MockMessageHandler()
        sut = ClientServerService(messageHandler: mockMessageHandler)
    }
    
    override func tearDown() {
        sut = nil
        mockMessageHandler = nil
        super.tearDown()
    }
    
    // MARK: - Value Conversion Tests
    
    func testConvertValueToAny_Null() {
        // Given
        let value = Value.null
        
        // When
        let result = sut.convertValueToAny(value)
        
        // Then
        XCTAssertTrue(result is NSNull)
    }
    
    func testConvertValueToAny_Bool() {
        // Given
        let value = Value.bool(true)
        
        // When
        let result = sut.convertValueToAny(value)
        
        // Then
        XCTAssertEqual(result as? Bool, true)
    }
    
    func testConvertValueToAny_Int() {
        // Given
        let value = Value.int(42)
        
        // When
        let result = sut.convertValueToAny(value)
        
        // Then
        XCTAssertEqual(result as? Int, 42)
    }
    
    func testConvertValueToAny_Double() {
        // Given
        let value = Value.double(3.14159)
        
        // When
        let result = sut.convertValueToAny(value)
        
        // Then
        XCTAssertEqual(result as? Double, 3.14159, accuracy: 0.0001)
    }
    
    func testConvertValueToAny_String() {
        // Given
        let value = Value.string("test string")
        
        // When
        let result = sut.convertValueToAny(value)
        
        // Then
        XCTAssertEqual(result as? String, "test string")
    }
    
    func testConvertValueToAny_Array() {
        // Given
        let value = Value.array([
            Value.string("item1"),
            Value.int(2),
            Value.bool(false)
        ])
        
        // When
        let result = sut.convertValueToAny(value)
        
        // Then
        let array = result as? [Any]
        XCTAssertNotNil(array)
        XCTAssertEqual(array?.count, 3)
        XCTAssertEqual(array?[0] as? String, "item1")
        XCTAssertEqual(array?[1] as? Int, 2)
        XCTAssertEqual(array?[2] as? Bool, false)
    }
    
    func testConvertValueToAny_NestedObject() {
        // Given
        let value = Value.object([
            "name": Value.string("test"),
            "count": Value.int(5),
            "enabled": Value.bool(true),
            "nested": Value.object([
                "subfield": Value.string("value")
            ])
        ])
        
        // When
        let result = sut.convertValueToAny(value)
        
        // Then
        let dict = result as? [String: Any]
        XCTAssertNotNil(dict)
        XCTAssertEqual(dict?["name"] as? String, "test")
        XCTAssertEqual(dict?["count"] as? Int, 5)
        XCTAssertEqual(dict?["enabled"] as? Bool, true)
        
        let nested = dict?["nested"] as? [String: Any]
        XCTAssertNotNil(nested)
        XCTAssertEqual(nested?["subfield"] as? String, "value")
    }
    
    // MARK: - Schema Conversion Tests
    
    func testConvertSchemaToDict_SimpleSchema() {
        // Given
        let schema: [String: Value] = [
            "type": Value.string("object"),
            "required": Value.array([Value.string("filePath")]),
            "properties": Value.object([
                "filePath": Value.object([
                    "type": Value.string("string"),
                    "description": Value.string("Path to the file")
                ])
            ])
        ]
        
        // When
        let result = sut.convertSchemaToDict(schema)
        
        // Then
        XCTAssertEqual(result["type"] as? String, "object")
        
        let required = result["required"] as? [Any]
        XCTAssertNotNil(required)
        XCTAssertEqual(required?.count, 1)
        XCTAssertEqual(required?[0] as? String, "filePath")
        
        let properties = result["properties"] as? [String: Any]
        XCTAssertNotNil(properties)
        
        let filePath = properties?["filePath"] as? [String: Any]
        XCTAssertNotNil(filePath)
        XCTAssertEqual(filePath?["type"] as? String, "string")
        XCTAssertEqual(filePath?["description"] as? String, "Path to the file")
    }
    
    func testConvertSchemaToDict_ComplexSchema() {
        // Given
        let schema: [String: Value] = [
            "type": Value.string("object"),
            "required": Value.array([
                Value.string("projectNumber"),
                Value.string("options")
            ]),
            "properties": Value.object([
                "projectNumber": Value.object([
                    "type": Value.string("integer"),
                    "description": Value.string("The project number to select"),
                    "minimum": Value.int(1)
                ]),
                "options": Value.object([
                    "type": Value.string("object"),
                    "properties": Value.object([
                        "verbose": Value.object([
                            "type": Value.string("boolean"),
                            "default": Value.bool(false)
                        ])
                    ])
                ])
            ])
        ]
        
        // When
        let result = sut.convertSchemaToDict(schema)
        
        // Then
        XCTAssertEqual(result["type"] as? String, "object")
        
        let required = result["required"] as? [Any]
        XCTAssertNotNil(required)
        XCTAssertEqual(required?.count, 2)
        
        let properties = result["properties"] as? [String: Any]
        XCTAssertNotNil(properties)
        
        let projectNumber = properties?["projectNumber"] as? [String: Any]
        XCTAssertNotNil(projectNumber)
        XCTAssertEqual(projectNumber?["type"] as? String, "integer")
        XCTAssertEqual(projectNumber?["minimum"] as? Int, 1)
        
        let options = properties?["options"] as? [String: Any]
        XCTAssertNotNil(options)
        XCTAssertEqual(options?["type"] as? String, "object")
        
        let optionProps = options?["properties"] as? [String: Any]
        XCTAssertNotNil(optionProps)
        
        let verbose = optionProps?["verbose"] as? [String: Any]
        XCTAssertNotNil(verbose)
        XCTAssertEqual(verbose?["type"] as? String, "boolean")
        XCTAssertEqual(verbose?["default"] as? Bool, false)
    }
    
    func testConvertSchemaToDict_EmptySchema() {
        // Given
        let schema: [String: Value] = [:]
        
        // When
        let result = sut.convertSchemaToDict(schema)
        
        // Then
        XCTAssertTrue(result.isEmpty)
    }
    
    // MARK: - Tool Parameter Check Tests
    
    func testToolNeedsParameters_WithProperties() {
        // Given
        let tool = MCPTool(
            name: "test_tool",
            description: "Test tool",
            inputSchema: [
                "type": "object",
                "properties": ["filePath": ["type": "string"]]
            ]
        )
        ToolRegistry.shared.registerTools([tool])
        
        // When
        let result = sut.toolNeedsParameters(toolName: "test_tool")
        
        // Then
        XCTAssertTrue(result)
    }
    
    func testToolNeedsParameters_WithRequiredOnly() {
        // Given
        let tool = MCPTool(
            name: "test_tool",
            description: "Test tool",
            inputSchema: [
                "type": "object",
                "required": ["param1"]
            ]
        )
        ToolRegistry.shared.registerTools([tool])
        
        // When
        let result = sut.toolNeedsParameters(toolName: "test_tool")
        
        // Then
        XCTAssertTrue(result)
    }
    
    func testToolNeedsParameters_NoSchema() {
        // Given
        let tool = MCPTool(
            name: "test_tool",
            description: "Test tool",
            inputSchema: nil
        )
        ToolRegistry.shared.registerTools([tool])
        
        // When
        let result = sut.toolNeedsParameters(toolName: "test_tool")
        
        // Then
        XCTAssertTrue(result) // Default to true when no schema
    }
    
    func testToolNeedsParameters_EmptySchema() {
        // Given
        let tool = MCPTool(
            name: "test_tool",
            description: "Test tool",
            inputSchema: [:]
        )
        ToolRegistry.shared.registerTools([tool])
        
        // When
        let result = sut.toolNeedsParameters(toolName: "test_tool")
        
        // Then
        XCTAssertFalse(result)
    }
}

// MARK: - Mock Classes

class MockMessageHandler: ClientServerServiceMessageHandler {
    var messages: [(content: String, isFromServer: Bool)] = []
    var status: ClientServerStatus?
    var tools: [MCPTool] = []
    
    func addMessage(content: String, isFromServer: Bool) async {
        messages.append((content, isFromServer))
    }
    
    func updateStatus(_ status: ClientServerStatus) async {
        self.status = status
    }
    
    func updateTools(_ tools: [MCPTool]) async {
        self.tools = tools
    }
}


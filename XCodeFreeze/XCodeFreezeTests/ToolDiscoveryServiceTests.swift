import XCTest
@testable import XCodeFreeze
import MCP

class ToolDiscoveryServiceTests: XCTestCase {
    
    var toolDiscovery: ToolDiscoveryService!
    var mockClient: MockClient!
    
    override func setUp() {
        super.setUp()
        mockClient = MockClient()
        toolDiscovery = ToolDiscoveryService()
        toolDiscovery.setClient(mockClient)
    }
    
    override func tearDown() {
        toolDiscovery = nil
        mockClient = nil
        super.tearDown()
    }
    
    // MARK: - Single Parameter Tests
    
    func testCallToolWithSingleParameter() async {
        // Given
        let toolName = "read_file"
        let filePath = "/test/file.txt"
        let expectedContent = "File content"
        
        mockClient.mockResponse = ([.text(expectedContent)], false)
        
        // When
        let result = await toolDiscovery.callTool(name: toolName, text: filePath)
        
        // Then
        XCTAssertEqual(result, expectedContent)
        XCTAssertEqual(mockClient.lastCalledTool, toolName)
        XCTAssertNotNil(mockClient.lastArguments)
    }
    
    // MARK: - Multiple Parameter Tests
    
    func testCallToolWithJSONMultipleStringParameters() async {
        // Given
        let toolName = "create_doc"
        let jsonArgs = """
        {
            "filePath": "/test/newfile.swift",
            "content": "import Foundation\\n\\nclass TestClass {}"
        }
        """
        let expectedResponse = "Document created successfully"
        
        mockClient.mockResponse = ([.text(expectedResponse)], false)
        
        // When
        let result = await toolDiscovery.callToolWithJSON(name: toolName, jsonArguments: jsonArgs)
        
        // Then
        XCTAssertEqual(result, expectedResponse)
        XCTAssertEqual(mockClient.lastCalledTool, toolName)
        XCTAssertNotNil(mockClient.lastArguments)
        
        // Verify both parameters were passed
        if let args = mockClient.lastArguments {
            XCTAssertEqual(args.count, 2)
            XCTAssertNotNil(args["filePath"])
            XCTAssertNotNil(args["content"])
            
            if case .string(let path) = args["filePath"] {
                XCTAssertEqual(path, "/test/newfile.swift")
            } else {
                XCTFail("filePath should be a string")
            }
            
            if case .string(let content) = args["content"] {
                XCTAssertTrue(content.contains("TestClass"))
            } else {
                XCTFail("content should be a string")
            }
        }
    }
    
    func testCallToolWithJSONMixedParameterTypes() async {
        // Given
        let toolName = "analyze_swift_code"
        let jsonArgs = """
        {
            "filePath": "/test/file.swift",
            "startLine": 10,
            "endLine": 20,
            "entireFile": false
        }
        """
        let expectedResponse = "Analysis complete"
        
        mockClient.mockResponse = ([.text(expectedResponse)], false)
        
        // When
        let result = await toolDiscovery.callToolWithJSON(name: toolName, jsonArguments: jsonArgs)
        
        // Then
        XCTAssertEqual(result, expectedResponse)
        XCTAssertEqual(mockClient.lastCalledTool, toolName)
        XCTAssertNotNil(mockClient.lastArguments)
        
        // Verify all parameters with correct types
        if let args = mockClient.lastArguments {
            XCTAssertEqual(args.count, 4)
            
            if case .string(let path) = args["filePath"] {
                XCTAssertEqual(path, "/test/file.swift")
            } else {
                XCTFail("filePath should be a string")
            }
            
            if case .int(let start) = args["startLine"] {
                XCTAssertEqual(start, 10)
            } else {
                XCTFail("startLine should be an int")
            }
            
            if case .int(let end) = args["endLine"] {
                XCTAssertEqual(end, 20)
            } else {
                XCTFail("endLine should be an int")
            }
            
            if case .bool(let entire) = args["entireFile"] {
                XCTAssertFalse(entire)
            } else {
                XCTFail("entireFile should be a bool")
            }
        }
    }
    
    func testCallToolWithJSONArrayParameter() async {
        // Given
        let toolName = "analyze_swift_code"
        let jsonArgs = """
        {
            "filePath": "/test/file.swift",
            "checkGroups": ["syntax", "style", "safety"]
        }
        """
        let expectedResponse = "Analysis complete"
        
        mockClient.mockResponse = ([.text(expectedResponse)], false)
        
        // When
        let result = await toolDiscovery.callToolWithJSON(name: toolName, jsonArguments: jsonArgs)
        
        // Then
        XCTAssertEqual(result, expectedResponse)
        XCTAssertEqual(mockClient.lastCalledTool, toolName)
        XCTAssertNotNil(mockClient.lastArguments)
        
        // Verify array parameter is converted to JSON string
        if let args = mockClient.lastArguments {
            if case .string(let checkGroups) = args["checkGroups"] {
                XCTAssertTrue(checkGroups.contains("syntax"))
                XCTAssertTrue(checkGroups.contains("style"))
                XCTAssertTrue(checkGroups.contains("safety"))
            } else {
                XCTFail("checkGroups should be a string (JSON)")
            }
        }
    }
    
    func testCallToolWithInvalidJSON() async {
        // Given
        let toolName = "some_tool"
        let invalidJson = "not a json { invalid"
        let expectedResponse = "Fallback response"
        
        // Mock the fallback callTool response
        mockClient.mockResponse = ([.text(expectedResponse)], false)
        
        // When
        let result = await toolDiscovery.callToolWithJSON(name: toolName, jsonArguments: invalidJson)
        
        // Then
        XCTAssertEqual(result, expectedResponse)
        // Should fall back to single parameter call
        XCTAssertEqual(mockClient.lastCalledTool, toolName)
    }
    
    func testCallToolWithEmptyJSON() async {
        // Given
        let toolName = "list"
        let jsonArgs = "{}"
        let expectedResponse = "Tool list"
        
        mockClient.mockResponse = ([.text(expectedResponse)], false)
        
        // When
        let result = await toolDiscovery.callToolWithJSON(name: toolName, jsonArguments: jsonArgs)
        
        // Then
        XCTAssertEqual(result, expectedResponse)
        XCTAssertEqual(mockClient.lastCalledTool, toolName)
        XCTAssertNotNil(mockClient.lastArguments)
        XCTAssertEqual(mockClient.lastArguments?.count, 0)
    }
    
    func testCallToolErrorHandling() async {
        // Given
        let toolName = "error_tool"
        let jsonArgs = """
        {"param": "value"}
        """
        
        mockClient.mockResponse = ([.text("Error message")], true)
        
        // When
        let result = await toolDiscovery.callToolWithJSON(name: toolName, jsonArguments: jsonArgs)
        
        // Then
        XCTAssertEqual(result, "Error from server")
    }
}

// MARK: - Mock Client

class MockClient: Client {
    var mockResponse: ([ContentType], Bool) = ([], false)
    var lastCalledTool: String?
    var lastArguments: [String: Value]?
    
    override func callTool(name: String, arguments: [String: Value]) async throws -> ([ContentType], Bool) {
        lastCalledTool = name
        lastArguments = arguments
        return mockResponse
    }
}
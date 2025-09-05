import XCTest
import Combine
@testable import XCodeFreeze

/// Comprehensive unit tests for MCPToolDiscoveryService
class MCPToolDiscoveryServiceTests: XCTestCase {
    
    var communicationService: MCPCommunicationService!
    var discoveryService: MCPToolDiscoveryService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        communicationService = await MCPCommunicationService()
        discoveryService = await MCPToolDiscoveryService(communicationService: communicationService)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        cancellables = nil
        discoveryService = nil
        await communicationService?.disconnect()
        communicationService = nil
        try await super.tearDown()
    }
    
    // MARK: - Tool Model Tests
    
    func testToolCreation() {
        let parameter = MCPToolDiscoveryService.Tool.Parameter(
            name: "filePath",
            type: .string,
            description: "Path to the file",
            required: true,
            defaultValue: nil,
            enumValues: nil
        )
        
        let tool = MCPToolDiscoveryService.Tool(
            name: "read_file",
            description: "Read contents of a file",
            parameters: [parameter],
            category: "file",
            examples: ["read_file filePath: /path/to/file"]
        )
        
        XCTAssertEqual(tool.name, "read_file")
        XCTAssertEqual(tool.description, "Read contents of a file")
        XCTAssertEqual(tool.parameters.count, 1)
        XCTAssertEqual(tool.parameters[0].name, "filePath")
        XCTAssertEqual(tool.category, "file")
        XCTAssertEqual(tool.examples?.count, 1)
    }
    
    func testToolEquality() {
        let param1 = MCPToolDiscoveryService.Tool.Parameter(
            name: "test",
            type: .string,
            description: nil,
            required: false,
            defaultValue: nil,
            enumValues: nil
        )
        
        let tool1 = MCPToolDiscoveryService.Tool(
            name: "test_tool",
            description: "Test",
            parameters: [param1],
            category: nil,
            examples: nil
        )
        
        let tool2 = MCPToolDiscoveryService.Tool(
            name: "test_tool",
            description: "Test",
            parameters: [param1],
            category: nil,
            examples: nil
        )
        
        // Tools should be equal based on content, not ID
        XCTAssertEqual(tool1.name, tool2.name)
        XCTAssertEqual(tool1.description, tool2.description)
        XCTAssertNotEqual(tool1.id, tool2.id) // Different UUIDs
    }
    
    func testParameterTypes() {
        let types: [MCPToolDiscoveryService.Tool.ParameterType] = [
            .string, .integer, .boolean, .number, .array, .object
        ]
        
        for type in types {
            XCTAssertFalse(type.rawValue.isEmpty)
        }
        
        // Test encoding/decoding
        for type in types {
            let encoded = type.rawValue
            let decoded = MCPToolDiscoveryService.Tool.ParameterType(rawValue: encoded)
            XCTAssertEqual(decoded, type)
        }
    }
    
    func testParameterWithEnumValues() {
        let parameter = MCPToolDiscoveryService.Tool.Parameter(
            name: "mode",
            type: .string,
            description: "Operation mode",
            required: true,
            defaultValue: "read",
            enumValues: ["read", "write", "append"]
        )
        
        XCTAssertEqual(parameter.enumValues?.count, 3)
        XCTAssertTrue(parameter.enumValues?.contains("read") ?? false)
        XCTAssertEqual(parameter.defaultValue, "read")
    }
    
    // MARK: - Tool Discovery Tests
    
    func testInitialState() async {
        await MainActor.run {
            XCTAssertTrue(discoveryService.discoveredTools.isEmpty)
            XCTAssertFalse(discoveryService.isDiscovering)
            XCTAssertNil(discoveryService.lastDiscoveryError)
        }
    }
    
    func testDiscoveryStatePublisher() async {
        var states: [Bool] = []
        
        await MainActor.run {
            discoveryService.$isDiscovering
                .sink { state in
                    states.append(state)
                }
                .store(in: &cancellables)
        }
        
        await Task.yield()
        XCTAssertEqual(states.last, false)
    }
    
    func testDiscoveredToolsPublisher() async {
        var toolCounts: [Int] = []
        
        await MainActor.run {
            discoveryService.$discoveredTools
                .map { $0.count }
                .sink { count in
                    toolCounts.append(count)
                }
                .store(in: &cancellables)
        }
        
        await Task.yield()
        XCTAssertEqual(toolCounts.last, 0)
    }
    
    // MARK: - Tool Search Tests
    
    func testSearchTools() async {
        // Manually add some test tools
        let tools = [
            MCPToolDiscoveryService.Tool(
                name: "read_file",
                description: "Read file contents",
                parameters: [],
                category: "file",
                examples: nil
            ),
            MCPToolDiscoveryService.Tool(
                name: "write_file",
                description: "Write to a file",
                parameters: [],
                category: "file",
                examples: nil
            ),
            MCPToolDiscoveryService.Tool(
                name: "run_project",
                description: "Run the project",
                parameters: [],
                category: "project",
                examples: nil
            )
        ]
        
        await MainActor.run {
            // Use reflection to set tools for testing
            // In production, we'd use dependency injection
            discoveryService.discoveredTools = tools
        }
        
        // Test search by name
        let fileTools = await discoveryService.searchTools(query: "file")
        XCTAssertEqual(fileTools.count, 2)
        
        // Test search by description
        let readTools = await discoveryService.searchTools(query: "read")
        XCTAssertEqual(readTools.count, 1)
        
        // Test search by category
        let projectTools = await discoveryService.searchTools(query: "project")
        XCTAssertEqual(projectTools.count, 1)
        
        // Test case insensitive search
        let upperCaseSearch = await discoveryService.searchTools(query: "FILE")
        XCTAssertEqual(upperCaseSearch.count, 2)
    }
    
    func testToolsByCategory() async {
        let tools = [
            MCPToolDiscoveryService.Tool(
                name: "tool1",
                description: "Test",
                parameters: [],
                category: "file",
                examples: nil
            ),
            MCPToolDiscoveryService.Tool(
                name: "tool2",
                description: "Test",
                parameters: [],
                category: "file",
                examples: nil
            ),
            MCPToolDiscoveryService.Tool(
                name: "tool3",
                description: "Test",
                parameters: [],
                category: "project",
                examples: nil
            )
        ]
        
        await MainActor.run {
            discoveryService.discoveredTools = tools
        }
        
        let fileTools = await discoveryService.toolsByCategory("file")
        XCTAssertEqual(fileTools.count, 2)
        
        let projectTools = await discoveryService.toolsByCategory("project")
        XCTAssertEqual(projectTools.count, 1)
        
        let systemTools = await discoveryService.toolsByCategory("system")
        XCTAssertEqual(systemTools.count, 0)
    }
    
    func testToolByName() async {
        let tool = MCPToolDiscoveryService.Tool(
            name: "specific_tool",
            description: "Test",
            parameters: [],
            category: nil,
            examples: nil
        )
        
        await MainActor.run {
            discoveryService.discoveredTools = [tool]
        }
        
        let found = await discoveryService.tool(named: "specific_tool")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "specific_tool")
        
        let notFound = await discoveryService.tool(named: "nonexistent")
        XCTAssertNil(notFound)
    }
    
    // MARK: - Parameter Validation Tests
    
    func testParameterTypeValidation() async {
        let tool = MCPToolDiscoveryService.Tool(
            name: "test",
            description: "Test",
            parameters: [
                MCPToolDiscoveryService.Tool.Parameter(
                    name: "stringParam",
                    type: .string,
                    description: nil,
                    required: true,
                    defaultValue: nil,
                    enumValues: nil
                ),
                MCPToolDiscoveryService.Tool.Parameter(
                    name: "intParam",
                    type: .integer,
                    description: nil,
                    required: true,
                    defaultValue: nil,
                    enumValues: nil
                ),
                MCPToolDiscoveryService.Tool.Parameter(
                    name: "boolParam",
                    type: .boolean,
                    description: nil,
                    required: false,
                    defaultValue: nil,
                    enumValues: nil
                )
            ],
            category: nil,
            examples: nil
        )
        
        // Valid arguments
        do {
            _ = try await discoveryService.executeTool(tool, arguments: [
                "stringParam": "test",
                "intParam": 42
            ])
        } catch MCPError.notConnected {
            // Expected when not connected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Missing required parameter
        do {
            _ = try await discoveryService.executeTool(tool, arguments: [
                "stringParam": "test"
            ])
            XCTFail("Should have thrown missing parameter error")
        } catch ToolError.missingRequiredParameter(let param) {
            XCTAssertEqual(param, "intParam")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
        
        // Wrong type
        do {
            _ = try await discoveryService.executeTool(tool, arguments: [
                "stringParam": 123, // Should be string
                "intParam": 42
            ])
            XCTFail("Should have thrown invalid type error")
        } catch ToolError.invalidParameterType(let param, _) {
            XCTAssertEqual(param, "stringParam")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testEnumValueValidation() async {
        let tool = MCPToolDiscoveryService.Tool(
            name: "test",
            description: "Test",
            parameters: [
                MCPToolDiscoveryService.Tool.Parameter(
                    name: "mode",
                    type: .string,
                    description: nil,
                    required: true,
                    defaultValue: nil,
                    enumValues: ["read", "write", "append"]
                )
            ],
            category: nil,
            examples: nil
        )
        
        // Valid enum value
        do {
            _ = try await discoveryService.executeTool(tool, arguments: [
                "mode": "read"
            ])
        } catch MCPError.notConnected {
            // Expected when not connected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Invalid enum value
        do {
            _ = try await discoveryService.executeTool(tool, arguments: [
                "mode": "delete" // Not in enum
            ])
            XCTFail("Should have thrown invalid enum error")
        } catch ToolError.invalidEnumValue(let param, let allowed) {
            XCTAssertEqual(param, "mode")
            XCTAssertEqual(allowed, ["read", "write", "append"])
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - OpenAI Export Tests
    
    func testExportForOpenAI() async {
        let tool = MCPToolDiscoveryService.Tool(
            name: "test_function",
            description: "A test function",
            parameters: [
                MCPToolDiscoveryService.Tool.Parameter(
                    name: "input",
                    type: .string,
                    description: "The input string",
                    required: true,
                    defaultValue: nil,
                    enumValues: nil
                ),
                MCPToolDiscoveryService.Tool.Parameter(
                    name: "count",
                    type: .integer,
                    description: "Number of times",
                    required: false,
                    defaultValue: "1",
                    enumValues: nil
                )
            ],
            category: nil,
            examples: nil
        )
        
        await MainActor.run {
            discoveryService.discoveredTools = [tool]
        }
        
        let exported = await discoveryService.exportForOpenAI()
        
        XCTAssertEqual(exported.count, 1)
        
        let function = exported[0]
        XCTAssertEqual(function["type"] as? String, "function")
        
        let functionDef = function["function"] as? [String: Any]
        XCTAssertEqual(functionDef?["name"] as? String, "test_function")
        XCTAssertEqual(functionDef?["description"] as? String, "A test function")
        
        let parameters = functionDef?["parameters"] as? [String: Any]
        XCTAssertEqual(parameters?["type"] as? String, "object")
        
        let properties = parameters?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["input"])
        XCTAssertNotNil(properties?["count"])
        
        let required = parameters?["required"] as? [String]
        XCTAssertEqual(required, ["input"])
    }
    
    // MARK: - Error Tests
    
    func testToolErrors() {
        let errors: [ToolError] = [
            .missingRequiredParameter("test"),
            .invalidParameterType("param", expected: "string"),
            .invalidEnumValue("mode", allowed: ["a", "b"]),
            .toolNotFound("unknown"),
            .executionFailed("test failure")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
    
    // MARK: - Performance Tests
    
    func testSearchPerformance() async {
        // Create many tools for performance testing
        var tools: [MCPToolDiscoveryService.Tool] = []
        for i in 0..<1000 {
            tools.append(MCPToolDiscoveryService.Tool(
                name: "tool_\(i)",
                description: "Description for tool \(i)",
                parameters: [],
                category: i % 2 == 0 ? "file" : "project",
                examples: nil
            ))
        }
        
        await MainActor.run {
            discoveryService.discoveredTools = tools
        }
        
        measure {
            _ = discoveryService.searchTools(query: "tool_5")
        }
    }
    
    func testExportPerformance() async {
        var tools: [MCPToolDiscoveryService.Tool] = []
        for i in 0..<100 {
            tools.append(MCPToolDiscoveryService.Tool(
                name: "tool_\(i)",
                description: "Description",
                parameters: [
                    MCPToolDiscoveryService.Tool.Parameter(
                        name: "param",
                        type: .string,
                        description: "Test",
                        required: true,
                        defaultValue: nil,
                        enumValues: nil
                    )
                ],
                category: nil,
                examples: nil
            ))
        }
        
        await MainActor.run {
            discoveryService.discoveredTools = tools
        }
        
        measure {
            _ = discoveryService.exportForOpenAI()
        }
    }
}
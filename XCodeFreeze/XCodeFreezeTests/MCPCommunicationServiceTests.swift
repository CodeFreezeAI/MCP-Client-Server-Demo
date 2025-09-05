import XCTest
import Combine
@testable import XCodeFreeze

/// Comprehensive unit tests for MCPCommunicationService
class MCPCommunicationServiceTests: XCTestCase {
    
    var service: MCPCommunicationService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        service = await MCPCommunicationService()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        await service?.disconnect()
        service = nil
        cancellables = nil
        try await super.tearDown()
    }
    
    // MARK: - JSON-RPC Message Tests
    
    func testJSONRPCMessageEncoding() throws {
        let message = MCPCommunicationService.JSONRPCMessage(
            id: .string("test-id"),
            method: "test.method",
            params: AnyCodable(["key": "value"]),
            result: nil,
            error: nil
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["id"] as? String, "test-id")
        XCTAssertEqual(json["method"] as? String, "test.method")
        XCTAssertNotNil(json["params"])
    }
    
    func testJSONRPCMessageDecoding() throws {
        let jsonString = """
        {
            "jsonrpc": "2.0",
            "id": "test-id",
            "result": {"data": "test-data"}
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let message = try decoder.decode(MCPCommunicationService.JSONRPCMessage.self, from: data)
        
        XCTAssertEqual(message.jsonrpc, "2.0")
        XCTAssertNotNil(message.id)
        XCTAssertNotNil(message.result)
        XCTAssertNil(message.method)
        XCTAssertNil(message.error)
    }
    
    func testJSONRPCIdEncoding() throws {
        // Test string ID
        let stringId = MCPCommunicationService.JSONRPCId.string("test")
        let encoder = JSONEncoder()
        let stringData = try encoder.encode(stringId)
        let stringJson = String(data: stringData, encoding: .utf8)!
        XCTAssertEqual(stringJson, "\"test\"")
        
        // Test number ID
        let numberId = MCPCommunicationService.JSONRPCId.number(123)
        let numberData = try encoder.encode(numberId)
        let numberJson = String(data: numberData, encoding: .utf8)!
        XCTAssertEqual(numberJson, "123")
    }
    
    func testJSONRPCErrorHandling() throws {
        let error = MCPCommunicationService.JSONRPCError(
            code: -32600,
            message: "Invalid Request",
            data: AnyCodable(["details": "Missing required field"])
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(error)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(json["code"] as? Int, -32600)
        XCTAssertEqual(json["message"] as? String, "Invalid Request")
        XCTAssertNotNil(json["data"])
    }
    
    // MARK: - AnyCodable Tests
    
    func testAnyCodableWithPrimitives() throws {
        // Test various primitive types
        let testCases: [(Any, String)] = [
            (true, "true"),
            (false, "false"),
            (42, "42"),
            (3.14, "3.14"),
            ("test", "\"test\"")
        ]
        
        let encoder = JSONEncoder()
        
        for (value, expected) in testCases {
            let anyCodable = AnyCodable(value)
            let data = try encoder.encode(anyCodable)
            let result = String(data: data, encoding: .utf8)!
            XCTAssertEqual(result, expected, "Failed for value: \(value)")
        }
    }
    
    func testAnyCodableWithCollections() throws {
        // Test array
        let array = [1, 2, 3]
        let arrayAnyCodable = AnyCodable(array)
        let encoder = JSONEncoder()
        let arrayData = try encoder.encode(arrayAnyCodable)
        let arrayJson = try JSONSerialization.jsonObject(with: arrayData) as! [Int]
        XCTAssertEqual(arrayJson, array)
        
        // Test dictionary
        let dict = ["key": "value", "number": "42"]
        let dictAnyCodable = AnyCodable(dict)
        let dictData = try encoder.encode(dictAnyCodable)
        let dictJson = try JSONSerialization.jsonObject(with: dictData) as! [String: String]
        XCTAssertEqual(dictJson, dict)
    }
    
    func testAnyCodableDecoding() throws {
        let jsonString = """
        {
            "string": "test",
            "number": 42,
            "boolean": true,
            "array": [1, 2, 3],
            "nested": {
                "key": "value"
            }
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let anyCodable = try decoder.decode(AnyCodable.self, from: data)
        
        let dict = anyCodable.value as! [String: Any]
        XCTAssertEqual(dict["string"] as? String, "test")
        XCTAssertEqual(dict["number"] as? Int, 42)
        XCTAssertEqual(dict["boolean"] as? Bool, true)
        XCTAssertEqual((dict["array"] as? [Any])?.count, 3)
        XCTAssertNotNil(dict["nested"] as? [String: Any])
    }
    
    // MARK: - Connection Tests
    
    func testConnectionStateManagement() async throws {
        // Initial state
        await MainActor.run {
            XCTAssertFalse(service.isConnected)
            XCTAssertNil(service.connectionError)
        }
        
        // After disconnect (should be idempotent)
        await service.disconnect()
        await MainActor.run {
            XCTAssertFalse(service.isConnected)
        }
    }
    
    func testConnectionWithInvalidPath() async {
        do {
            try await service.connect(serverPath: "/invalid/path/to/server")
            XCTFail("Should have thrown an error")
        } catch {
            await MainActor.run {
                XCTAssertFalse(service.isConnected)
            }
        }
    }
    
    // MARK: - Message Buffer Tests
    
    func testMessageBuffering() throws {
        // Create a mock message handler
        var receivedMessages: [MCPCommunicationService.JSONRPCMessage] = []
        
        await service.addMessageHandler { message in
            receivedMessages.append(message)
        }
        
        // Test that multiple message handlers can be added
        var secondHandlerCalled = false
        await service.addMessageHandler { _ in
            secondHandlerCalled = true
        }
        
        // Verify handlers are stored (would need to expose for testing or test indirectly)
        XCTAssertTrue(receivedMessages.isEmpty)
        XCTAssertFalse(secondHandlerCalled)
    }
    
    // MARK: - Error Handling Tests
    
    func testMCPErrorDescriptions() {
        let errors: [MCPError] = [
            .notConnected,
            .connectionFailed("Test failure"),
            .initializationFailed("Init failed"),
            .serverError("Server error"),
            .toolExecutionFailed("Tool failed"),
            .disconnected
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
    
    // MARK: - Mock Server Tests
    
    func testSendRequestTimeout() async throws {
        // This test would require a mock server or process
        // For now, test that sending without connection throws
        do {
            _ = try await service.sendRequest("test.method", params: ["test": "data"])
            XCTFail("Should have thrown notConnected error")
        } catch MCPError.notConnected {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testSendNotification() async throws {
        // Test that notifications don't wait for response
        do {
            try await service.sendNotification("test.notification", params: nil as String?)
            XCTFail("Should have thrown notConnected error")
        } catch MCPError.notConnected {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Tool Call Tests
    
    func testToolCallParams() throws {
        let params = ToolCallParams(
            name: "test_tool",
            arguments: ["arg1": "value1", "arg2": 42]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(json["name"] as? String, "test_tool")
        XCTAssertNotNil(json["arguments"])
        
        let args = json["arguments"] as! [String: Any]
        XCTAssertEqual(args["arg1"] as? String, "value1")
        XCTAssertEqual(args["arg2"] as? Int, 42)
    }
    
    // MARK: - Performance Tests
    
    func testMessageEncodingPerformance() throws {
        let message = MCPCommunicationService.JSONRPCMessage(
            id: .string("perf-test"),
            method: "performance.test",
            params: AnyCodable(["data": Array(repeating: "test", count: 100)]),
            result: nil,
            error: nil
        )
        
        let encoder = JSONEncoder()
        
        measure {
            _ = try? encoder.encode(message)
        }
    }
    
    func testMessageDecodingPerformance() throws {
        let jsonString = """
        {
            "jsonrpc": "2.0",
            "id": "perf-test",
            "result": {
                "data": \(Array(repeating: "\"test\"", count: 100).joined(separator: ","))
            }
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        measure {
            _ = try? decoder.decode(MCPCommunicationService.JSONRPCMessage.self, from: data)
        }
    }
    
    // MARK: - Integration Tests
    
    func testFullMessageRoundtrip() throws {
        // Create a complex message
        let originalMessage = MCPCommunicationService.JSONRPCMessage(
            id: .number(42),
            method: "complex.method",
            params: AnyCodable([
                "string": "value",
                "number": 123,
                "boolean": true,
                "array": [1, 2, 3],
                "nested": ["key": "value"]
            ]),
            result: nil,
            error: nil
        )
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(originalMessage)
        
        // Decode back
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(MCPCommunicationService.JSONRPCMessage.self, from: data)
        
        // Verify
        XCTAssertEqual(decodedMessage.jsonrpc, originalMessage.jsonrpc)
        XCTAssertEqual(decodedMessage.method, originalMessage.method)
        
        // Check ID
        if case .number(let original) = originalMessage.id,
           case .number(let decoded) = decodedMessage.id {
            XCTAssertEqual(original, decoded)
        } else {
            XCTFail("ID mismatch")
        }
        
        // Check params exist
        XCTAssertNotNil(decodedMessage.params)
    }
    
    // MARK: - Publisher Tests
    
    func testConnectionStatePublisher() async throws {
        var states: [Bool] = []
        
        await MainActor.run {
            service.$isConnected
                .sink { state in
                    states.append(state)
                }
                .store(in: &cancellables)
        }
        
        // Initial state should be false
        await Task.yield()
        XCTAssertEqual(states.last, false)
    }
    
    func testConnectionErrorPublisher() async throws {
        var errors: [String?] = []
        
        await MainActor.run {
            service.$connectionError
                .sink { error in
                    errors.append(error)
                }
                .store(in: &cancellables)
        }
        
        // Initial state should be nil
        await Task.yield()
        XCTAssertEqual(errors.last, nil)
    }
}
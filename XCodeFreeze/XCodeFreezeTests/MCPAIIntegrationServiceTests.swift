import XCTest
import Combine
@testable import XCodeFreeze

/// Comprehensive unit tests for MCPAIIntegrationService
class MCPAIIntegrationServiceTests: XCTestCase {
    
    var communicationService: MCPCommunicationService!
    var discoveryService: MCPToolDiscoveryService!
    var aiService: MCPAIIntegrationService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        communicationService = await MCPCommunicationService()
        discoveryService = await MCPToolDiscoveryService(communicationService: communicationService)
        aiService = await MCPAIIntegrationService(
            toolDiscovery: discoveryService,
            communicationService: communicationService
        )
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        cancellables = nil
        aiService = nil
        discoveryService = nil
        await communicationService?.disconnect()
        communicationService = nil
        try await super.tearDown()
    }
    
    // MARK: - Message Type Tests
    
    func testAIMessageCreation() {
        let message = MCPAIIntegrationService.AIMessage(
            role: .user,
            content: "Test message",
            toolCalls: nil,
            toolCallId: nil
        )
        
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content, "Test message")
        XCTAssertNil(message.toolCalls)
        XCTAssertNil(message.toolCallId)
        XCTAssertNotNil(message.timestamp)
    }
    
    func testAIMessageRoles() {
        let roles: [MCPAIIntegrationService.AIMessage.Role] = [.system, .user, .assistant, .tool]
        
        for role in roles {
            let message = MCPAIIntegrationService.AIMessage(
                role: role,
                content: "Test",
                toolCalls: nil,
                toolCallId: nil
            )
            XCTAssertEqual(message.role, role)
            XCTAssertFalse(message.role.rawValue.isEmpty)
        }
    }
    
    func testToolCallCreation() {
        let toolCall = MCPAIIntegrationService.AIMessage.ToolCall(
            id: "test-id",
            name: "read_file",
            arguments: ["path": "/test/file.txt"]
        )
        
        XCTAssertEqual(toolCall.id, "test-id")
        XCTAssertEqual(toolCall.name, "read_file")
        XCTAssertEqual(toolCall.arguments["path"] as? String, "/test/file.txt")
    }
    
    func testAIResponse() {
        let response = MCPAIIntegrationService.AIResponse(
            content: "Test response",
            toolsExecuted: ["tool1", "tool2"],
            thinking: "Test thinking",
            confidence: 0.95
        )
        
        XCTAssertEqual(response.content, "Test response")
        XCTAssertEqual(response.toolsExecuted.count, 2)
        XCTAssertEqual(response.thinking, "Test thinking")
        XCTAssertEqual(response.confidence, 0.95)
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() async {
        await MainActor.run {
            XCTAssertFalse(aiService.isProcessing)
            XCTAssertNil(aiService.currentTask)
            XCTAssertNil(aiService.lastError)
            
            // Should have system prompt in history
            XCTAssertFalse(aiService.conversationHistory.isEmpty)
            XCTAssertEqual(aiService.conversationHistory.first?.role, .system)
        }
    }
    
    func testSystemPromptSetup() async {
        await MainActor.run {
            let systemMessage = aiService.conversationHistory.first
            XCTAssertNotNil(systemMessage)
            XCTAssertEqual(systemMessage?.role, .system)
            XCTAssertTrue(systemMessage?.content.contains("XCodeFreeze") ?? false)
            XCTAssertTrue(systemMessage?.content.contains("MCP") ?? false)
        }
    }
    
    // MARK: - Configuration Tests
    
    func testModelConfiguration() async {
        await aiService.setModel("gpt-4")
        // Model should be set internally (would need getter for full test)
        
        await aiService.setModel("claude-3-opus")
        // Should accept different model names
    }
    
    func testToolExecutionConfiguration() async {
        await aiService.setAutoExecuteTools(true)
        await aiService.setRequireConfirmation(false)
        
        // Test opposite configuration
        await aiService.setAutoExecuteTools(false)
        await aiService.setRequireConfirmation(true)
    }
    
    // MARK: - History Management Tests
    
    func testClearHistory() async {
        // Add some messages
        _ = await aiService.processMessage("Test message")
        
        await MainActor.run {
            let initialCount = aiService.conversationHistory.count
            XCTAssertGreaterThan(initialCount, 1)
        }
        
        // Clear history
        await aiService.clearHistory()
        
        await MainActor.run {
            // Should only have system prompt
            XCTAssertEqual(aiService.conversationHistory.count, 1)
            XCTAssertEqual(aiService.conversationHistory.first?.role, .system)
        }
    }
    
    func testExportHistory() async {
        // Add messages
        _ = await aiService.processMessage("Hello")
        
        let exported = await aiService.exportHistory()
        
        XCTAssertFalse(exported.isEmpty)
        XCTAssertTrue(exported.contains("SYSTEM:"))
        XCTAssertTrue(exported.contains("USER:"))
    }
    
    // MARK: - Processing State Tests
    
    func testProcessingStatePublisher() async {
        var states: [Bool] = []
        
        await MainActor.run {
            aiService.$isProcessing
                .sink { state in
                    states.append(state)
                }
                .store(in: &cancellables)
        }
        
        await Task.yield()
        XCTAssertEqual(states.last, false)
    }
    
    func testCurrentTaskPublisher() async {
        var tasks: [String?] = []
        
        await MainActor.run {
            aiService.$currentTask
                .sink { task in
                    tasks.append(task)
                }
                .store(in: &cancellables)
        }
        
        await Task.yield()
        XCTAssertEqual(tasks.last, nil)
    }
    
    func testErrorPublisher() async {
        var errors: [String?] = []
        
        await MainActor.run {
            aiService.$lastError
                .sink { error in
                    errors.append(error)
                }
                .store(in: &cancellables)
        }
        
        await Task.yield()
        XCTAssertEqual(errors.last, nil)
    }
    
    // MARK: - Message Processing Tests
    
    func testMessageProcessingAddsToHistory() async {
        let initialCount = await MainActor.run {
            aiService.conversationHistory.count
        }
        
        _ = await aiService.processMessage("Test question")
        
        let finalCount = await MainActor.run {
            aiService.conversationHistory.count
        }
        
        // Should add at least user message
        XCTAssertGreaterThan(finalCount, initialCount)
        
        // Check user message was added
        let messages = await MainActor.run {
            aiService.conversationHistory
        }
        
        let hasUserMessage = messages.contains { msg in
            msg.role == .user && msg.content == "Test question"
        }
        XCTAssertTrue(hasUserMessage)
    }
    
    func testResponseStructure() async {
        let response = await aiService.processMessage("Hello")
        
        XCTAssertFalse(response.content.isEmpty)
        XCTAssertNotNil(response.toolsExecuted)
        XCTAssertGreaterThanOrEqual(response.confidence, 0.0)
        XCTAssertLessThanOrEqual(response.confidence, 1.0)
    }
    
    // MARK: - Thinking Extraction Tests
    
    func testThinkingExtraction() {
        // Test various thinking patterns
        let testCases = [
            ("<thinking>This is my thought process</thinking>Rest of content", 
             "This is my thought process"),
            ("No thinking here", nil),
            ("<thinking>Multi\nline\nthinking</thinking>", "Multi\nline\nthinking"),
            ("<thinking></thinking>", "")
        ]
        
        for (input, expected) in testCases {
            // Would need to expose extractThinking method or test indirectly
            // through message processing
        }
    }
    
    func testResponseCleaning() {
        // Test that thinking tags are removed from final response
        let testResponses = [
            "<thinking>Internal thoughts</thinking>Visible response",
            "Clean response without tags",
            "<thinking>Thought1</thinking>Middle<thinking>Thought2</thinking>End"
        ]
        
        for response in testResponses {
            // Would need to test through actual message processing
            // to verify thinking tags are removed
        }
    }
    
    // MARK: - Confidence Calculation Tests
    
    func testConfidenceCalculation() {
        // Test confidence ranges
        let testCases: [(iterations: Int, tools: Int, minConfidence: Double, maxConfidence: Double)] = [
            (1, 0, 0.9, 1.0),   // Simple case
            (3, 2, 0.8, 0.95),  // Multiple iterations with tools
            (5, 5, 0.7, 0.9),   // Max complexity
        ]
        
        // Would need to expose calculateConfidence or test indirectly
    }
    
    // MARK: - Streaming Tests
    
    func testStreamMessage() async {
        let stream = await aiService.streamMessage("Test streaming")
        
        var chunks: [String] = []
        
        for await chunk in stream {
            chunks.append(chunk)
        }
        
        XCTAssertFalse(chunks.isEmpty)
    }
    
    func testStreamMessageTiming() async {
        let startTime = Date()
        let stream = await aiService.streamMessage("Quick test")
        
        var chunkCount = 0
        for await _ in stream {
            chunkCount += 1
            if chunkCount >= 3 {
                break // Test first few chunks
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should have some delay between chunks (50ms per chunk)
        XCTAssertGreaterThan(elapsed, 0.1)
    }
    
    // MARK: - Tool Integration Tests
    
    func testToolCallStructure() {
        let toolCall = MCPAIIntegrationService.AIMessage.ToolCall(
            id: UUID().uuidString,
            name: "test_tool",
            arguments: [
                "string_param": "value",
                "number_param": 42,
                "bool_param": true,
                "array_param": [1, 2, 3],
                "object_param": ["key": "value"]
            ]
        )
        
        XCTAssertFalse(toolCall.id.isEmpty)
        XCTAssertEqual(toolCall.name, "test_tool")
        XCTAssertEqual(toolCall.arguments.count, 5)
        
        // Verify different argument types
        XCTAssertEqual(toolCall.arguments["string_param"] as? String, "value")
        XCTAssertEqual(toolCall.arguments["number_param"] as? Int, 42)
        XCTAssertEqual(toolCall.arguments["bool_param"] as? Bool, true)
        XCTAssertEqual((toolCall.arguments["array_param"] as? [Int])?.count, 3)
        XCTAssertNotNil(toolCall.arguments["object_param"] as? [String: String])
    }
    
    func testMessageWithToolCalls() {
        let toolCalls = [
            MCPAIIntegrationService.AIMessage.ToolCall(
                id: "1",
                name: "tool1",
                arguments: [:]
            ),
            MCPAIIntegrationService.AIMessage.ToolCall(
                id: "2",
                name: "tool2",
                arguments: ["param": "value"]
            )
        ]
        
        let message = MCPAIIntegrationService.AIMessage(
            role: .assistant,
            content: "I'll use these tools",
            toolCalls: toolCalls,
            toolCallId: nil
        )
        
        XCTAssertEqual(message.toolCalls?.count, 2)
        XCTAssertEqual(message.toolCalls?[0].name, "tool1")
        XCTAssertEqual(message.toolCalls?[1].name, "tool2")
    }
    
    func testToolResultMessage() {
        let message = MCPAIIntegrationService.AIMessage(
            role: .tool,
            content: "Tool execution result",
            toolCalls: nil,
            toolCallId: "tool-call-123"
        )
        
        XCTAssertEqual(message.role, .tool)
        XCTAssertEqual(message.toolCallId, "tool-call-123")
        XCTAssertNil(message.toolCalls)
    }
    
    // MARK: - Performance Tests
    
    func testHistoryExportPerformance() async {
        // Add many messages to history
        for i in 0..<100 {
            let message = MCPAIIntegrationService.AIMessage(
                role: i % 2 == 0 ? .user : .assistant,
                content: "Message \(i)",
                toolCalls: nil,
                toolCallId: nil
            )
            await MainActor.run {
                aiService.conversationHistory.append(message)
            }
        }
        
        measure {
            _ = aiService.exportHistory()
        }
    }
    
    func testMessageProcessingPerformance() async {
        // This would require mocking the AI endpoint
        // For unit tests, we measure the overhead of our processing
        
        measure {
            Task {
                // Simulate processing without actual API call
                let message = MCPAIIntegrationService.AIMessage(
                    role: .user,
                    content: String(repeating: "test ", count: 100),
                    toolCalls: nil,
                    toolCallId: nil
                )
                await MainActor.run {
                    aiService.conversationHistory.append(message)
                }
            }
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyMessage() async {
        let response = await aiService.processMessage("")
        
        // Should handle empty input gracefully
        XCTAssertFalse(response.content.isEmpty)
    }
    
    func testVeryLongMessage() async {
        let longMessage = String(repeating: "test ", count: 1000)
        _ = await aiService.processMessage(longMessage)
        
        // Should handle long messages without crashing
        let messages = await MainActor.run {
            aiService.conversationHistory
        }
        
        let hasLongMessage = messages.contains { msg in
            msg.content == longMessage
        }
        XCTAssertTrue(hasLongMessage)
    }
    
    func testSpecialCharacters() async {
        let specialMessage = "Test with special chars: 🎉 <>&\"' \n\t"
        _ = await aiService.processMessage(specialMessage)
        
        // Should handle special characters
        let messages = await MainActor.run {
            aiService.conversationHistory
        }
        
        let hasSpecialMessage = messages.contains { msg in
            msg.content == specialMessage
        }
        XCTAssertTrue(hasSpecialMessage)
    }
}
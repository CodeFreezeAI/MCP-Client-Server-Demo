// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import MCP

public class MCPClientManager {
    private var client: Client?
    private var isConnected = false
    
    public init() {}
    
    public func setupClient(name: String, version: String) -> Client {
        let client = Client(name: name, version: version)
        self.client = client
        return client
    }
    
    public func connectToServer() async throws {
        guard let client = client else {
            throw NSError(domain: "MCPClientManager", code: 400, 
                          userInfo: [NSLocalizedDescriptionKey: "Client not initialized"])
        }
        
        // Use the standard StdioTransport from the MCP SDK
        let transport = StdioTransport()
        
        try await client.connect(transport: transport)
        isConnected = true
        
        // Initialize the connection with the server
        let result = try await client.initialize()
        
        // Now you can check server capabilities
        if let tools = result.capabilities.tools {
            print("Server supports tools capability")
        }
        
        if let prompts = result.capabilities.prompts {
            print("Server supports prompts capability")
        }
    }
    
    public func listAvailableTools() async throws -> [Tool] {
        guard let client = client, isConnected else {
            throw NSError(domain: "MCPClientManager", code: 401, 
                          userInfo: [NSLocalizedDescriptionKey: "Client not connected"])
        }
        
        let tools = try await client.listTools()
        return tools.tools
    }
    
    public func callTool(name: String, arguments: [String: Value]? = nil) async throws -> [Tool.Content] {
        guard let client = client, isConnected else {
            throw NSError(domain: "MCPClientManager", code: 401, 
                          userInfo: [NSLocalizedDescriptionKey: "Client not connected"])
        }
        
        let (content, isError) = try await client.callTool(name: name, arguments: arguments)
        
        if let isError = isError, isError {
            throw NSError(domain: "MCPClientManager", code: 500, 
                          userInfo: [NSLocalizedDescriptionKey: "Tool execution failed"])
        }
        
        return content
    }
    
    public func disconnect() async {
        guard let client = client else { return }
        await client.disconnect()
        isConnected = false
    }
}

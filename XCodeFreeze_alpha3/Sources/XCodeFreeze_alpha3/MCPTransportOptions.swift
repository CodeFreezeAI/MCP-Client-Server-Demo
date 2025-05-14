import Foundation
import MCP

public enum MCPTransportType {
    case stdio
    case http(URL, streaming: Bool)
}

public class MCPConnectionManager {
    private var client: Client?
    private var transport: any Transport?
    
    public init(clientName: String, clientVersion: String) {
        self.client = Client(name: clientName, version: clientVersion)
    }
    
    public func connect(using transportType: MCPTransportType) async throws {
        guard let client = client else {
            throw NSError(domain: "MCPConnectionManager", code: 400, 
                          userInfo: [NSLocalizedDescriptionKey: "Client not initialized"])
        }
        
        // Create the appropriate transport based on the type
        switch transportType {
        case .stdio:
            // Use the standard StdioTransport from the MCP SDK
            self.transport = StdioTransport()
            
        case .http(let url, let streaming):
            // Use HTTPClientTransport for network connections
            self.transport = HTTPClientTransport(endpoint: url, streaming: streaming)
        }
        
        guard let transport = transport else {
            throw NSError(domain: "MCPConnectionManager", code: 402,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create transport"])
        }
        
        // Connect the client using the selected transport
        try await client.connect(transport: transport)
        
        // Initialize the connection
        _ = try await client.initialize()
    }
    
    public func withBatchRequests(completion: (Client.Batch) async throws -> Void) async throws {
        guard let client = client else {
            throw NSError(domain: "MCPConnectionManager", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Client not initialized"])
        }
        
        try await client.withBatch(body: completion)
    }
    
    public func disconnect() async {
        await client?.disconnect()
    }
    
    public func listTools() async throws -> [Tool] {
        guard let client = client else {
            throw NSError(domain: "MCPConnectionManager", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Client not initialized"])
        }
        
        let response = try await client.listTools()
        return response.tools
    }
    
    // Example of using batch requests
    public func executeBatchExample() async throws {
        guard let client = client else {
            throw NSError(domain: "MCPConnectionManager", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Client not initialized"])
        }
        
        // Array to store tasks
        var toolTasks: [Task<CallTool.Result, Error>] = []
        
        // Create a batch of requests
        try await client.withBatch { batch in
            // Add request for tool1
            toolTasks.append(
                try await batch.addRequest(
                    CallTool.request(.init(name: "tool1", arguments: ["param": "value"]))
                )
            )
            
            // Add request for tool2
            toolTasks.append(
                try await batch.addRequest(
                    CallTool.request(.init(name: "tool2", arguments: ["param": "value"]))
                )
            )
        }
        
        // Process results after the batch is sent
        for (index, task) in toolTasks.enumerated() {
            do {
                let result = try await task.value
                print("Tool \(index+1) result: \(result.content)")
            } catch {
                print("Tool \(index+1) failed: \(error)")
            }
        }
    }
} 
import Foundation
import MCP
import Logging
import System
import SwiftUI

// MARK: - Custom Error Type
enum TransportError: Swift.Error {
    case serverNotConfigured(String)
    case unsupportedServerType(String)
    case transportUnavailable
    case encodingError(String)
    case otherError(Swift.Error)
    
    var localizedDescription: String {
        switch self {
        case .serverNotConfigured(let message):
            return "Server not configured: \(message)"
        case .unsupportedServerType(let type):
            return "Unsupported server type: \(type)"
        case .transportUnavailable:
            return "Transport is not available"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        case .otherError(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - MCP Transport Service
class TransportService {
    private var serverProcess: Process?
    private var transport: StdioTransport?
    
    // Start MCP server process and create transport
    func startServer(configPath: String, completion: @escaping (Result<(StdioTransport, Process), Swift.Error>) -> Void) {
        do {
            // Load configuration from custom path
            let config = try MCPConfig.loadConfig(customPath: configPath)
            
            // Check if there's a server configured for MCP_SERVER_NAME
            guard let serverConfig = config.mcpServers[MCP_SERVER_NAME] else {
                completion(.failure(TransportError.serverNotConfigured("No server configuration found for \(MCP_SERVER_NAME)")))
                return
            }
            
            // Get the server type (default to stdio if not specified)
            let serverType = serverConfig.type ?? "stdio"
            
            // Only use external server if it's a stdio type
            guard serverType == "stdio" else {
                completion(.failure(TransportError.unsupportedServerType(serverType)))
                return
            }
            
            // Get the command and use it as the executable path
            let executablePath = serverConfig.command
            
            // Get any additional arguments from the config
            var arguments: [String] = []
            if let configArgs = serverConfig.args {
                arguments = configArgs
            }
            
            print("Will use \(MCP_SERVER_NAME) server from config: \(executablePath)")
            if !arguments.isEmpty {
                print("With arguments: \(arguments.joined(separator: " "))")
            }
            
            // Launch MCP server process
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            
            // Set arguments from the config
            process.arguments = arguments
            
            // Set environment variables if provided
            if let env = serverConfig.env {
                var currentEnv = ProcessInfo.processInfo.environment
                for (key, value) in env {
                    currentEnv[key] = value
                }
                process.environment = currentEnv
            }
            
            // Create pipes for bidirectional communication
            let serverInput = Pipe()
            let serverOutput = Pipe()
            let serverError = Pipe()
            
            process.standardInput = serverInput
            process.standardOutput = serverOutput
            process.standardError = serverError
            
            // Set up async error reading
            Task {
                let errorHandle = serverError.fileHandleForReading
                let errorData = errorHandle.readDataToEndOfFile()
                if !errorData.isEmpty, let errorString = String(data: errorData, encoding: .utf8) {
                    print("\(MCP_SERVER_NAME) Server stderr: \(errorString)")
                }
            }
            
            // Start MCP server
            try process.run()
            print("\(MCP_SERVER_NAME) Server process started with PID: \(process.processIdentifier)")
            self.serverProcess = process
            
            // Create FileDescriptors for transport from the pipes
            let inputFD = FileDescriptor(rawValue: serverOutput.fileHandleForReading.fileDescriptor)
            let outputFD = FileDescriptor(rawValue: serverInput.fileHandleForWriting.fileDescriptor)
            
            // Use StdioTransport with explicit FileDescriptors
            let transport = StdioTransport(input: inputFD, output: outputFD, logger: nil)
            self.transport = transport
            
            // Return the transport and process
            completion(.success((transport, process)))
            
        } catch {
            // Forward any errors
            completion(.failure(TransportError.otherError(error)))
        }
    }
    
    // Stop the server
    func stopServer() {
        // Terminate server process
        serverProcess?.terminate()
        serverProcess = nil
        transport = nil
    }
    
    // Test the transport with a ping message
    func testTransport() async throws -> Bool {
        guard let transport = transport else {
            throw TransportError.transportUnavailable
        }
        
        // Test with a simple ping message
        let pingMessage = "{\"jsonrpc\": \"2.0\", \"method\": \"ping\", \"id\": \"transport-test\"}"
        print("Sending transport test message: \(pingMessage)")
        
        guard let pingData = pingMessage.data(using: .utf8) else {
            throw TransportError.encodingError("Failed to encode ping message")
        }
        
        try await transport.send(pingData)
        print("Transport test message sent successfully")
        
        return true
    }
    
    // Send a raw message through the transport
    func sendRawMessage(_ message: String) async throws {
        guard let transport = transport else {
            throw TransportError.transportUnavailable
        }
        
        guard let data = message.data(using: .utf8) else {
            throw TransportError.encodingError("Failed to encode message")
        }
        
        print("Sending raw message: \(message)")
        try await transport.send(data)
        print("Raw message sent successfully")
    }
} 
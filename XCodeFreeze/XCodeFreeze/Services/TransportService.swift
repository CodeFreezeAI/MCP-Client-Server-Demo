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
            return "\(MCPConstants.Messages.Errors.serverNotConfigured): \(message)"
        case .unsupportedServerType(let type):
            return "Unsupported server type: \(type)"
        case .transportUnavailable:
            return MCPConstants.Messages.Errors.transportUnavailable
        case .encodingError(let message):
            return "Encoding error: \(message)"
        case .otherError(let error):
            return error.localizedDescription
        }
    }
}

var runner = 0

// MARK: - MCP Transport Service
class TransportService {
    private var serverProcess: Process?
    private var transport: StdioTransport?
    
    // Start MCP server process and create transport
    func startServer(configPath: String, completion: @escaping (Result<(StdioTransport, Process), Swift.Error>) -> Void) {
        do {
            runner += 1
            print("RUNNER", runner)
            // Load configuration from custom path
            let config = try MCPConfig.loadConfig(customPath: configPath)
            
            // Check if there's a server configured for the MCP server
            guard let serverConfig = config.mcpServers[MCPConstants.Server.name] else {
                completion(.failure(TransportError.serverNotConfigured("No server configuration found for \(MCPConstants.Server.name)")))
                return
            }
            
            // Get the server type (default to stdio if not specified)
            let serverType = serverConfig.type ?? "stdio"
            print(serverType)
            
            
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
            
            LoggingService.shared.info(String(format: MCPConstants.Messages.Transport.willUseServer, MCPConstants.Server.name, executablePath))
            if !arguments.isEmpty {
                LoggingService.shared.info(String(format: MCPConstants.Messages.Transport.withArguments, arguments.joined(separator: " ")))
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)

            // Set arguments from the config
            process.arguments = arguments
            print("ARGS", process.arguments)
            // Set environment variables if provided
            if let env = serverConfig.env {
                print("ENV", env)
                var currentEnv = ProcessInfo.processInfo.environment
                for (key, value) in env {
                    currentEnv[key] = value
                }
                
                // Ensure PATH includes Homebrew paths
                  if let currentPath = currentEnv["PATH"] {
                      currentEnv["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
                  } else {
                      currentEnv["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                  }
                
                process.environment = currentEnv
            }

            // Create pipes for bidirectional communication
            let serverInput = Pipe()
            let serverOutput = Pipe()
            //let serverError = Pipe()

            process.standardInput = serverInput
            process.standardOutput = serverOutput

            // Add termination handler to prevent crashes
            process.terminationHandler = { process in
                print("MCP server process terminated with status: \(process.terminationStatus)")
            }

            // Store process reference to prevent deallocation
            // Make sure to keep this reference in your class/struct
            // self.mcpProcess = process

            do {
                try process.run()
                
                // Verify process started successfully
                if !process.isRunning {
                    throw NSError(domain: "MCPServerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Process failed to start"])
                }
                
            } catch {
                print("Failed to start MCP server: \(error)")
                // Handle the error appropriately
            }
            
           //  Set up async error reading
//            Task {
//                let errorHandle = serverError.fileHandleForReading
//                let errorData = errorHandle.readDataToEndOfFile()
//                if !errorData.isEmpty, let errorString = String(data: errorData, encoding: .utf8) {
//                    LoggingService.shared.warning(String(format: MCPConstants.Messages.Transport.serverStderr, MCPConstants.Server.name, errorString))
//                }
//            }
            
            // Start MCP server
           // do {
             //   try process.run()
      
            
LoggingService.shared.info(String(format: MCPConstants.Messages.Transport.serverProcessStarted, MCPConstants.Server.name, process.processIdentifier))
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
        LoggingService.shared.debug(String(format: MCPConstants.Messages.Transport.sendingTestMessage, pingMessage))
        
        guard let pingData = pingMessage.data(using: .utf8) else {
            throw TransportError.encodingError("Failed to encode ping message")
        }
        
        try await transport.send(pingData)
        LoggingService.shared.info(MCPConstants.Messages.Transport.testMessageSent)
        
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
        
        LoggingService.shared.debug(String(format: MCPConstants.Messages.Transport.sendingRawMessage, message))
        try await transport.send(data)
        LoggingService.shared.debug(MCPConstants.Messages.Transport.rawMessageSent)
    }
} 

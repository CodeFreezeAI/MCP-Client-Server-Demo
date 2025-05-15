# XCodeFreeze MCP Client

This project demonstrates a proper integration of the MCP Swift SDK client.

## SDK Integration Updates

The following improvements were made to correctly use the MCP Client SDK:

1. Added proper System/SystemPackage imports for FileDescriptor support:
   ```swift
   #if canImport(System)
       import System
   #else
       @preconcurrency import SystemPackage
   #endif
   ```

2. Replaced stdin/stdout redirection approach with proper FileDescriptor-based StdioTransport:
   ```swift
   // Create FileDescriptors for transport from the pipes
   let inputFD = FileDescriptor(rawValue: serverOutput.fileHandleForReading.fileDescriptor)
   let outputFD = FileDescriptor(rawValue: serverInput.fileHandleForWriting.fileDescriptor)
   
   // Use StdioTransport with explicit FileDescriptors
   let transport = StdioTransport(input: inputFD, output: outputFD, logger: nil)
   ```

3. Implemented proper client connection and disconnection to clean up resources:
   ```swift
   func stopClientServer() {
       Task {
           // Disconnect client first
           if let client = client {
               await client.disconnect()
           }
           
           // Clean up transport
           self.transport = nil
           
           // Terminate server process
           serverProcess?.terminate()
           serverProcess = nil
           
           // Clean up client reference
           self.client = nil
           
           await MainActor.run {
               self.isConnected = false
               self.statusMessage = "Disconnected"
           }
       }
   }
   ```

4. Added direct transport communication for debugging:
   ```swift
   // Send a raw message directly through the transport
   func sendRawMessage(_ message: String) async throws {
       guard let transport = transport, isConnected else {
           throw NSError(domain: "XCodeFreeze", code: 400, 
                         userInfo: [NSLocalizedDescriptionKey: "Transport not connected"])
       }
       
       guard let data = message.data(using: .utf8) else {
           throw NSError(domain: "XCodeFreeze", code: 400, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to encode message"])
       }
       
       print("Sending raw message: \(message)")
       try await transport.send(data)
       print("Raw message sent successfully")
   }
   
   // Start a direct message receiver for debugging purposes
   func startDebugMessageReceiver() async {
       guard let transport = transport, isConnected else {
           print("Cannot start message receiver: transport not connected")
           return
       }
       
       // Get the message stream
       guard let messageStream = await transport.receive() else {
           print("Failed to get message stream from transport")
           return
       }
       
       // Start processing messages
       Task {
           do {
               print("Debug message receiver started")
               for try await messageData in messageStream {
                   if let messageText = String(data: messageData, encoding: .utf8) {
                       print("DEBUG RECEIVER: Raw message received: \(messageText)")
                       
                       // For demonstration purposes, add to the UI
                       await addMessage(content: "[DEBUG RECEIVER] Raw message: \(messageText)", 
                                       isFromServer: true)
                   } else {
                       print("DEBUG RECEIVER: Received binary data of length \(messageData.count)")
                   }
               }
           } catch {
               print("DEBUG RECEIVER: Error in message receiver: \(error.localizedDescription)")
           }
       }
   }
   ```

## Requirements

- macOS 12.0 or later
- Swift 5.5 or later
- MCP Swift SDK package 
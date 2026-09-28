# MCP Client-Server Demo — XCodeFreeze

**XCodeFreeze** is a macOS SwiftUI chat app that works as a **Model Context Protocol (MCP) client** and an **AI front-end** at the same time. It starts an MCP server (by default the [xcf](https://xcf.ai) Xcode MCP server) over stdio, finds the server's tools, and lets a local LLM call those tools during a chat. The LLM suggests a tool call, the client runs it, and the result goes back to the model.

Built on the official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) (`0.8.2`, up to next major).

## Features

- **MCP over stdio**: starts the server process and connects with `StdioTransport` on FileDescriptors. It can connect and disconnect cleanly and send raw messages for debugging.
- **Tool discovery and registry**: lists the server's tools and their JSON-schema parameters, and keeps them in a type-safe registry.
- **AI chat with tool calling**: talks to any OpenAI-compatible endpoint (`/v1/models`, `/v1/chat/completions`), such as Ollama on port `11434`. MCP tools are passed to the model as function tools. Tool calls are run and the results are fed back to the model, several rounds if needed.
- **Thinking**: shows the model's `<thinking>` blocks separately from the answer.
- **Model picker**: fills the model list from `/v1/models`. The LLM server address can be changed in the header.
- **Config picker**: choose an existing MCP JSON config or create a new one. The path is saved in UserDefaults.
- **Built-in commands**: `help`, `list`, `ping`, plus Debug and Diagnostics buttons.

## Configuration

Click **New** in the header to create a config file (`mcp.json`):

```json
{
  "mcpServers": {
    "XCF_MCP_SERVER": {
      "type": "stdio",
      "command": "/usr/local/bin/xcf",
      "args": [],
      "env": {}
    }
  }
}
```

Set `command` to the path of your MCP server executable. The app uses the first server in the file (fallback name `XCF_MCP_SERVER`).

The LLM server address defaults to `192.168.1.135:11434`. Change it in the app header to your own Ollama / OpenAI-compatible host.

## Project layout

```
XCodeFreeze/
├── XCodeFreeze.xcodeproj
└── XCodeFreeze/
    ├── Config/     MCPConstants, ServerConfig
    ├── Models/     MCPViewModel, ChatMessage, AIModels (OpenAI-style request/response types)
    ├── Services/   TransportService, ClientServerService, MCPCommunicationService,
    │               MCPToolDiscoveryService / ToolDiscoveryService, ToolRegistry,
    │               AIService, MCPAIIntegrationService, CommandService,
    │               ConfigFileService, LoggingService, JSONFormatter, MessageFormatService
    └── Views/      ContentView, MessageView, Components/ (JSONHeaderView, ChatView,
                    InputBarView, ToolsListView, AIModelSelectorView, ConfigSelectorView)
```

`XCodeFreeze/README.md` has notes on how the SDK is integrated (FileDescriptor transport, disconnect handling, raw-message debugging).

## Build and run

1. Open `XCodeFreeze/XCodeFreeze.xcodeproj` in Xcode and run the `XCodeFreeze` scheme.
2. **Select** or **New** an MCP config, then **Connect**.
3. Set your LLM server address, pick a model, and start chatting.

## History

- **May 2025**: started as a basic MCP client/server demo (transport, JSON handling, enums, type-safe tool registry) and was renamed XCodeFreeze.
- **Aug–Sep 2025**: added AI chat. The model suggests tools and the client runs them. Added the single-line JSON header UI and fixed duplicate logging and over-eager tool auto-execution.

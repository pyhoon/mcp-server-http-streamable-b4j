# mcp_server_http_streamable

The issue with Claude desktop is it only support stdio transport.

For http streamable/sse, it requires a local proxy or bridge.

Currently a working proof of concept is using the command ```npx mcp-remote http://127.0.0.1:8080/mcp``` \
https://www.npmjs.com/package/mcp-remote

Unless you upgrade Claude to Pro, Max, Team, and Enterprise plans which enables integrations with remote MCP. \
https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers

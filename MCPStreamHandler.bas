B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10.3
@EndOfDesignText@
'Handler class
Sub Class_Globals
	Private in As InputStream
	Private out As OutputStream
	Private reader As TextReader
	Private Request As ServletRequest
	Private Response As ServletResponse
End Sub

Public Sub Initialize
	
End Sub

Sub Handle (req As ServletRequest, resp As ServletResponse)
    Request = req
    Response = resp
	
	If req.Method.ToLowerCase = "get" Then
		Log("GET method called")
	End If
	
	' 1. Essential Headers for Streaming
    Response.ContentType = "application/json-rpc"
    Response.SetHeader("Transfer-Encoding", "chunked")
    Response.SetHeader("Connection", "keep-alive") ' Instruct client/proxy to keep TCP connection open
    
    ' 2. Get the raw OutputStream
    out = Response.OutputStream
    
    ' 3. Start the Resumable Sub to handle the streaming logic
    StartStreaming
	'StartMessageLoop
End Sub

' --- The Resumable Streaming Logic ---
Sub StartStreaming
    ' A. Read the initial JSON-RPC message from the client (the POST body)
    'Dim jsonStr As String = Request.InputStream.As(TextReader).ReadAll
	in = Request.InputStream
    reader.Initialize(in)
	Dim jsonStr As String = reader.ReadAll
	Log(jsonStr)
	
    ' B. Process the message (This is the equivalent of HandleMessage)
    Dim responseString As String = HandleMessage(jsonStr)
	Log(responseString)
	
    ' C. Send the response as the first chunk
    If responseString.Length > 0 Then
        SendChunk(responseString)
    End If
    
    ' D. After the initial response, the connection could remain open to send 
    '    further notifications/events, but for a simple Request/Response, we close it.

    ' E. Final step: Send the zero-length chunk to close the stream gracefully
    out.WriteBytes(Array As Byte(0, 13, 10, 13, 10), 0, 5) ' 0\r\n\r\n
    out.Close
	out.Flush ' Release resources
	
	'StopMessageLoop
End Sub

' --- The Logic Core (Adapted from Stdio) ---
' Returns the final JSON-RPC response string
Sub HandleMessage (jsonStr As String) As String
    Try
        Dim map As Map = jsonStr.As(JSON).ToMap
        Dim method As String = map.Get("method")
        Dim id As Object = map.GetDefault("id", Null)
        
        Select method
            Case "initialize"
                Dim caps As Map = CreateMap("tools": CreateMap(), "resources": CreateMap())
                Return CreateResponse(id, CreateMap("protocolVersion": "2025-03-26", "capabilities": caps))
                    
            Case "tools/list"
                Dim tools As List = GetToolsList
                Return CreateResponse(id, CreateMap("tools": tools))
                
            Case "tools/call"
                Dim params As Map = map.Get("params")
                Dim toolName As String = params.Get("name")
                'Dim args As Map = map.GetDefault("arguments", CreateMap())
                
                If toolName = "get_inventory" Then
                    Dim res As List = ExecuteQuery("SELECT * FROM products")
                    Dim content As List = CreateContentList(res.As(JSON).ToCompactString)
                    Return CreateResponse(id, CreateMap("content": content))
                Else
                    Return CreateError(id, -32601, "Tool not found.")
                End If

            Case Else
                If id <> Null Then Return CreateError(id, -32601, "Method not found.")
        End Select
        
    Catch
        ' If JSON parsing or internal logic fails
        Return CreateError(Null, -32700, "Parse error or internal exception.")
    End Try
    
    Return "" ' Return empty string if it was a notification
End Sub

Sub ExecuteQuery (Query As String) As List
    Dim res As List
    res.Initialize
    Dim rs As ResultSet = Main.sql.ExecQuery(Query)
    Do While rs.NextRow
        Dim row As Map
        row.Initialize
        For i = 0 To rs.ColumnCount - 1
            row.Put(rs.GetColumnName(i), rs.GetString2(i))
        Next
        res.Add(row)
    Loop
    rs.Close
    Return res
End Sub

' --- JSON-RPC Helper Functions ---

Sub GetToolsList As List
    Dim tools As List
    tools.Initialize
    tools.Add(CreateMap("name": "get_inventory", "description": "Get all stock", "inputSchema": CreateMap("type": "object", "properties": CreateMap())))
    Return tools
End Sub

Sub CreateContentList(text As String) As List
    Dim content As List
    content.Initialize
    content.Add(CreateMap("type": "text", "text": text))
    Return content
End Sub

Sub CreateResponse (id As Object, result As Map) As String
    If id = Null Then Return ""
    Dim res As Map = CreateMap("jsonrpc": "2.0", "id": id, "result": result)
    Return res.As(JSON).ToString
End Sub

Sub CreateError (id As Object, code As Int, message As String) As String
    If id = Null Then Return ""
    Dim errMap As Map = CreateMap("code": code, "message": message)
    Dim res As Map = CreateMap("jsonrpc": "2.0", "id": id, "error": errMap)
    Return res.As(JSON).ToString
End Sub

' --- Chunked Transfer Encoding Helper ---

Sub SendChunk (data As String)
    ' 1. Calculate length of data in bytes
    Dim dataBytes() As Byte = data.GetBytes("UTF8")
    Dim len As Int = dataBytes.Length
    
    ' 2. Convert length to Hex string
    Dim hexLen As String = Bit.ToHexString(len)
    
    ' 3. Write chunk header: <size in hex>\r\n
    out.WriteBytes(hexLen.GetBytes("UTF8"), 0, hexLen.Length)
    out.WriteBytes(Array As Byte(13, 10), 0, 2) 
    
    ' 4. Write data: <data>\r\n
    out.WriteBytes(dataBytes, 0, len)
    out.WriteBytes(Array As Byte(13, 10), 0, 2) 
    
    out.Flush ' CRITICAL: Send the data immediately
End Sub
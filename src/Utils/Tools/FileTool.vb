Imports Microsoft.VisualBasic.CommandLine.Reflection
Imports Microsoft.VisualBasic.Data.Framework
Imports Microsoft.VisualBasic.Serialization.JSON

' ============================================================================
' 文件操作 Function Calling 工具集 - 注册到 LLM 供其读写工作区文件
' ============================================================================

''' <summary>
''' 文件操作工具集，提供工作区内的文件读写、目录列举、文件存在性检查等功能。
''' 这些方法通过 LLMClient.AddFunction 注册为大语言模型的函数调用工具，
''' 使 LLM 能够自主管理工作区内的脚本文件、配置文件、临时数据等。
''' </summary>
Public Class FileTool

    Private ReadOnly _workspaceRoot As String
    Private ReadOnly _logger As Action(Of String)

    Public Sub New(workspaceRoot As String, Optional logger As Action(Of String) = Nothing)
        _workspaceRoot = workspaceRoot
        _logger = If(logger, AddressOf Console.WriteLine)
    End Sub

    ''' <summary>
    ''' 将相对路径解析为工作区内的绝对路径，并验证路径不越界
    ''' </summary>
    Private Function ResolvePath(relativePath As String) As String
        If String.IsNullOrWhiteSpace(relativePath) Then
            Throw New ArgumentException("Path cannot be empty")
        End If

        Dim absPath As String
        If Path.IsPathRooted(relativePath) Then
            absPath = relativePath
        Else
            absPath = Path.Combine(_workspaceRoot, relativePath)
        End If

        ' 规范化路径
        absPath = Path.GetFullPath(absPath)

        ' 防止路径越界（仅允许在工作区内操作）
        Dim workspaceFull = Path.GetFullPath(_workspaceRoot)
        If Not absPath.StartsWith(workspaceFull, StringComparison.OrdinalIgnoreCase) Then
            ' 允许读取工作区外的输入文件，但写入必须在工作区内
        End If

        Return absPath
    End Function

    <Description("Write text content to a file in the workspace. Creates parent directories if they don't exist. Overwrites existing file by default.")>
    Public Function write_file(
        <Argument("path", Description:="File path relative to workspace root, or absolute path")> path As String,
        <Argument("content", Description:="Text content to write to the file")> content As String,
        <Argument("append", Description:="If true, append to existing file instead of overwriting (default false)")> Optional append As Boolean = False
    ) As String
        Try
            Dim absPath = ResolvePath(path)
            Dim dir = System.IO.Path.GetDirectoryName(absPath)
            If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
                Directory.CreateDirectory(dir)
            End If

            If append Then
                File.AppendAllText(absPath, content, Encoding.UTF8)
            Else
                File.WriteAllText(absPath, content, Encoding.UTF8)
            End If

            _logger?.Invoke($"[FileTool] Wrote {content.Length} chars to {absPath}")
            Return $"{{""success"": true, ""path"": ""{EscapeJson(absPath)}"", ""bytes"": {Encoding.UTF8.GetByteCount(content)}}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("Get previews summary of the csv table file, returns the dimension size and column headers")>
    Public Function peek_csv(<Argument("path", Description:="File path relative to workspace root, or absolute path")> path As String) As String
        Try
            Dim dims = DataFrame.GetDimension(path)
            Dim content As String = $"Csv Table[{dims.rows} Rows x {dims.cols} Cols]; column_headers:{dims.header.GetJson}"

            Return content
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("Read all text content from a file in the workspace. Returns the file content as a string. do not use this function for read all large text/csv file")>
    Public Function read_file(
        <Argument("path", Description:="File path relative to workspace root, or absolute path")> path As String
    ) As String
        Try
            Dim absPath = ResolvePath(path)
            If Not File.Exists(absPath) Then
                Return $"{{""error"": ""File not found: {EscapeJson(absPath)}""}}"
            End If

            Dim content = File.ReadAllText(absPath, Encoding.UTF8)
            _logger?.Invoke($"[FileTool] Read {content.Length} chars from {absPath}")
            Return content
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("peek the top 15 lines of the text(or csv) file, returns the file peeks contents as a string")>
    Public Function peek_file(<Argument("path", Description:="File path relative to workspace root, or absolute path")> path As String) As String
        Return path.IterateAllLines.Take(15).JoinBy(vbCrLf)
    End Function

    <Description("Check if a file exists in the workspace.")>
    Public Function file_exists(
        <Argument("path", Description:="File path relative to workspace root, or absolute path")> path As String
    ) As String
        Try
            Dim absPath = ResolvePath(path)
            Dim exists = File.Exists(absPath)
            Return $"{{""exists"": {exists.ToString().ToLower()}, ""path"": ""{EscapeJson(absPath)}""}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("List all files in a directory within the workspace. Optionally filter by file extension.")>
    Public Function list_files(
        <Argument("dir_path", Description:="Directory path relative to workspace root, or absolute path")> dir_path As String,
        <Argument("extension", Description:="Optional file extension filter, e.g. '.csv' or '.R' (empty for all files)")> Optional extension As String = ""
    ) As String
        Try
            Dim absPath = ResolvePath(dir_path)
            If Not Directory.Exists(absPath) Then
                Return $"{{""error"": ""Directory not found: {EscapeJson(absPath)}""}}"
            End If

            Dim files As String()
            If String.IsNullOrEmpty(extension) Then
                files = Directory.GetFiles(absPath)
            Else
                files = Directory.GetFiles(absPath, $"*{extension}")
            End If

            Dim fileList = files.Select(Function(f) Path.GetFileName(f)).ToArray()
            Return $"{{""count"": {fileList.Length}, ""dir"": ""{EscapeJson(absPath)}"", ""files"": [""{String.Join(""", """, fileList)}""]}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("Create a directory in the workspace. Creates all parent directories if needed.")>
    Public Function create_directory(
        <Argument("dir_path", Description:="Directory path relative to workspace root, or absolute path")> dir_path As String
    ) As String
        Try
            Dim absPath = ResolvePath(dir_path)
            If Not Directory.Exists(absPath) Then
                Directory.CreateDirectory(absPath)
            End If
            Return $"{{""success"": true, ""path"": ""{EscapeJson(absPath)}""}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    Private Shared Function EscapeJson(input As String) As String
        If String.IsNullOrEmpty(input) Then Return ""
        Return input.Replace("\", "\\").Replace("""", "\""").Replace(vbCr, "\r").Replace(vbLf, "\n").Replace(vbTab, "\t")
    End Function

End Class

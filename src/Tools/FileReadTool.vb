' ============================================================================
' LLM 函数调用工具集 - 文件读取、Shell执行、R脚本执行等
' ============================================================================
Imports System.ComponentModel
Imports System.Diagnostics
Imports System.IO
Imports System.Text
Imports Microsoft.VisualBasic.CommandLine.Reflection

Namespace Tools

    ''' <summary>
    ''' 文件读取工具，注册到 LLM 供其读取本地文件
    ''' </summary>
    Public Class FileReadTool

        <Description("Read the text content of a local file. Returns the file content as a string. Use this to inspect existing R scripts, CSV data files, knowledge base files, or any text file in the workspace.")>
        Public Function read_file(
            <Argument("path", Description:="Absolute path to the file to read")> path As String,
            <Argument("max_lines", Description:="Maximum number of lines to read (0 for all, default 5000)")> Optional max_lines As Integer = 5000
        ) As String
            Try
                If Not File.Exists(path) Then
                    Return $"{{""error"": ""File not found: {path}""}}"
                End If
                Dim lines = File.ReadLines(path)
                If max_lines > 0 Then
                    lines = lines.Take(max_lines)
                End If
                Dim sb As New StringBuilder()
                Dim n = 0
                For Each ln In lines
                    sb.AppendLine(ln)
                    n += 1
                Next
                Return $"{{""path"": ""{path}"", ""lines_read"": {n}, ""content"": {Newtonsoft.Json.JsonConvert.ToString(sb.ToString())}}}"
            Catch ex As Exception
                Return $"{{""error"": ""{ex.Message.Replace("""", "\""")}""}}"
            End Try
        End Function

        <Description("List files in a directory. Returns a JSON array of file names with their sizes.")>
        Public Function list_files(
            <Argument("path", Description:="Absolute path to the directory")> path As String,
            <Argument("pattern", Description:="Optional file name pattern, e.g. '*.R' (default '*')")> Optional pattern As String = "*"
        ) As String
            Try
                If Not Directory.Exists(path) Then
                    Return $"{{""error"": ""Directory not found: {path}""}}"
                End If
                Dim files = Directory.GetFiles(path, pattern)
                Dim sb As New StringBuilder()
                sb.Append("[")
                For i = 0 To files.Length - 1
                    If i > 0 Then sb.Append(",")
                    Dim fi As New FileInfo(files(i))
                    sb.Append($"{{""name"": ""{path.GetFileName(files(i))}"", ""size"": {fi.Length}}}")
                Next
                sb.Append("]")
                Return $"{{""path"": ""{path}"", ""count"": {files.Length}, ""files"": {sb.ToString()}}}"
            Catch ex As Exception
                Return $"{{""error"": ""{ex.Message.Replace("""", "\""")}""}}"
            End Try
        End Function

        <Description("Write text content to a file. Creates parent directories if needed. Use this to save generated R scripts, summary text, or any text output.")>
        Public Function write_file(
            <Argument("path", Description:="Absolute path to the file to write")> path As String,
            <Argument("content", Description:="Text content to write to the file")> content As String
        ) As String
            Try
                Dim parent = path.GetDirectoryName(path)
                If Not String.IsNullOrEmpty(parent) AndAlso Not Directory.Exists(parent) Then
                    Directory.CreateDirectory(parent)
                End If
                File.WriteAllText(path, content, Encoding.UTF8)
                Return $"{{""success"": true, ""path"": ""{path}"", ""bytes"": {New UTF8Encoding().GetByteCount(content)}}}"
            Catch ex As Exception
                Return $"{{""error"": ""{ex.Message.Replace("""", "\""")}""}}"
            End Try
        End Function

    End Class

End Namespace

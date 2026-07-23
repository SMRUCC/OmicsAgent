Imports System.IO.Compression
Imports Microsoft.VisualBasic.CommandLine.Reflection
Imports Microsoft.VisualBasic.Data.Framework
Imports Microsoft.VisualBasic.Serialization.JSON
Imports Microsoft.VisualBasic.Text

' ============================================================================
' 文件操作 Function Calling 工具集 - 注册到 LLM 供其读写工作区文件
' ============================================================================

''' <summary>
''' 文件操作工具集，提供工作区内的文件读写、目录列举、文件存在性检查等功能。
''' 这些方法通过 LLMClient.AddFunction 注册为大语言模型的函数调用工具，
''' 使 LLM 能够自主管理工作区内的脚本文件、配置文件、临时数据等。
''' </summary>
Public Class FileTool

    ReadOnly _workspaceRoot As String
    ReadOnly _logger As Action(Of String)

    Public Sub New(workspaceRoot As String, Optional logger As Action(Of String) = Nothing)
        _workspaceRoot = workspaceRoot
        _logger = If(logger, AddressOf Console.WriteLine)
    End Sub

    ''' <summary>
    ''' 将相对路径解析为工作区内的绝对路径，并验证路径不越界
    ''' </summary>
    ''' <param name="enforceWorkspace">
    ''' 为 True 时强制路径必须在工作区根目录内，用于写入类操作的安全检查
    ''' </param>
    Private Function ResolvePath(relativePath As String, Optional enforceWorkspace As Boolean = False) As String
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

        ' 防止路径越界
        ' 允许读取工作区外的输入文件，但写入必须在工作区内
        Dim workspaceFull = Path.GetFullPath(_workspaceRoot)
        If enforceWorkspace AndAlso Not absPath.StartsWith(workspaceFull, StringComparison.OrdinalIgnoreCase) Then
            Throw New UnauthorizedAccessException($"Path outside workspace is not allowed for write operations: {absPath}")
        End If

        Return absPath
    End Function

    <Description("将文本内容写入工作区内的文件。如果父目录不存在会自动创建。默认覆盖已存在的文件。")>
    Public Function write_file(
        <Argument("path", Description:="文件路径，相对于工作区根目录或绝对路径")> path As String,
        <Argument("content", Description:="要写入文件的文本内容")> content As String,
        <Argument("append", Description:="为 true 时追加到已存在的文件而非覆盖（默认 false）")> Optional append As Boolean = False
    ) As String
        Try
            Dim absPath = ResolvePath(path, enforceWorkspace:=True)
            Dim dir = System.IO.Path.GetDirectoryName(absPath)
            If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
                Directory.CreateDirectory(dir)
            End If

            If path.ExtensionSuffix("r") Then
                content = RScriptFixer.FixEntireRScript(rScript:=content)
            End If

            ' 20260723 the writed R script file must be save in utf8 (not utf8-bom)
            ' or run rscript will error happends:
            '
            ' "C:\Program Files\R\R-4.5.0\bin\Rscript.exe" --vanilla "F:/datapool/2026.7.6-energy/agent_test/analysis/scripts/check_data.R"
            ' Error: unexpected Input in ""
            ' Execution halted
            '
            ' due to the reason of utf8-bom header

            Static utf8 As Encoding = Encodings.UTF8WithoutBOM.CodePage

            If append Then
                File.AppendAllText(absPath, content, utf8)
            Else
                File.WriteAllText(absPath, content, utf8)
            End If

            _logger?.Invoke($"[FileTool] Wrote {content.Length} chars to {absPath}")
            Return $"{{""success"": true, ""path"": ""{EscapeJson(absPath)}"", ""bytes"": {Encoding.UTF8.GetByteCount(content)}}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("获取 csv 表格文件的预览摘要，返回维度大小和列标题")>
    Public Function peek_csv(<Argument("path", Description:="文件路径，相对于工作区根目录或绝对路径")> path As String) As String
        Try
            Dim dims = DataFrame.GetDimension(path)
            Dim content As String = $"Csv Table[{dims.rows} Rows x {dims.cols} Cols]; column_headers:{dims.header.GetJson}"

            Return content
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("读取工作区内文件的全部文本内容，以字符串形式返回。请勿使用此函数读取大型文本/csv 文件的全部内容")>
    Public Function read_file(
        <Argument("path", Description:="文件路径，相对于工作区根目录或绝对路径")> path As String
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

    <Description("查看文本（或 csv）文件的前 N 行，以字符串形式返回所查看的文件内容。默认读取 15 行。")>
    Public Function peek_file(
        <Argument("path", Description:="文件路径，相对于工作区根目录或绝对路径")> path As String,
        <Argument("line_count", Description:="从顶部开始读取的行数（默认 15）")> Optional line_count As Integer = 15
    ) As String
        Try
            Dim absPath = ResolvePath(path)
            If Not File.Exists(absPath) Then
                Return $"{{""error"": ""File not found: {EscapeJson(absPath)}""}}"
            End If

            Return absPath.IterateAllLines.Take(line_count).JoinBy(vbCrLf)
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("检查工作区内是否存在指定的文件。")>
    Public Function file_exists(
        <Argument("path", Description:="文件路径，相对于工作区根目录或绝对路径")> path As String
    ) As String
        Try
            Dim absPath = ResolvePath(path)
            Dim exists = File.Exists(absPath)
            Return $"{{""exists"": {exists.ToString().ToLower()}, ""path"": ""{EscapeJson(absPath)}""}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("列出工作区内某个目录下的所有文件，可选按文件扩展名进行过滤。")>
    Public Function list_files(
        <Argument("dir_path", Description:="目录路径，相对于工作区根目录或绝对路径")> dir_path As String,
        <Argument("extension", Description:="可选的文件扩展名过滤器，例如 '.csv' 或 '.R'（留空表示所有文件）")> Optional extension As String = ""
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

    <Description("在工作区内创建目录，如有需要会创建所有父目录。")>
    Public Function create_directory(
        <Argument("dir_path", Description:="目录路径，相对于工作区根目录或绝对路径")> dir_path As String
    ) As String
        Try
            Dim absPath = ResolvePath(dir_path, enforceWorkspace:=True)
            If Not Directory.Exists(absPath) Then
                Directory.CreateDirectory(absPath)
            End If
            Return $"{{""success"": true, ""path"": ""{EscapeJson(absPath)}""}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    ' ========================================================================
    ' 文件操作工具
    ' ========================================================================

    <Description("从工作区中删除一个文件。")>
    Public Function delete_file(
        <Argument("path", Description:="文件路径，相对于工作区根目录或绝对路径")> path As String
    ) As String
        Try
            Dim absPath = ResolvePath(path, enforceWorkspace:=True)
            If Not File.Exists(absPath) Then
                Return $"{{""error"": ""File not found: {EscapeJson(absPath)}""}}"
            End If
            File.Delete(absPath)
            _logger?.Invoke($"[FileTool] Deleted file: {absPath}")
            Return $"{{""success"": true, ""path"": ""{EscapeJson(absPath)}""}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("将文件复制到工作区内的新位置。如有需要会创建父目录。会覆盖已存在的文件。")>
    Public Function copy_file(
        <Argument("src_path", Description:="源文件路径，相对于工作区根目录或绝对路径")> src_path As String,
        <Argument("dest_path", Description:="目标文件路径，相对于工作区根目录或绝对路径")> dest_path As String
    ) As String
        Try
            Dim absSrc = ResolvePath(src_path)
            Dim absDest = ResolvePath(dest_path, enforceWorkspace:=True)
            If Not File.Exists(absSrc) Then
                Return $"{{""error"": ""Source file not found: {EscapeJson(absSrc)}""}}"
            End If
            Dim dir = Path.GetDirectoryName(absDest)
            If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
                Directory.CreateDirectory(dir)
            End If
            File.Copy(absSrc, absDest, overwrite:=True)
            _logger?.Invoke($"[FileTool] Copied {absSrc} -> {absDest}")
            Return $"{{""success"": true, ""src"": ""{EscapeJson(absSrc)}"", ""dest"": ""{EscapeJson(absDest)}""}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("将文件移动或重命名到工作区内的新位置。如有需要会创建父目录。会覆盖已存在的文件。")>
    Public Function move_file(
        <Argument("src_path", Description:="源文件路径，相对于工作区根目录或绝对路径")> src_path As String,
        <Argument("dest_path", Description:="目标文件路径，相对于工作区根目录或绝对路径")> dest_path As String
    ) As String
        Try
            Dim absSrc = ResolvePath(src_path, enforceWorkspace:=True)
            Dim absDest = ResolvePath(dest_path, enforceWorkspace:=True)
            If Not File.Exists(absSrc) Then
                Return $"{{""error"": ""Source file not found: {EscapeJson(absSrc)}""}}"
            End If
            Dim dir = Path.GetDirectoryName(absDest)
            If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
                Directory.CreateDirectory(dir)
            End If
            File.Move(absSrc, absDest, overwrite:=True)
            _logger?.Invoke($"[FileTool] Moved {absSrc} -> {absDest}")
            Return $"{{""success"": true, ""src"": ""{EscapeJson(absSrc)}"", ""dest"": ""{EscapeJson(absDest)}""}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("获取文件或目录的元数据信息：大小、最后修改时间、扩展名、类型。")>
    Public Function get_file_info(
        <Argument("path", Description:="文件或目录路径，相对于工作区根目录或绝对路径")> path As String
    ) As String
        Try
            Dim absPath = ResolvePath(path)
            If File.Exists(absPath) Then
                Dim fi As New FileInfo(absPath)
                Return $"{{""exists"": true, ""type"": ""file"", ""name"": ""{EscapeJson(fi.Name)}"", ""size_bytes"": {fi.Length}, ""extension"": ""{EscapeJson(fi.Extension)}"", ""last_modified"": ""{fi.LastWriteTime:yyyy-MM-ddTHH:mm:ss}"", ""path"": ""{EscapeJson(absPath)}""}}"
            ElseIf Directory.Exists(absPath) Then
                Dim di As New DirectoryInfo(absPath)
                Return $"{{""exists"": true, ""type"": ""directory"", ""name"": ""{EscapeJson(di.Name)}"", ""file_count"": {di.GetFiles().Length}, ""subdir_count"": {di.GetDirectories().Length}, ""last_modified"": ""{di.LastWriteTime:yyyy-MM-ddTHH:mm:ss}"", ""path"": ""{EscapeJson(absPath)}""}}"
            Else
                Return $"{{""exists"": false, ""path"": ""{EscapeJson(absPath)}""}}"
            End If
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    ' ========================================================================
    ' 高级文件读取工具
    ' ========================================================================

    <Description("从文本文件中读取指定范围的行。适用于使用 read_file 读取数据量过大的情况。行号从 1 开始计数。")>
    Public Function read_file_lines(
        <Argument("path", Description:="文件路径，相对于工作区根目录或绝对路径")> path As String,
        <Argument("start_line", Description:="开始读取的行号，从 1 开始计数（默认 1）")> Optional start_line As Integer = 1,
        <Argument("line_count", Description:="要读取的行数（默认 50）")> Optional line_count As Integer = 50
    ) As String
        Try
            Dim absPath = ResolvePath(path)
            If Not File.Exists(absPath) Then
                Return $"{{""error"": ""File not found: {EscapeJson(absPath)}""}}"
            End If

            If start_line < 1 Then start_line = 1
            If line_count < 1 Then line_count = 1

            Dim lines = absPath.IterateAllLines _
                .Skip(start_line - 1) _
                .Take(line_count) _
                .ToArray()
            Dim content = String.Join(vbCrLf, lines)
            _logger?.Invoke($"[FileTool] Read lines {start_line}-{start_line + lines.Length - 1} from {absPath}")
            Return content
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("读取文本文件的最后 N 行。适用于查看日志文件或脚本输出。默认读取最后 20 行。")>
    Public Function tail_file(
        <Argument("path", Description:="文件路径，相对于工作区根目录或绝对路径")> path As String,
        <Argument("line_count", Description:="从文件末尾开始读取的行数（默认 20）")> Optional line_count As Integer = 20
    ) As String
        Try
            Dim absPath = ResolvePath(path)
            If Not File.Exists(absPath) Then
                Return $"{{""error"": ""File not found: {EscapeJson(absPath)}""}}"
            End If

            If line_count < 1 Then line_count = 20

            ' 使用队列作为环形缓冲区，仅保留最后 N 行在内存中
            Dim buffer As New Queue(Of String)(line_count)
            For Each line In absPath.IterateAllLines
                If buffer.Count = line_count Then
                    buffer.Dequeue()
                End If
                buffer.Enqueue(line)
            Next

            Dim content = String.Join(vbCrLf, buffer)
            _logger?.Invoke($"[FileTool] Read last {buffer.Count} lines from {absPath}")
            Return content
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("在文件中搜索文本模式（不区分大小写）。返回匹配的行及其行号。默认最多返回 50 条结果。")>
    Public Function search_in_file(
        <Argument("path", Description:="文件路径，相对于工作区根目录或绝对路径")> path As String,
        <Argument("pattern", Description:="要搜索的文本模式（不区分大小写）")> pattern As String,
        <Argument("max_results", Description:="返回匹配行的最大数量（默认 50）")> Optional max_results As Integer = 50
    ) As String
        Try
            Dim absPath = ResolvePath(path)
            If Not File.Exists(absPath) Then
                Return $"{{""error"": ""File not found: {EscapeJson(absPath)}""}}"
            End If

            If max_results < 1 Then max_results = 50

            Dim matches As New List(Of String)()
            Dim lineNum As Integer = 0
            For Each line In absPath.IterateAllLines
                lineNum += 1
                If line.IndexOf(pattern, StringComparison.OrdinalIgnoreCase) >= 0 Then
                    matches.Add($"{{""line"": {lineNum}, ""content"": ""{EscapeJson(line)}""}}")
                    If matches.Count >= max_results Then Exit For
                End If
            Next

            Return $"{{""count"": {matches.Count}, ""pattern"": ""{EscapeJson(pattern)}"", ""matches"": [{String.Join(", ", matches)}]}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    ' ========================================================================
    ' 目录操作工具
    ' ========================================================================

    <Description("列出工作区内某个目录下的所有子目录。")>
    Public Function list_directories(
        <Argument("dir_path", Description:="目录路径，相对于工作区根目录或绝对路径")> dir_path As String
    ) As String
        Try
            Dim absPath = ResolvePath(dir_path)
            If Not Directory.Exists(absPath) Then
                Return $"{{""error"": ""Directory not found: {EscapeJson(absPath)}""}}"
            End If

            Dim dirs = Directory.GetDirectories(absPath)
            Dim dirList = dirs.Select(Function(d) Path.GetFileName(d)).ToArray()
            Return $"{{""count"": {dirList.Length}, ""dir"": ""{EscapeJson(absPath)}"", ""directories"": [""{String.Join(""", """, dirList)}""]}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("检查工作区内是否存在指定的目录。")>
    Public Function directory_exists(
        <Argument("dir_path", Description:="目录路径，相对于工作区根目录或绝对路径")> dir_path As String
    ) As String
        Try
            Dim absPath = ResolvePath(dir_path)
            Dim exists = Directory.Exists(absPath)
            Return $"{{""exists"": {exists.ToString().ToLower()}, ""path"": ""{EscapeJson(absPath)}""}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("从工作区中删除一个目录。如果 recursive 为 true，则递归删除所有子目录和文件。")>
    Public Function delete_directory(
        <Argument("dir_path", Description:="目录路径，相对于工作区根目录或绝对路径")> dir_path As String,
        <Argument("recursive", Description:="为 true 时递归删除所有子目录和文件（默认 false）")> Optional recursive As Boolean = False
    ) As String
        Try
            Dim absPath = ResolvePath(dir_path, enforceWorkspace:=True)
            If Not Directory.Exists(absPath) Then
                Return $"{{""error"": ""Directory not found: {EscapeJson(absPath)}""}}"
            End If
            Directory.Delete(absPath, recursive)
            _logger?.Invoke($"[FileTool] Deleted directory: {absPath} (recursive={recursive})")
            Return $"{{""success"": true, ""path"": ""{EscapeJson(absPath)}""}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("以树形结构递归列出文件和子目录。默认最大深度为 3，以防止输出内容过大。")>
    Public Function list_tree(
        <Argument("dir_path", Description:="目录路径，相对于工作区根目录或绝对路径")> dir_path As String,
        <Argument("max_depth", Description:="遍历的最大深度（默认 3）")> Optional max_depth As Integer = 3
    ) As String
        Try
            Dim absPath = ResolvePath(dir_path)
            If Not Directory.Exists(absPath) Then
                Return $"{{""error"": ""Directory not found: {EscapeJson(absPath)}""}}"
            End If

            If max_depth < 1 Then max_depth = 1

            Dim sb As New StringBuilder()
            sb.Append($"{{""root"": ""{EscapeJson(absPath)}"", ""tree"": ")
            BuildTreeJson(sb, absPath, 0, max_depth)
            sb.Append("}")
            Return sb.ToString()
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    Private Sub BuildTreeJson(sb As StringBuilder, dirPath As String, currentDepth As Integer, maxDepth As Integer)
        sb.Append("{")
        sb.Append($"""name"": ""{EscapeJson(Path.GetFileName(dirPath))}"", ")
        sb.Append($"""path"": ""{EscapeJson(dirPath)}"", ")

        ' List files
        Dim files = Directory.GetFiles(dirPath)
        sb.Append("""files"": [")
        For i As Integer = 0 To files.Length - 1
            If i > 0 Then sb.Append(", ")
            sb.Append($"""{EscapeJson(Path.GetFileName(files(i)))}""")
        Next
        sb.Append("]")

        ' List subdirectories recursively or indicate truncation
        Dim subdirs = Directory.GetDirectories(dirPath)
        If currentDepth < maxDepth Then
            If subdirs.Length > 0 Then
                sb.Append(", ""subdirs"": [")
                For i As Integer = 0 To subdirs.Length - 1
                    If i > 0 Then sb.Append(", ")
                    BuildTreeJson(sb, subdirs(i), currentDepth + 1, maxDepth)
                Next
                sb.Append("]")
            End If
        Else
            If subdirs.Length > 0 Then
                sb.Append($", ""subdirs_truncated"": true, ""subdir_count"": {subdirs.Length}")
            End If
        End If

        sb.Append("}")
    End Sub

    ' ========================================================================
    ' ZIP 压缩包工具
    ' ========================================================================

    <Description("将目录压缩为 ZIP 归档文件。如有需要会为输出 zip 文件创建父目录。会覆盖已存在的 zip 文件。")>
    Public Function create_zip(
        <Argument("source_dir", Description:="要压缩的源目录，相对于工作区根目录或绝对路径")> source_dir As String,
        <Argument("zip_path", Description:="输出的 ZIP 文件路径，相对于工作区根目录或绝对路径")> zip_path As String
    ) As String
        Try
            Dim absSrc = ResolvePath(source_dir)
            Dim absZip = ResolvePath(zip_path, enforceWorkspace:=True)
            If Not Directory.Exists(absSrc) Then
                Return $"{{""error"": ""Source directory not found: {EscapeJson(absSrc)}""}}"
            End If

            Dim dir = Path.GetDirectoryName(absZip)
            If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
                Directory.CreateDirectory(dir)
            End If

            ' 删除已存在的 zip 文件
            If File.Exists(absZip) Then
                File.Delete(absZip)
            End If

            ' 使用 ZipArchive 手动创建，遍历所有文件添加到压缩包中
            Using fs As New FileStream(absZip, FileMode.Create)
                Using archive As New ZipArchive(fs, ZipArchiveMode.Create)
                    For Each filePath In Directory.GetFiles(absSrc, "*", SearchOption.AllDirectories)
                        Dim relativePath = filePath.Substring(absSrc.Length) _
                            .TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) _
                            .Replace(Path.DirectorySeparatorChar, "/"c)
                        Dim entry = archive.CreateEntry(relativePath, CompressionLevel.Optimal)
                        Using entryStream = entry.Open()
                            Using fileStream As New FileStream(filePath, FileMode.Open, FileAccess.Read)
                                fileStream.CopyTo(entryStream)
                            End Using
                        End Using
                    Next
                End Using
            End Using

            Dim zipInfo As New FileInfo(absZip)
            _logger?.Invoke($"[FileTool] Created zip: {absZip} ({zipInfo.Length} bytes)")
            Return $"{{""success"": true, ""source"": ""{EscapeJson(absSrc)}"", ""zip_path"": ""{EscapeJson(absZip)}"", ""size_bytes"": {zipInfo.Length}}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("将 ZIP 归档文件解压到工作区内的目录。如果目标目录不存在则会创建。会覆盖已存在的文件。")>
    Public Function extract_zip(
        <Argument("zip_path", Description:="ZIP 文件路径，相对于工作区根目录或绝对路径")> zip_path As String,
        <Argument("dest_dir", Description:="解压到的目标目录，相对于工作区根目录或绝对路径")> dest_dir As String
    ) As String
        Try
            Dim absZip = ResolvePath(zip_path)
            Dim absDest = ResolvePath(dest_dir, enforceWorkspace:=True)
            If Not File.Exists(absZip) Then
                Return $"{{""error"": ""ZIP file not found: {EscapeJson(absZip)}""}}"
            End If

            If Not Directory.Exists(absDest) Then
                Directory.CreateDirectory(absDest)
            End If

            Dim entryCount As Integer = 0
            Using fs As New FileStream(absZip, FileMode.Open, FileAccess.Read)
                Using archive As New ZipArchive(fs, ZipArchiveMode.Read)
                    For Each entry As ZipArchiveEntry In archive.Entries
                        Dim destPath = Path.GetFullPath(Path.Combine(absDest, entry.FullName))

                        ' 安全检查：防止 zip slip 路径遍历攻击
                        If Not destPath.StartsWith(absDest, StringComparison.OrdinalIgnoreCase) Then
                            Return $"{{""error"": ""Zip entry path traversal detected: {EscapeJson(entry.FullName)}""}}"
                        End If

                        ' 跳过目录条目
                        If entry.FullName.EndsWith("/") OrElse entry.FullName.EndsWith("\") Then
                            Continue For
                        End If

                        Dim dir = Path.GetDirectoryName(destPath)
                        If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
                            Directory.CreateDirectory(dir)
                        End If

                        Using entryStream = entry.Open()
                            Using fileStream As New FileStream(destPath, FileMode.Create, FileAccess.Write)
                                entryStream.CopyTo(fileStream)
                            End Using
                        End Using
                        entryCount += 1
                    Next
                End Using
            End Using

            _logger?.Invoke($"[FileTool] Extracted {entryCount} entries from {absZip} -> {absDest}")
            Return $"{{""success"": true, ""zip_path"": ""{EscapeJson(absZip)}"", ""dest_dir"": ""{EscapeJson(absDest)}"", ""entries_extracted"": {entryCount}}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("在不解压的情况下列出 ZIP 归档内的所有文件条目。返回条目名称、大小和压缩后大小。")>
    Public Function list_zip_contents(
        <Argument("zip_path", Description:="ZIP 文件路径，相对于工作区根目录或绝对路径")> zip_path As String
    ) As String
        Try
            Dim absZip = ResolvePath(zip_path)
            If Not File.Exists(absZip) Then
                Return $"{{""error"": ""ZIP file not found: {EscapeJson(absZip)}""}}"
            End If

            Dim entries As New List(Of String)()
            Using fs As New FileStream(absZip, FileMode.Open, FileAccess.Read)
                Using archive As New ZipArchive(fs, ZipArchiveMode.Read)
                    For Each entry As ZipArchiveEntry In archive.Entries
                        entries.Add($"{{""name"": ""{EscapeJson(entry.FullName)}"", ""size"": {entry.Length}, ""compressed_size"": {entry.CompressedLength}}}")
                    Next
                End Using
            End Using

            Return $"{{""count"": {entries.Count}, ""zip_path"": ""{EscapeJson(absZip)}"", ""entries"": [{String.Join(", ", entries)}]}}"
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("在不解压整个归档的情况下读取 ZIP 归档内单个文件条目的文本内容。")>
    Public Function read_zip_entry(
        <Argument("zip_path", Description:="ZIP 文件路径，相对于工作区根目录或绝对路径")> zip_path As String,
        <Argument("entry_name", Description:="要读取的 ZIP 内条目的名称/路径")> entry_name As String
    ) As String
        Try
            Dim absZip = ResolvePath(zip_path)
            If Not File.Exists(absZip) Then
                Return $"{{""error"": ""ZIP file not found: {EscapeJson(absZip)}""}}"
            End If

            Using fs As New FileStream(absZip, FileMode.Open, FileAccess.Read), archive As New ZipArchive(fs, ZipArchiveMode.Read)
                Dim entry = archive.GetEntry(entry_name)
                If entry Is Nothing Then
                    Return $"{{""error"": ""Entry not found in ZIP: {EscapeJson(entry_name)}""}}"
                End If

                Using entryStream = entry.Open()
                    Using reader As New StreamReader(entryStream, Encoding.UTF8)
                        Dim content = reader.ReadToEnd()
                        _logger?.Invoke($"[FileTool] Read zip entry '{entry_name}' ({content.Length} chars) from {absZip}")
                        Return content
                    End Using
                End Using
            End Using
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    Private Shared Function EscapeJson(input As String) As String
        If String.IsNullOrEmpty(input) Then Return ""
        Return input.Replace("\", "\\").Replace("""", "\""").Replace(vbCr, "\r").Replace(vbLf, "\n").Replace(vbTab, "\t")
    End Function

End Class

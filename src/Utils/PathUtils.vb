' ============================================================================
' 路径与文件工具类
' ============================================================================
Imports System.IO
Imports System.Text

''' <summary>
''' 提供路径处理、文件读写、目录创建等通用工具方法。
''' </summary>
Public Module PathUtils

    ''' <summary>确保目录存在，不存在则创建</summary>
    Public Sub EnsureDirectory(path As String)
        If String.IsNullOrEmpty(path) Then Return
        If Not Directory.Exists(path) Then Directory.CreateDirectory(path)
    End Sub

    ''' <summary>获取相对于基准目录的相对路径</summary>
    Public Function GetRelativePath(relativeTo As String, path As String) As String
        Return Path.GetRelativePath(relativeTo, path).Replace("\"c, "/"c)
    End Function

    ''' <summary>将路径中的反斜杠转换为正斜杠（用于 R 脚本）</summary>
    Public Function NormalizePath(path As String) As String
        If String.IsNullOrEmpty(path) Then Return ""
        Return path.Replace("\"c, "/"c)
    End Function

    ''' <summary>将路径转换为 R 脚本中可用的字符串字面量（双反斜杠）</summary>
    Public Function ToRPath(path As String) As String
        If String.IsNullOrEmpty(path) Then Return ""
        Return path.Replace("\"c, "/"c)
    End Function

    ''' <summary>将路径转换为 Python 脚本中可用的字符串字面量</summary>
    Public Function ToPythonPath(path As String) As String
        If String.IsNullOrEmpty(path) Then Return ""
        Return path.Replace("\"c, "/"c).Replace("""", "\""")
    End Function

    ''' <summary>读取文本文件全部内容</summary>
    Public Function ReadAllText(filePath As String) As String
        If Not File.Exists(filePath) Then Return ""
        Return File.ReadAllText(filePath, Encoding.UTF8)
    End Function

    ''' <summary>写入文本文件</summary>
    Public Sub WriteAllText(filePath As String, content As String)
        EnsureDirectory(Path.GetDirectoryName(filePath))
        File.WriteAllText(filePath, content, Encoding.UTF8)
    End Sub

    ''' <summary>追加文本到文件</summary>
    Public Sub AppendText(filePath As String, content As String)
        EnsureDirectory(Path.GetDirectoryName(filePath))
        File.AppendAllText(filePath, content, Encoding.UTF8)
    End Sub

    ''' <summary>复制文件，覆盖目标</summary>
    Public Sub CopyFile(src As String, dst As String)
        EnsureDirectory(Path.GetDirectoryName(dst))
        File.Copy(src, dst, True)
    End Sub

    ''' <summary>列出目录下所有指定扩展名的文件</summary>
    Public Function ListFiles(dir As String, ext As String) As List(Of String)
        Dim result As New List(Of String)()
        If Not Directory.Exists(dir) Then Return result
        For Each f In Directory.GetFiles(dir, $"*{ext}")
            result.Add(f)
        Next
        Return result
    End Function

    ''' <summary>生成时间戳字符串，用于文件名</summary>
    Public Function Timestamp() As String
        Return DateTime.Now.ToString("yyyyMMdd_HHmmss")
    End Function

End Module

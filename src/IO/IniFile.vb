' ============================================================================
' INI 文件读写工具
' ============================================================================
Imports System.IO
Imports System.Text

Namespace IO

    ''' <summary>
    ''' 简单的 INI 配置文件读写器，支持 [section] / key=value 形式
    ''' </summary>
    Public Class IniFile

        Private ReadOnly _path As String
        Private ReadOnly _data As New Dictionary(Of String, Dictionary(Of String, String))(StringComparer.OrdinalIgnoreCase)

        Public Sub New(path As String)
            _path = path
            If File.Exists(path) Then Load()
        End Sub

        Default Public Property Item(section As String, key As String) As String
            Get
                Return Get(section, key)
            End Get
            Set(value As String)
                [Set](section, key, value)
            End Set
        End Property

        Public Function [Get](section As String, key As String, Optional defaultValue As String = "") As String
            section = section.Trim()
            key = key.Trim()
            If _data.ContainsKey(section) AndAlso _data(section).ContainsKey(key) Then
                Return _data(section)(key)
            End If
            Return defaultValue
        End Function

        Public Sub [Set](section As String, key As String, value As String)
            section = section.Trim()
            key = key.Trim()
            If Not _data.ContainsKey(section) Then
                _data(section) = New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
            End If
            _data(section)(key) = If(value, "")
        End Sub

        Public Function HasSection(section As String) As Boolean
            Return _data.ContainsKey(section.Trim())
        End Function

        Public Function HasKey(section As String, key As String) As Boolean
            section = section.Trim()
            key = key.Trim()
            Return _data.ContainsKey(section) AndAlso _data(section).ContainsKey(key)
        End Function

        Public Sub Save()
            Dim dir = Path.GetDirectoryName(_path)
            If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
                Directory.CreateDirectory(dir)
            End If
            Dim sb As New StringBuilder()
            For Each section In _data
                sb.AppendLine($"[{section.Key}]")
                For Each kv In section.Value
                    sb.AppendLine($"{kv.Key}={kv.Value}")
                Next
                sb.AppendLine()
            Next
            File.WriteAllText(_path, sb.ToString(), Encoding.UTF8)
        End Sub

        Private Sub Load()
            Dim currentSection As String = ""
            For Each line In File.ReadAllLines(_path, Encoding.UTF8)
                Dim trimmed = line.Trim()
                If String.IsNullOrEmpty(trimmed) Then Continue For
                If trimmed.StartsWith(";") OrElse trimmed.StartsWith("#") Then Continue For
                If trimmed.StartsWith("[") AndAlso trimmed.EndsWith("]") Then
                    currentSection = trimmed.Substring(1, trimmed.Length - 2).Trim()
                    If Not _data.ContainsKey(currentSection) Then
                        _data(currentSection) = New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
                    End If
                Else
                    Dim eq = trimmed.IndexOf("="c)
                    If eq > 0 Then
                        Dim k = trimmed.Substring(0, eq).Trim()
                        Dim v = trimmed.Substring(eq + 1).Trim()
                        If Not _data.ContainsKey(currentSection) Then
                            _data(currentSection) = New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
                        End If
                        _data(currentSection)(k) = v
                    End If
                End If
            Next
        End Sub

        Public ReadOnly Property FilePath As String
            Get
                Return _path
            End Get
        End Property

    End Class

End Namespace

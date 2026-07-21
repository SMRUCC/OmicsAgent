' ============================================================================
' 日志工具
' ============================================================================
Imports System.IO

Namespace Utils

    ''' <summary>
    ''' 简单的控制台 + 文件日志器
    ''' </summary>
    Public Class Logger

        Private ReadOnly _logFile As String
        Private ReadOnly _lock As New Object()

        Public Sub New(logFile As String)
            _logFile = logFile
            Dim dir = Path.GetDirectoryName(logFile)
            If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
                Directory.CreateDirectory(dir)
            End If
        End Sub

        Public Sub Info(msg As String)
            Write("INFO", msg)
        End Sub

        Public Sub Warn(msg As String)
            Write("WARN", msg)
        End Sub

        Public Sub [Error](msg As String)
            Write("ERROR", msg)
        End Sub

        Public Sub Phase(name As String)
            Dim bar = New String("="c, 60)
            Console.WriteLine(bar)
            Console.WriteLine($"  PHASE: {name}")
            Console.WriteLine(bar)
            AppendFile(bar)
            AppendFile($"  PHASE: {name}")
            AppendFile(bar)
        End Sub

        Private Sub Write(level As String, msg As String)
            Dim line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] [{level}] {msg}"
            Console.WriteLine(line)
            AppendFile(line)
        End Sub

        Private Sub AppendFile(line As String)
            SyncLock _lock
                Try
                    File.AppendAllText(_logFile, line & Environment.NewLine)
                Catch
                End Try
            End SyncLock
        End Sub

    End Class

End Namespace

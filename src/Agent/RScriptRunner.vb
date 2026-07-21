' ============================================================================
' R 脚本执行器（内部使用，非 LLM 工具）
' ============================================================================
Imports System.Diagnostics
Imports System.IO
Imports System.Text

Namespace Agent

    ''' <summary>
    ''' 直接调用 Rscript 执行 R 脚本，返回执行结果
    ''' </summary>
    Public Class RScriptRunner

        Private ReadOnly _rscriptPath As String
        Private ReadOnly _workingDir As String
        Private ReadOnly _timeoutMs As Integer

        Public Sub New(rscriptPath As String, workingDir As String, Optional timeoutMs As Integer = 900000)
            _rscriptPath = rscriptPath
            _workingDir = workingDir
            _timeoutMs = timeoutMs
        End Sub

        ''' <summary>
        ''' 执行 R 脚本文件
        ''' </summary>
        Public Function Run(scriptPath As String, Optional args As String = "") As RunResult
            Dim r As New RunResult With {.ScriptPath = scriptPath}
            If Not File.Exists(scriptPath) Then
                r.Success = False
                r.ErrorMessage = $"R script not found: {scriptPath}"
                Return r
            End If
            If Not File.Exists(_rscriptPath) Then
                r.Success = False
                r.ErrorMessage = $"Rscript not found: {_rscriptPath}"
                Return r
            End If

            Try
                Dim psi As New ProcessStartInfo With {
                    .FileName = _rscriptPath,
                    .Arguments = $"""{scriptPath}"" {args}",
                    .UseShellExecute = False,
                    .RedirectStandardOutput = True,
                    .RedirectStandardError = True,
                    .CreateNoWindow = True,
                    .StandardOutputEncoding = Encoding.UTF8,
                    .StandardErrorEncoding = Encoding.UTF8,
                    .WorkingDirectory = _workingDir
                }
                Using p As New Process()
                    p.StartInfo = psi
                    p.Start()
                    Dim stdoutTask = p.StandardOutput.ReadToEndAsync()
                    Dim stderrTask = p.StandardError.ReadToEndAsync()
                    Dim exited = p.WaitForExit(_timeoutMs)
                    If Not exited Then
                        Try
                            p.Kill()
                        Catch
                        End Try
                        r.Success = False
                        r.ErrorMessage = $"Rscript timed out after {_timeoutMs} ms"
                        Return r
                    End If
                    r.ExitCode = p.ExitCode
                    r.Stdout = stdoutTask.Result
                    r.Stderr = stderrTask.Result
                    r.Success = (p.ExitCode = 0)
                    If Not r.Success Then
                        r.ErrorMessage = r.Stderr
                    End If
                End Using
            Catch ex As Exception
                r.Success = False
                r.ErrorMessage = ex.Message
            End Try
            Return r
        End Function

        ''' <summary>
        ''' 执行内联 R 代码（写入临时文件后执行）
        ''' </summary>
        Public Function RunInline(rCode As String, Optional scriptName As String = "inline.R") As RunResult
            Dim path = Path.Combine(_workingDir, "tmp", scriptName)
            If Not Directory.Exists(Path.GetDirectoryName(path)) Then
                Directory.CreateDirectory(Path.GetDirectoryName(path))
            End If
            File.WriteAllText(path, rCode, Encoding.UTF8)
            Return Run(path)
        End Function

        Public Class RunResult
            Public Property ScriptPath As String
            Public Property Success As Boolean
            Public Property ExitCode As Integer
            Public Property Stdout As String = ""
            Public Property Stderr As String = ""
            Public Property ErrorMessage As String = ""

            Public Overrides Function ToString() As String
                If Success Then
                    Return $"[OK] {ScriptPath}"
                Else
                    Return $"[FAIL exit={ExitCode}] {ScriptPath}: {ErrorMessage}"
                End If
            End Function
        End Class

    End Class

End Namespace

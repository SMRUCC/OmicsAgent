' ============================================================================
' Shell 命令执行工具
' ============================================================================
Imports System.ComponentModel
Imports System.Diagnostics
Imports System.Text

Namespace Tools

    ''' <summary>
    ''' Shell 命令执行工具，注册到 LLM 供其调用本地命令行工具
    ''' </summary>
    Public Class ShellTool

        Private ReadOnly _workingDir As String
        Private ReadOnly _timeoutMs As Integer

        Public Sub New(Optional workingDir As String = Nothing, Optional timeoutMs As Integer = 600000)
            _workingDir = If(workingDir, Environment.CurrentDirectory)
            _timeoutMs = timeoutMs
        End Sub

        <Description("Execute a shell command and return stdout/stderr. Use this to run command-line tools like Rscript, python, or any executable. The command runs in the workspace working directory.")>
        Public Function run_shell(
            <Argument("command", Description:="The executable name or path, e.g. 'Rscript' or 'python'")> command As String,
            <Argument("args", Description:="Command line arguments as a single string")> args As String,
            <Argument("working_dir", Description:="Optional working directory (defaults to workspace root)")> Optional working_dir As String = ""
        ) As String
            Try
                Dim psi As New ProcessStartInfo With {
                    .FileName = command,
                    .Arguments = args,
                    .UseShellExecute = False,
                    .RedirectStandardOutput = True,
                    .RedirectStandardError = True,
                    .CreateNoWindow = True,
                    .StandardOutputEncoding = Encoding.UTF8,
                    .StandardErrorEncoding = Encoding.UTF8
                }
                If String.IsNullOrEmpty(working_dir) Then
                    psi.WorkingDirectory = _workingDir
                Else
                    psi.WorkingDirectory = working_dir
                End If

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
                        Return $"{{""error"": ""Command timed out after {_timeoutMs} ms"", ""command"": ""{command} {args}""}}"
                    End If
                    Dim stdout = stdoutTask.Result
                    Dim stderr = stderrTask.Result
                    Return $"{{""exit_code"": {p.ExitCode}, ""stdout"": {Newtonsoft.Json.JsonConvert.ToString(stdout)}, ""stderr"": {Newtonsoft.Json.JsonConvert.ToString(stderr)}}}"
                End Using
            Catch ex As Exception
                Return $"{{""error"": ""{ex.Message.Replace("""", "\""")}""}}"
            End Try
        End Function

    End Class

End Namespace

' ============================================================================
' R 脚本执行工具
' ============================================================================
Imports System.ComponentModel
Imports System.Diagnostics
Imports System.IO
Imports System.Text

Namespace Tools

    ''' <summary>
    ''' R 脚本执行工具，注册到 LLM 供其执行 R 脚本
    ''' </summary>
    Public Class RScriptTool

        Private ReadOnly _rscriptPath As String
        Private ReadOnly _rscriptToolDir As String
        Private ReadOnly _scriptsDir As String
        Private ReadOnly _workingDir As String
        Private ReadOnly _timeoutMs As Integer

        Public Sub New(rscriptPath As String, rscriptToolDir As String, scriptsDir As String, workingDir As String, Optional timeoutMs As Integer = 900000)
            _rscriptPath = rscriptPath
            _rscriptToolDir = rscriptToolDir
            _scriptsDir = scriptsDir
            _workingDir = workingDir
            _timeoutMs = timeoutMs
        End Sub

        <Description("Execute an R script file using Rscript. Returns stdout, stderr, and exit code. The script runs in the workspace working directory with access to the rscript tool directory.")>
        Public Function run_rscript(
            <Argument("script_path", Description:="Absolute path to the .R script file to execute")> script_path As String,
            <Argument("args", Description:="Optional command line arguments to pass to the R script")> Optional args As String = ""
        ) As String
            Try
                If Not File.Exists(script_path) Then
                    Return $"{{""error"": ""R script not found: {script_path}""}}"
                End If
                If Not File.Exists(_rscriptPath) Then
                    Return $"{{""error"": ""Rscript executable not found: {_rscriptPath}""}}"
                End If

                Dim psi As New ProcessStartInfo With {
                    .FileName = _rscriptPath,
                    .Arguments = $"""{script_path}"" {args}",
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
                        Return $"{{""error"": ""Rscript timed out after {_timeoutMs} ms"", ""script"": ""{script_path}""}}"
                    End If
                    Dim stdout = stdoutTask.Result
                    Dim stderr = stderrTask.Result
                    Return $"{{""exit_code"": {p.ExitCode}, ""script"": ""{script_path}"", ""stdout"": {Newtonsoft.Json.JsonConvert.ToString(stdout)}, ""stderr"": {Newtonsoft.Json.JsonConvert.ToString(stderr)}}}"
                End Using
            Catch ex As Exception
                Return $"{{""error"": ""{ex.Message.Replace("""", "\""")}""}}"
            End Try
        End Function

        <Description("Write R script content to a file in the workspace scripts directory and return the absolute path. Use this to save generated R code before executing it with run_rscript.")>
        Public Function write_rscript(
            <Argument("filename", Description:="File name (without path), e.g. 'pca_analysis.R'")> filename As String,
            <Argument("content", Description:="The R script source code content")> content As String
        ) As String
            Try
                If Not filename.EndsWith(".R") AndAlso Not filename.EndsWith(".r") Then
                    filename &= ".R"
                End If
                Dim path = Path.Combine(_scriptsDir, filename)
                If Not Directory.Exists(_scriptsDir) Then Directory.CreateDirectory(_scriptsDir)
                File.WriteAllText(path, content, Encoding.UTF8)
                Return $"{{""success"": true, ""path"": ""{path.Replace("\", "/")}""}}"
            Catch ex As Exception
                Return $"{{""error"": ""{ex.Message.Replace("""", "\""")}""}}"
            End Try
        End Function

        <Description("List available R tool scripts in the rscript tool directory. These are pre-existing helper functions that can be loaded with source() in your R scripts. Always check this list first before writing new R code.")>
        Public Function list_rscript_tools() As String
            Try
                If Not Directory.Exists(_rscriptToolDir) Then
                    Return $"{{""error"": ""Rscript tool directory not found: {_rscriptToolDir}"", ""available"": false}}"
                End If
                Dim files = Directory.GetFiles(_rscriptToolDir, "*.R").
                    Select(Function(f) Path.GetFileName(f)).ToArray()
                Dim sb As New StringBuilder()
                sb.Append("[")
                For i = 0 To files.Length - 1
                    If i > 0 Then sb.Append(",")
                    sb.Append($"""{files(i)}""")
                Next
                sb.Append("]")
                Return $"{{""directory"": ""{_rscriptToolDir}"", ""count"": {files.Length}, ""scripts"": {sb.ToString()}}}"
            Catch ex As Exception
                Return $"{{""error"": ""{ex.Message.Replace("""", "\""")}""}}"
            End Try
        End Function

    End Class

End Namespace

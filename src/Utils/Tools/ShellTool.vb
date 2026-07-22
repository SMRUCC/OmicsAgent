Imports Microsoft.VisualBasic.CommandLine.Reflection
Imports OmicsAgent.AppRuntime

' ============================================================================
' 命令行执行 Function Calling 工具集 - 执行 Rscript / Rsharp / Python 脚本
' ============================================================================

''' <summary>
''' 命令行执行工具集，提供 Rscript、R#、Python 脚本的执行能力。
''' 这些方法通过 LLMClient.AddFunction 注册为大语言模型的函数调用工具，
''' 使 LLM 能够自主运行所编写的分析脚本并获取执行结果。
''' </summary>
Public Class ShellTool

    Private ReadOnly _config As AgentConfig
    Private ReadOnly _workspaceRoot As String
    Private ReadOnly _logger As Action(Of String)

    Public Sub New(config As AgentConfig, workspaceRoot As String, Optional logger As Action(Of String) = Nothing)
        _config = config
        _workspaceRoot = workspaceRoot
        _logger = If(logger, AddressOf Console.WriteLine)
    End Sub

    <Description("Execute an R script file using Rscript interpreter. Returns the stdout, stderr, and exit code. The script file path should be relative to workspace root or absolute.")>
    Public Function run_rscript(
        <Argument("script_path", Description:="Path to the .R script file to execute")> script_path As String,
        <Argument("args", Description:="Optional command-line arguments to pass to the R script")> Optional args As String = "",
        <Argument("timeout_seconds", Description:="Maximum execution time in seconds (default 600 = 10 minutes)")> Optional timeout_seconds As Integer = 600
    ) As String
        Try
            Dim absScriptPath = ResolvePath(script_path)
            If Not File.Exists(absScriptPath) Then
                Return $"{{""error"": ""R script file not found: {EscapeJson(absScriptPath)}""}}"
            End If

            Return RunProcess(_config.Tools.RscriptPath, $"--vanilla ""{absScriptPath}"" {args}".Trim(), timeout_seconds)
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("Execute a Python script file using the configured Python interpreter. Returns stdout, stderr, and exit code.")>
    Public Function run_python(
        <Argument("script_path", Description:="Path to the .py script file to execute")> script_path As String,
        <Argument("args", Description:="Optional command-line arguments to pass to the Python script")> Optional args As String = "",
        <Argument("timeout_seconds", Description:="Maximum execution time in seconds (default 600 = 10 minutes)")> Optional timeout_seconds As Integer = 600
    ) As String
        Try
            Dim absScriptPath = ResolvePath(script_path)
            If Not File.Exists(absScriptPath) Then
                Return $"{{""error"": ""Python script file not found: {EscapeJson(absScriptPath)}""}}"
            End If

            Return RunProcess(_config.Tools.PythonPath, $"""{absScriptPath}"" {args}".Trim(), timeout_seconds)
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("Execute an R# (Rsharp) script file using the configured Rsharp interpreter. Returns stdout, stderr, and exit code.")>
    Public Function run_rsharp(
        <Argument("script_path", Description:="Path to the .R Rsharp script file to execute")> script_path As String,
        <Argument("args", Description:="Optional command-line arguments to pass to the Rsharp script")> Optional args As String = "",
        <Argument("timeout_seconds", Description:="Maximum execution time in seconds (default 600 = 10 minutes)")> Optional timeout_seconds As Integer = 600
    ) As String
        Try
            Dim absScriptPath = ResolvePath(script_path)
            If Not File.Exists(absScriptPath) Then
                Return $"{{""error"": ""Rsharp script file not found: {EscapeJson(absScriptPath)}""}}"
            End If

            Return RunProcess(_config.Tools.RsharpPath, $"""{absScriptPath}"" {args}".Trim(), timeout_seconds)
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    <Description("Execute wkhtmltopdf to convert an HTML file to PDF. Used for generating the final analysis report.")>
    Public Function run_wkhtmltopdf(
        <Argument("html_path", Description:="Path to the input HTML file")> html_path As String,
        <Argument("pdf_path", Description:="Path to the output PDF file")> pdf_path As String,
        <Argument("extra_args", Description:="Optional extra command-line arguments for wkhtmltopdf")> Optional extra_args As String = "",
        <Argument("timeout_seconds", Description:="Maximum execution time in seconds (default 300 = 5 minutes)")> Optional timeout_seconds As Integer = 300
    ) As String
        Try
            Dim absHtmlPath = ResolvePath(html_path)
            Dim absPdfPath = ResolvePath(pdf_path)
            If Not File.Exists(absHtmlPath) Then
                Return $"{{""error"": ""HTML file not found: {EscapeJson(absHtmlPath)}""}}"
            End If

            Dim dir = Path.GetDirectoryName(absPdfPath)
            If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
                Directory.CreateDirectory(dir)
            End If

            Dim args = $"--page-size A3 --orientation Portrait {extra_args} ""{absHtmlPath}"" ""{absPdfPath}"""
            Return RunProcess(_config.Tools.WkHtmlToPdfPath, args, timeout_seconds)
        Catch ex As Exception
            Return $"{{""error"": ""{EscapeJson(ex.Message)}""}}"
        End Try
    End Function

    ''' <summary>执行外部进程并捕获输出</summary>
    Private Function RunProcess(executable As String, args As String, timeoutSeconds As Integer) As String
        If String.IsNullOrEmpty(executable) OrElse Not File.Exists(executable) Then
            Return $"{{""error"": ""Executable not found: {EscapeJson(executable)}""}}"
        End If

        Dim psi As New ProcessStartInfo()
        psi.FileName = executable
        psi.Arguments = args
        psi.UseShellExecute = False
        psi.RedirectStandardOutput = True
        psi.RedirectStandardError = True
        psi.RedirectStandardInput = False
        psi.CreateNoWindow = True
        psi.StandardOutputEncoding = Encoding.UTF8
        psi.StandardErrorEncoding = Encoding.UTF8
        psi.WorkingDirectory = _workspaceRoot

        _logger?.Invoke($"[ShellTool] Running: {executable} {args}")

        Using p As New Process()
            p.StartInfo = psi
            Dim stdoutSb As New StringBuilder()
            Dim stderrSb As New StringBuilder()

            AddHandler p.OutputDataReceived, Sub(s, e) stdoutSb.AppendLine(e.Data)
            AddHandler p.ErrorDataReceived, Sub(s, e) stderrSb.AppendLine(e.Data)

            p.Start()
            p.BeginOutputReadLine()
            p.BeginErrorReadLine()

            Dim exited = p.WaitForExit(timeoutSeconds * 1000)
            If Not exited Then
                Try
                    p.Kill(True)
                Catch
                End Try
                Return $"{{""error"": ""Process timed out after {timeoutSeconds} seconds"", ""stdout"": ""{EscapeJson(stdoutSb.ToString())}"", ""stderr"": ""{EscapeJson(stderrSb.ToString())}""}}"
            End If

            ' 确保异步读取完成
            p.WaitForExit()

            Dim exitCode = p.ExitCode
            Dim stdout = stdoutSb.ToString()
            Dim stderr = stderrSb.ToString()

            _logger?.Invoke($"[ShellTool] Exit code: {exitCode}")

            ' 截断过长的输出
            If stdout.Length > 5000 Then stdout = stdout.Substring(0, 5000) & "...[truncated]"
            If stderr.Length > 5000 Then stderr = stderr.Substring(0, 5000) & "...[truncated]"

            Return $"{{""exit_code"": {exitCode}, ""stdout"": ""{EscapeJson(stdout)}"", ""stderr"": ""{EscapeJson(stderr)}""}}"
        End Using
    End Function

    Private Function ResolvePath(relativePath As String) As String
        If String.IsNullOrWhiteSpace(relativePath) Then Return ""
        If Path.IsPathRooted(relativePath) Then Return relativePath
        Return Path.GetFullPath(Path.Combine(_workspaceRoot, relativePath))
    End Function

    Private Shared Function EscapeJson(input As String) As String
        If String.IsNullOrEmpty(input) Then Return ""
        Return input.Replace("\", "\\").Replace("""", "\""").Replace(vbCr, "\r").Replace(vbLf, "\n").Replace(vbTab, "\t")
    End Function

End Class

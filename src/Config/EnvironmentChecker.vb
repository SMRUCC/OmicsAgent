' ============================================================================
' 运行环境检查器
' ============================================================================
Imports System.Diagnostics
Imports System.IO
Imports System.Net.Http

Namespace Config

    ''' <summary>
    ''' 检查运行环境：工具路径、LLM 服务可用性
    ''' </summary>
    Public Class EnvironmentChecker

        Private ReadOnly _config As AppConfig
        Private ReadOnly _iniPath As String

        Public Sub New(config As AppConfig, iniPath As String)
            _config = config
            _iniPath = iniPath
        End Sub

        ''' <summary>
        ''' 执行完整的环境检查，返回是否通过
        ''' </summary>
        Public Async Function CheckAsync() As Task(Of Boolean)
            Console.WriteLine("[Environment] Starting environment check...")

            ' 1. 检查工具路径
            If Not CheckToolPath(_config.RscriptPath, "Rscript") Then Return False
            If Not CheckToolPath(_config.WkHtmlToPdfPath, "wkhtmltopdf") Then Return False
            If Not CheckToolPath(_config.RsharpPath, "Rsharp") Then Return False
            If Not CheckToolPath(_config.PythonPath, "python") Then Return False

            ' 2. 检查 LLM 配置
            If String.IsNullOrEmpty(_config.LlmUrl) OrElse String.IsNullOrEmpty(_config.LlmModel) Then
                Console.Error.WriteLine("[Environment] LLM url or model is not configured in INI file.")
                Console.Error.WriteLine("             Please set [llm] section: url and model.")
                Return False
            End If

            ' 3. 检查 LLM 服务可用性
            If Not Await CheckLlmServiceAsync() Then Return False

            ' 4. 检查文献检索模式相关配置
            If _config.LiteratureSearchMode = "local_mysql" Then
                If String.IsNullOrEmpty(_config.MysqlHost) OrElse String.IsNullOrEmpty(_config.MysqlDatabase) Then
                    Console.Error.WriteLine("[Environment] Literature search mode is 'local_mysql' but MySQL config is incomplete.")
                    Return False
                End If
            End If

            Console.WriteLine("[Environment] Environment check passed.")
            Return True
        End Function

        Private Function CheckToolPath(path As String, name As String) As Boolean
            If String.IsNullOrWhiteSpace(path) Then
                Console.Error.WriteLine($"[Environment] {name} path is not configured.")
                PrintIniHelp()
                Return False
            End If

            ' 处理 PATH 中的命令（如 python）
            If path.Contains("/") = False AndAlso path.Contains("\") = False Then
                ' 尝试在 PATH 中查找
                Try
                    Dim pinfo As New ProcessStartInfo With {
                        .FileName = path,
                        .Arguments = "--version",
                        .UseShellExecute = False,
                        .RedirectStandardOutput = True,
                        .RedirectStandardError = True,
                        .CreateNoWindow = True
                    }
                    Using p = Process.Start(pinfo)
                        p.WaitForExit(5000)
                        If p.ExitCode = 0 Then
                            Console.WriteLine($"[Environment] {name} found in PATH: {path}")
                            Return True
                        End If
                    End Using
                Catch
                End Try
                Console.Error.WriteLine($"[Environment] {name} '{path}' not found in PATH.")
                PrintIniHelp()
                Return False
            End If

            If Not File.Exists(path) Then
                Console.Error.WriteLine($"[Environment] {name} path does not exist: {path}")
                PrintIniHelp()
                Return False
            End If
            Console.WriteLine($"[Environment] {name} OK: {path}")
            Return True
        End Function

        Private Async Function CheckLlmServiceAsync() As Task(Of Boolean)
            Console.WriteLine($"[Environment] Checking LLM service at {_config.LlmUrl} ...")
            Try
                Using client As New HttpClient()
                    client.Timeout = TimeSpan.FromSeconds(10)
                    Dim resp = Await client.GetAsync($"{_config.LlmUrl.TrimEnd("/"c)}/api/tags")
                    If resp.IsSuccessStatusCode Then
                        Console.WriteLine("[Environment] LLM service is available.")
                        Return True
                    Else
                        Console.Error.WriteLine($"[Environment] LLM service returned status {(CInt(resp.StatusCode))} {resp.StatusCode}.")
                        Return False
                    End If
                End Using
            Catch ex As Exception
                Console.Error.WriteLine($"[Environment] Cannot connect to LLM service: {ex.Message}")
                Console.Error.WriteLine("             Please ensure Ollama is running and the URL in INI file is correct.")
                Return False
            End Try
        End Function

        Private Sub PrintIniHelp()
            Console.Error.WriteLine()
            Console.Error.WriteLine("Please configure the INI file at:")
            Console.Error.WriteLine($"  {_iniPath}")
            Console.Error.WriteLine()
            Console.Error.WriteLine("Required sections:")
            Console.Error.WriteLine("  [tools]")
            Console.Error.WriteLine("    rscript=<path to Rscript.exe>")
            Console.Error.WriteLine("    wkhtmltopdf=<path to wkhtmltopdf.exe>")
            Console.Error.WriteLine("    rsharp=<path to Rsharp.exe>")
            Console.Error.WriteLine("    python=<path to python.exe or 'python'>")
            Console.Error.WriteLine("  [llm]")
            Console.Error.WriteLine("    url=http://localhost:11434")
            Console.Error.WriteLine("    model=llama3.1")
            Console.Error.WriteLine("    apikey=")
            Console.Error.WriteLine("  [mysql]   (required if literature mode=local_mysql)")
            Console.Error.WriteLine("    host=localhost")
            Console.Error.WriteLine("    port=3306")
            Console.Error.WriteLine("    user=root")
            Console.Error.WriteLine("    password=")
            Console.Error.WriteLine("    database=pubmed")
            Console.Error.WriteLine("  [literature]")
            Console.Error.WriteLine("    mode=none | local_mysql | ncbi_online")
            Console.Error.WriteLine()
        End Sub

    End Class

End Namespace

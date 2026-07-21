Imports System.Net.Http
Imports Microsoft.VisualBasic.MIME.application.json.Javascript

' ============================================================================
' 运行环境检查模块 - 检查外部工具路径与 LLM 服务可用性
' ============================================================================

''' <summary>
''' 运行环境检查器，负责在 agent 启动时检查所有外部依赖工具的可用性，
''' 包括 Rscript、wkhtmltopdf、R#、Python 解释器路径，以及 Ollama 大语言模型服务。
''' 若任一关键依赖不可用，将向用户输出明确的配置指引并终止程序。
''' </summary>
Public Class EnvironmentChecker

    Private ReadOnly _config As AgentConfig
    Private ReadOnly _logger As Action(Of String)

    Public Sub New(config As AgentConfig, Optional logger As Action(Of String) = Nothing)
        _config = config
        _logger = If(logger, AddressOf Console.WriteLine)
    End Sub

    ''' <summary>
    ''' 执行完整的环境检查流程：
    ''' 1. 检查所有外部工具路径是否存在
    ''' 2. 检查 LLM 服务配置是否完整
    ''' 3. 检查 MySQL 配置是否完整（若启用 mysql 检索策略）
    ''' 4. 检查 LLM 服务是否可用
    ''' </summary>
    ''' <returns>若全部检查通过返回 True，否则返回 False</returns>
    Public Async Function CheckAllAsync() As Task(Of Boolean)
        LogInfo("========== 运行环境检查 ==========")

        ' 1. 检查外部工具路径
        If Not CheckToolPaths() Then Return False

        ' 2. 检查 LLM 配置
        If Not CheckLLMConfig() Then Return False

        ' 3. 检查 MySQL 配置（若启用 mysql 检索策略）
        If _config.LiteratureSearchStrategy = "mysql" Then
            If Not CheckMySqlConfig() Then Return False
        End If

        ' 4. 检查 LLM 服务可用性
        If Not Await CheckLLMServiceAsync() Then Return False

        LogInfo("========== 环境检查通过 ==========")
        Return True
    End Function

    ''' <summary>检查所有外部工具路径是否存在</summary>
    Private Function CheckToolPaths() As Boolean
        Dim allOk As Boolean = True

        allOk = allOk AndAlso CheckSingleTool("Rscript", _config.RscriptPath)
        allOk = allOk AndAlso CheckSingleTool("wkhtmltopdf", _config.WkHtmlToPdfPath)
        allOk = allOk AndAlso CheckSingleTool("Rsharp", _config.RsharpPath)
        allOk = allOk AndAlso CheckSingleTool("Python", _config.PythonPath)

        If Not allOk Then
            LogInfo("")
            LogInfo("检测到部分外部工具路径未正确配置。")
            LogInfo($"请编辑 INI 配置文件：{AgentConfig.DefaultIniPath}")
            LogInfo("在 [tools] 段中填写正确的工具路径，然后重新运行本程序。")
        End If

        Return allOk
    End Function

    ''' <summary>检查单个工具路径是否存在</summary>
    Private Function CheckSingleTool(toolName As String, path As String) As Boolean
        If String.IsNullOrWhiteSpace(path) Then
            LogInfo($"  [X] {toolName}：路径未配置")
            Return False
        End If
        If Not File.Exists(path) Then
            LogInfo($"  [X] {toolName}：路径不存在 -> {path}")
            Return False
        End If
        LogInfo($"  [OK] {toolName}：{path}")
        Return True
    End Function

    ''' <summary>检查 LLM 服务配置是否完整</summary>
    Private Function CheckLLMConfig() As Boolean
        LogInfo("")
        LogInfo("----- 检查大语言模型配置 -----")
        Dim ok As Boolean = True

        If String.IsNullOrWhiteSpace(_config.LLMServiceUrl) Then
            LogInfo("  [X] LLM 服务 URL 未配置")
            ok = False
        Else
            LogInfo($"  [OK] LLM 服务 URL：{_config.LLMServiceUrl}")
        End If

        If String.IsNullOrWhiteSpace(_config.LLMModelName) Then
            LogInfo("  [X] LLM 模型名称未配置")
            ok = False
        Else
            LogInfo($"  [OK] LLM 模型名称：{_config.LLMModelName}")
        End If

        If Not ok Then
            LogInfo("")
            LogInfo("大语言模型配置不完整。")
            LogInfo($"请编辑 INI 配置文件：{AgentConfig.DefaultIniPath}")
            LogInfo("在 [llm] 段中填写 url 和 model 字段，然后重新运行本程序。")
        End If

        Return ok
    End Function

    ''' <summary>检查 MySQL 配置是否完整</summary>
    Private Function CheckMySqlConfig() As Boolean
        LogInfo("")
        LogInfo("----- 检查 MySQL 数据库配置 -----")
        Dim ok As Boolean = True

        If String.IsNullOrWhiteSpace(_config.MySqlHost) Then
            LogInfo("  [X] MySQL 主机未配置")
            ok = False
        End If
        If String.IsNullOrWhiteSpace(_config.MySqlDatabase) Then
            LogInfo("  [X] MySQL 数据库名未配置")
            ok = False
        End If
        If String.IsNullOrWhiteSpace(_config.MySqlUser) Then
            LogInfo("  [X] MySQL 用户名未配置")
            ok = False
        End If

        If ok Then
            LogInfo($"  [OK] MySQL：{_config.MySqlUser}@{_config.MySqlHost}:{_config.MySqlPort}/{_config.MySqlDatabase}")
        Else
            LogInfo("")
            LogInfo("MySQL 配置不完整，无法启用 PubMed 本地镜像检索。")
            LogInfo($"请编辑 INI 配置文件：{AgentConfig.DefaultIniPath}")
            LogInfo("在 [mysql] 段中填写完整的数据库连接参数。")
        End If

        Return ok
    End Function

    ''' <summary>检查 LLM 服务是否可用（调用 /api/tags 接口）</summary>
    Private Async Function CheckLLMServiceAsync() As Task(Of Boolean)
        LogInfo("")
        LogInfo("----- 检查大语言模型服务可用性 -----")

        Try
            Using client As New HttpClient()
                client.Timeout = TimeSpan.FromSeconds(15)
                Dim tagsUrl = _config.LLMServiceUrl.TrimEnd("/"c) & "/api/tags"
                LogInfo($"  正在连接：{tagsUrl}")
                Dim resp = Await client.GetAsync(tagsUrl)
                If resp.IsSuccessStatusCode Then
                    Dim json = Await resp.Content.ReadAsStringAsync()
                    Dim jobj As JsonObject = Await JsonObject.Parse(json)
                    Dim models As JsonArray = jobj("models")
                    If models IsNot Nothing AndAlso models.Count > 0 Then
                        LogInfo($"  [OK] LLM 服务可用，已加载 {models.Count} 个模型")
                        Dim modelExists As Boolean = False
                        For Each m As JsonObject In models
                            Dim name = m("name")?.ToString()
                            If name = _config.LLMModelName Then
                                modelExists = True
                                Exit For
                            End If
                        Next
                        If Not modelExists Then
                            LogInfo($"  [!] 指定的模型 {_config.LLMModelName} 未在服务中找到，请确认模型名称是否正确")
                            LogInfo("  当前可用模型列表：")
                            For Each m As JsonObject In models
                                LogInfo($"      - {m("name")?.ToString()}")
                            Next
                            Return False
                        End If
                        Return True
                    Else
                        LogInfo("  [X] LLM 服务可用但未加载任何模型")
                        Return False
                    End If
                Else
                    LogInfo($"  [X] LLM 服务返回错误状态码：{CInt(resp.StatusCode)} {resp.ReasonPhrase}")
                    Return False
                End If
            End Using
        Catch ex As Exception
            LogInfo($"  [X] 无法连接到 LLM 服务：{ex.Message}")
            LogInfo("  请确认 Ollama 服务已启动，并检查 INI 配置文件中的 url 字段。")
            Return False
        End Try
    End Function

    Private Sub LogInfo(msg As String)
        _logger?.Invoke(msg)
    End Sub

End Class

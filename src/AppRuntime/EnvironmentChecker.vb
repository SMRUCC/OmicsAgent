Imports Ollama

' ============================================================================
' 运行环境检查模块 - 检查外部工具路径与 LLM 服务可用性
' ============================================================================

Namespace AppRuntime

    ''' <summary>
    ''' 运行环境检查器，负责在 agent 启动时检查所有外部依赖工具的可用性，
    ''' 包括 Rscript、wkhtmltopdf、R#、Python 解释器路径，以及 Ollama 大语言模型服务。
    ''' 若任一关键依赖不可用，将向用户输出明确的配置指引并终止程序。
    ''' </summary>
    Public Class EnvironmentChecker

        ReadOnly _config As AgentConfig
        ReadOnly _logger As Action(Of String)

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
            If _config.Literature.LiteratureSearchStrategy = "mysql" Then
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

            allOk = allOk AndAlso CheckSingleTool("Rscript", _config.Tools.RscriptPath)
            allOk = allOk AndAlso CheckSingleTool("wkhtmltopdf", _config.Tools.WkHtmlToPdfPath)
            allOk = allOk AndAlso CheckSingleTool("Rsharp", _config.Tools.RsharpPath)
            allOk = allOk AndAlso CheckSingleTool("Python", _config.Tools.PythonPath)

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

            If String.IsNullOrWhiteSpace(_config.LLM.LLMServiceUrl) Then
                LogInfo("  [X] LLM 服务 URL 未配置")
                ok = False
            Else
                LogInfo($"  [OK] LLM 服务 URL：{_config.LLM.LLMServiceUrl}")
            End If

            If String.IsNullOrWhiteSpace(_config.LLM.LLMModelName) Then
                LogInfo("  [X] LLM 模型名称未配置")
                ok = False
            Else
                LogInfo($"  [OK] LLM 模型名称：{_config.LLM.LLMModelName}")
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

            If String.IsNullOrWhiteSpace(_config.MySql.MySqlHost) Then
                LogInfo("  [X] MySQL 主机未配置")
                ok = False
            End If
            If String.IsNullOrWhiteSpace(_config.MySql.MySqlDatabase) Then
                LogInfo("  [X] MySQL 数据库名未配置")
                ok = False
            End If
            If String.IsNullOrWhiteSpace(_config.MySql.MySqlUser) Then
                LogInfo("  [X] MySQL 用户名未配置")
                ok = False
            End If

            If ok Then
                LogInfo($"  [OK] MySQL：{_config.MySql.MySqlUser}@{_config.MySql.MySqlHost}:{_config.MySql.MySqlPort}/{_config.MySql.MySqlDatabase}")
            Else
                LogInfo("")
                LogInfo("MySQL 配置不完整，无法启用 PubMed 本地镜像检索。")
                LogInfo($"请编辑 INI 配置文件：{AgentConfig.DefaultIniPath}")
                LogInfo("在 [mysql] 段中填写完整的数据库连接参数。")
            End If

            Return ok
        End Function

        ''' <summary>检查 LLM 服务是否可用（调用 LLMClient.GetModelInformation，兼容 Ollama / OpenAI 后端）</summary>
        Private Async Function CheckLLMServiceAsync() As Task(Of Boolean)
            LogInfo("")
            LogInfo("----- 检查大语言模型服务可用性 -----")

            ' 取得 LLMClient：优先使用注入的工厂，未注入时基于配置直接构造
            Dim client As LLMClient = New LLMClient(LLMUrl.Create(_config.LLM.LLMServiceUrl, _config.LLM.LLMApiKey), _config.LLM.LLMModelName)

            Try
                LogInfo($"  正在连接：{_config.LLM.LLMServiceUrl}")
                LogInfo($"  目标模型：{_config.LLM.LLMModelName}")
                Dim info As ModelInfo = Await client.GetModelInformation(timeout:=15, verbose:=True)

                If info Is Nothing OrElse String.IsNullOrEmpty(info.Id) Then
                    LogInfo("  [X] LLM 服务返回了空的模型信息（ModelInfo 为空）")
                    Return False
                End If

                LogInfo($"  [OK] LLM 服务可用，模型：{info.Id}（后端：{info.Provider}）")
                Return True
            Catch ex As Exception
                LogInfo($"  [X] 无法连接到 LLM 服务或获取模型信息失败：{ex.Message}")
                LogInfo("  请确认 LLM 服务已启动，并检查 INI 配置文件中的 url / apikey / model 字段。")
                Return False
            Finally
                If client IsNot Nothing Then client.Dispose()
            End Try
        End Function

        Private Sub LogInfo(msg As String)
            _logger?.Invoke(msg)
        End Sub
    End Class
End Namespace
' ============================================================================
' 分析模块基类
' ============================================================================
Imports System.IO
Imports System.Text
Imports OmicsAgent.Config
Imports OmicsAgent.Models
Imports OmicsAgent.Utils
Imports OmicsAgent.IO
Imports Ollama
Imports OmicsAgent.Models.OmicsDataset

Namespace Agent

    ''' <summary>
    ''' 分析模块基类，每个具体分析模块继承此类
    ''' </summary>
    Public MustInherit Class AnalysisModuleBase

        Protected ReadOnly Property Config As AppConfig
        Protected ReadOnly Property Workspace As WorkspaceManager
        Protected ReadOnly Property Input As AnalysisInput
        Protected ReadOnly Property KbPath As String
        Protected ReadOnly Property Logger As Logger
        Protected ReadOnly Property LlmClientFactory As Func(Of LLMClient)

        Public ReadOnly Property ModuleName As String
        Public ReadOnly Property ModuleIndex As Integer

        Public Sub New(name As String, index As Integer, config As AppConfig, workspace As WorkspaceManager,
                       input As AnalysisInput, kbPath As String, logger As Logger,
                       llmClientFactory As Func(Of LLMClient))
            ModuleName = name
            ModuleIndex = index
            Me.Config = config
            Me.Workspace = workspace
            Me.Input = input
            Me.KbPath = kbPath
            Me.Logger = logger
            Me.LlmClientFactory = llmClientFactory
        End Sub

        Public ReadOnly Property ModuleDir As String
            Get
                Return Path.Combine(Workspace.WorkspaceDir, $"analysis_modules_{ModuleIndex:00}_{ModuleName}")
            End Get
        End Property

        Public ReadOnly Property TablesDir As String
            Get
                Return Path.Combine(ModuleDir, "tables")
            End Get
        End Property

        Public ReadOnly Property FiguresDir As String
            Get
                Return Path.Combine(ModuleDir, "figures")
            End Get
        End Property

        Public ReadOnly Property ScriptsDir As String
            Get
                Return Workspace.ScriptsDir
            End Get
        End Property

        Public ReadOnly Property TmpDir As String
            Get
                Return Workspace.TmpDir
            End Get
        End Property

        ''' <summary>
        ''' 执行分析模块（每个模块创建新的 LLM 客户端实例）
        ''' </summary>
        Public Async Function RunAsync() As Task(Of ModuleResult)
            Logger.Phase($"Module {ModuleIndex:00}: {ModuleName}")
            WorkspaceManager.EnsureDir(ModuleDir)
            WorkspaceManager.EnsureDir(TablesDir)
            WorkspaceManager.EnsureDir(FiguresDir)

            Dim result As New ModuleResult With {
                .ModuleName = ModuleName,
                .ModuleDir = ModuleDir
            }

            Try
                ' 创建新的 LLM 客户端实例（防止 token 积累）
                Dim llm = LlmClientFactory()
                RegisterTools(llm)
                Await ExecuteAsync(llm, result)
                result.Success = True
                Logger.Info($"Module {ModuleName} completed successfully.")
            Catch ex As Exception
                result.Success = False
                result.ErrorMessage = ex.Message
                Logger.Error($"Module {ModuleName} failed: {ex.Message}")
                Logger.Error(ex.StackTrace)
            End Try

            ' 保存结论
            If Not String.IsNullOrEmpty(result.ConclusionText) Then
                File.WriteAllText(Path.Combine(ModuleDir, "conclusion.txt"), result.ConclusionText, Encoding.UTF8)
            End If

            Return result
        End Function

        ''' <summary>
        ''' 注册该模块所需的 LLM 函数工具
        ''' </summary>
        Protected Overridable Sub RegisterTools(llm As LLMClient)
            ' 文件读写工具
            Dim fileTool As New Tools.FileReadTool()
            llm.AddFunction(fileTool, "read_file")
            llm.AddFunction(fileTool, "list_files")
            llm.AddFunction(fileTool, "write_file")

            ' Shell 工具
            Dim shellTool As New Tools.ShellTool(Workspace.WorkspaceDir)
            llm.AddFunction(shellTool, "run_shell")

            ' R 脚本工具
            Dim rTool As New Tools.RScriptTool(
                Config.RscriptPath,
                Config.RscriptToolDir,
                ScriptsDir,
                Workspace.WorkspaceDir)
            llm.AddFunction(rTool, "run_rscript")
            llm.AddFunction(rTool, "write_rscript")
            llm.AddFunction(rTool, "list_rscript_tools")
        End Sub

        ''' <summary>
        ''' 子类实现具体的分析逻辑
        ''' </summary>
        Protected MustOverride Function ExecuteAsync(llm As LLMClient, result As ModuleResult) As Task

        ''' <summary>
        ''' 读取知识库内容（截断到合理长度）
        ''' </summary>
        Protected Function ReadKnowledgeBase(Optional maxChars As Integer = 6000) As String
            If Not File.Exists(KbPath) Then Return "(no knowledge base available)"
            Dim content = File.ReadAllText(KbPath)
            If content.Length > maxChars Then
                Return content.Substring(0, maxChars) & "...[truncated]"
            End If
            Return content
        End Function

        ''' <summary>
        ''' 读取研究主题描述
        ''' </summary>
        Protected Function ReadResearchDescription() As String
            Return Input.Research.RawText
        End Function

        ''' <summary>
        ''' 构建模块通用上下文信息
        ''' </summary>
        Protected Function BuildContext() As String
            Dim sb As New StringBuilder()
            sb.AppendLine($"# Research Topic")
            sb.AppendLine(Input.Research.RawText)
            sb.AppendLine()
            sb.AppendLine($"# Datasets ({Input.Datasets.Count} omics)")
            For Each ds In Input.Datasets
                sb.AppendLine($"- {ds.Name}: {ds.OmicsType}, {ds.MoleculeCount} molecules x {ds.SampleCount} samples, groups: {String.Join(", ", ds.SampleGroups)}")
                sb.AppendLine($"  Expression: {ds.ExpressionCsvPath}")
                sb.AppendLine($"  SampleInfo: {ds.SampleInfoCsvPath}")
            Next
            sb.AppendLine()
            sb.AppendLine($"# Annotation File")
            sb.AppendLine(Input.AnnotationCsvPath)
            sb.AppendLine()
            sb.AppendLine($"# Workspace Paths")
            sb.AppendLine($"- Workspace root: {Workspace.WorkspaceDir}")
            sb.AppendLine($"- Tmp dir: {TmpDir}")
            sb.AppendLine($"- Scripts dir: {ScriptsDir}")
            sb.AppendLine($"- Module dir: {ModuleDir}")
            sb.AppendLine($"- Tables dir: {TablesDir}")
            sb.AppendLine($"- Figures dir: {FiguresDir}")
            sb.AppendLine($"- Rscript tool dir: {Config.RscriptToolDir}")
            sb.AppendLine()
            sb.AppendLine($"# Knowledge Base (kb.json)")
            sb.AppendLine(ReadKnowledgeBase())
            Return sb.ToString()
        End Function

        ''' <summary>
        ''' 调用 LLM 并清理响应（去除 markdown 包裹）
        ''' </summary>
        Protected Async Function ChatCleanAsync(llm As LLMClient, prompt As String) As Task(Of String)
            Dim resp = Await llm.Chat(prompt)
            Dim text = resp.output
            ' 去除可能的 markdown 包裹
            If text.StartsWith("```") Then
                Dim firstNl = text.IndexOf(vbLf)
                If firstNl > 0 Then
                    text = text.Substring(firstNl + 1)
                End If
                If text.EndsWith("```") Then
                    text = text.Substring(0, text.Length - 3)
                End If
                text = text.Trim()
            End If
            Return text
        End Function

    End Class

End Namespace

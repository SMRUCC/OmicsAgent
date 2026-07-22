Imports Microsoft.VisualBasic.Data.Trinity
Imports Ollama
Imports OmicsAgent.AppRuntime

' ============================================================================
' 分析模块基类 - 所有具体分析模块的抽象基类
' ============================================================================

''' <summary>
''' 所有分析模块的抽象基类。每个分析模块负责一个具体的分析步骤，
''' 例如预处理、PCA、LIMMA 差异分析、KEGG 富集等。
''' 
''' 每个模块都会创建一个新的 LLMClient 实例，以避免 token 累积。
''' 模块的工作流程：
''' 1. 调用 LLM 生成分析计划（ModulePlan）
''' 2. 调用 LLM 编写 R/Python 脚本
''' 3. 执行脚本
''' 4. 调用 LLM 生成阶段性总结文本
''' 5. 将结果保存到对应的 analysis_modules_N/ 目录
''' </summary>
Public MustInherit Class AnalysisModuleBase

    Protected ReadOnly _config As AgentConfig
    Protected ReadOnly _context As AnalysisContext
    Protected ReadOnly _logger As Action(Of String)

    ''' <summary>模块名称，用于创建输出目录</summary>
    Public MustOverride ReadOnly Property ModuleName As String

    ''' <summary>模块序号，用于创建 analysis_modules_N 目录</summary>
    Public MustOverride ReadOnly Property ModuleIndex As Integer

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        _config = config
        _context = context
        _logger = If(logger, AddressOf Console.WriteLine)
    End Sub

    ''' <summary>模块输出目录</summary>
    Public ReadOnly Property OutputDir As String
        Get
            Return Path.Combine(_context.AnalysisDir, $"analysis_modules_{ModuleIndex}")
        End Get
    End Property

    ''' <summary>模块表格输出目录</summary>
    Public ReadOnly Property TablesDir As String
        Get
            Return Path.Combine(OutputDir, "tables")
        End Get
    End Property

    ''' <summary>模块图像输出目录</summary>
    Public ReadOnly Property FiguresDir As String
        Get
            Return Path.Combine(OutputDir, "figures")
        End Get
    End Property

    ''' <summary>模块总结文件路径</summary>
    Public ReadOnly Property ConclusionFile As String
        Get
            Return Path.Combine(OutputDir, "conclusion.txt")
        End Get
    End Property

    ''' <summary>
    ''' 执行模块分析流程
    ''' </summary>
    Public Async Function RunAsync(cancellationToken As CancellationToken) As Task
        LogInfo($"========== 模块 {ModuleIndex}: {ModuleName} ==========")

        ' 创建输出目录
        Call OutputDir.MakeDir
        Call TablesDir.MakeDir
        Call FiguresDir.MakeDir

        Try
            ' 1. 生成分析计划
            Dim plan = Await GeneratePlanAsync(cancellationToken)
            LogInfo($"分析计划已生成：{plan.Goal}")

            ' 2. 编写并执行脚本
            Await GenerateAndRunScriptAsync(plan, cancellationToken)

            ' 3. 生成阶段性总结
            Dim conclusion = Await GenerateConclusionAsync(plan, cancellationToken)
            conclusion.SaveTo(ConclusionFile)
            LogInfo($"阶段性总结已保存：{ConclusionFile}")

            ' 4. 记录到上下文
            _context.ModuleResults.Add(New ModuleResult() With {
                .ModuleName = ModuleName,
                .ModuleIndex = ModuleIndex,
                .Conclusion = conclusion,
                .OutputDir = OutputDir
            })

        Catch ex As Exception
            LogInfo($"[错误] 模块 {ModuleName} 执行失败：{ex.Message}")
            LogInfo(ex.StackTrace)

            Call $"Module {ModuleName} failed with error: {ex.Message}{vbCrLf}{vbCrLf}Stack trace:{vbCrLf}{ex.StackTrace}".SaveTo(ConclusionFile)
            Call App.LogException(ex)
        End Try
    End Function

    ''' <summary>调用 LLM 生成分析计划</summary>
    Protected MustOverride Function GeneratePlanAsync(cancellationToken As CancellationToken) As Task(Of ModulePlan)

    ''' <summary>调用 LLM 编写并执行脚本</summary>
    Protected MustOverride Function GenerateAndRunScriptAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task

    ''' <summary>调用 LLM 生成阶段性总结</summary>
    Protected MustOverride Function GenerateConclusionAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)

    ''' <summary>构建模块上下文信息字符串，提供给 LLM</summary>
    Protected Function BuildContextInfo() As String
        Dim sb As New StringBuilder()
        sb.AppendLine($"# Workspace Information")
        sb.AppendLine($"- Workspace root: {_context.WorkspaceDir}")
        sb.AppendLine($"- Tmp directory: {_context.TmpDir}")
        sb.AppendLine($"- Scripts directory: {_context.ScriptsDir}")
        sb.AppendLine($"- R scripts tools directory: {AgentConfig.RScriptsDir}")
        sb.AppendLine($"- R-sharp scripts tools directory: {AgentConfig.RsharpScriptsDir}")
        sb.AppendLine($"- Python scripts tools directory: {AgentConfig.PythonScriptsDir}")
        sb.AppendLine($"- KEGG background data directory: {AgentConfig.KeggDataDir}")
        sb.AppendLine($"- molecule biological annotation table: {_context.AnnotationFile} ({StringFormats.Lanudry(_context.AnnotationFile.FileLength)})")
        sb.AppendLine()
        sb.AppendLine($"# Research Topic")
        sb.AppendLine(_context.ResearchTopic)
        sb.AppendLine()
        sb.AppendLine($"# Omics Datasets ({_context.Datasets.Count})")
        For i = 0 To _context.Datasets.Count - 1
            Dim d = _context.Datasets(i)
            sb.AppendLine($"## Dataset {i + 1}: {d.OmicsType}")
            sb.AppendLine($"- Expression file: {d.ExpressionFile.GetFullPath} ({StringFormats.Lanudry(d.ExpressionFile.FileLength)})")
            sb.AppendLine($"- Sample info file: {d.SampleInfoFile.GetFullPath} ({StringFormats.Lanudry(d.SampleInfoFile.FileLength)})")
            sb.AppendLine($"- Sample count: {d.SampleIDs.Count}")
            sb.AppendLine($"- Molecule count: {d.MoleculeIDs.Count}")
            sb.AppendLine($"- Sample IDs: { d.SampleIDs.Concatenate(", ")}")
        Next
        sb.AppendLine()
        sb.AppendLine($"# Knowledge Base")
        If File.Exists(_context.KnowledgeBaseFile) Then
            Dim kbContent = File.ReadAllText(_context.KnowledgeBaseFile, Encoding.UTF8)
            Dim stripLen As Integer = 30000

            If kbContent.Length > stripLen Then
                sb.AppendLine(kbContent.Substring(0, stripLen) & "...[truncated]")
            Else
                sb.AppendLine(kbContent)
            End If
        Else
            sb.AppendLine("(No knowledge base file available)")
        End If
        sb.AppendLine()
        sb.AppendLine($"# Previous Module Conclusions")
        For Each r In _context.ModuleResults
            sb.AppendLine($"## Module {r.ModuleIndex}: {r.ModuleName}")
            Dim c = r.Conclusion
            Dim stripLen As Integer = 5000

            If c.Length > stripLen Then c = c.Substring(0, stripLen) & "...[truncated]"
            sb.AppendLine(c)
            sb.AppendLine()
        Next
        Return sb.ToString()
    End Function

    ''' <summary>注册 Function Calling 工具到 LLM 客户端</summary>
    Protected Sub RegisterTools(llm As LLMClient)
        Dim fileTool As New FileTool(_context.WorkspaceDir, _logger)
        Dim shellTool As New ShellTool(_config, _context.WorkspaceDir, _logger)

        ' 注册文件操作工具
        llm.AddFunction(fileTool, "write_file")
        llm.AddFunction(fileTool, "read_file")
        llm.AddFunction(fileTool, "file_exists")
        llm.AddFunction(fileTool, "list_files")
        llm.AddFunction(fileTool, "create_directory")
        llm.AddFunction(fileTool, "peek_csv")
        llm.AddFunction(fileTool, "peek_file")

        ' 注册命令行执行工具
        llm.AddFunction(shellTool, "run_rscript")
        llm.AddFunction(shellTool, "run_python")
        llm.AddFunction(shellTool, "run_rsharp")
    End Sub

    Protected Sub LogInfo(msg As String)
        _logger?.Invoke(msg)
    End Sub

End Class

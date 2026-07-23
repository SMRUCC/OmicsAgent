Imports Microsoft.VisualBasic.Data.Trinity
Imports Microsoft.VisualBasic.MIME.application.json
Imports Microsoft.VisualBasic.MIME.application.json.LenientJson
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

    Public MustOverride ReadOnly Property CsvFileNamePrefix As String

    Public ReadOnly Property FolderBaseName As String
        Get
            Return $"{ModuleIndex}_{ModuleName.NormalizePathString(alphabetOnly:=True).Replace(" ", "_").ToLower}"
        End Get
    End Property

    Public ReadOnly Property Workspace As String
        Get
            Return _context.TmpDir & "/" & FolderBaseName
        End Get
    End Property

    Protected Overridable ReadOnly Property NeedsPlantSteps As Boolean
        Get
            Return True
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        _config = config
        _context = context
        _logger = If(logger, AddressOf Console.WriteLine)
    End Sub

    ''' <summary>模块输出目录</summary>
    Public ReadOnly Property OutputDir As String
        Get
            Return Path.Combine(_context.AnalysisDir, FolderBaseName)
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

            plan.GetJson(comment:=True).SaveTo($"{Workspace}/plan.json")

            ' 2. 编写并执行脚本
            Await GenerateAndRunScriptAsync(plan, cancellationToken)

            ' 3. 生成阶段性总结
            Dim conclusion = Await GenerateConclusionAsync(plan, cancellationToken)
            conclusion.SaveTo(ConclusionFile)
            LogInfo($"阶段性总结已保存：{ConclusionFile}")

            ' 4. 记录到上下文
            plan.conclusion = conclusion
            plan.GetJson(comment:=True).SaveTo($"{Workspace}/plan.json")

            If ModuleName = "Comparison Group Design" Then
                plan.comparisons.GetJson(comment:=False).SaveTo($"{_context.AnalysisDir}/design.json")
            End If

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
    Protected Async Function GeneratePlanAsync(cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Using llm As LLMClient = _config.CreateLLMClient(FolderBaseName & "-plan", _context.TmpDir)
            RegisterTools(llm, True)
            Return Await GeneratePlanAsync(llm, cancellationToken)
        End Using
    End Function

    Private Function CheckPlanSteps(actions As [Step]()) As Boolean
        If NeedsPlantSteps Then
            Return Not actions.IsNullOrEmpty
        Else
            Return True
        End If
    End Function

    Protected Async Function GeneratePlanAsync(llm As LLMClient, resp As LLMsResponse, cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Dim json = resp.ExtractJsonFromResponse
        Dim plan As New ModulePlan With {.module_name = ModuleName}
        Dim goal As String = Nothing
        Dim actions As [Step]() = Nothing
        Dim note As String = Nothing

        For retry_round As Integer = 0 To 9
            If Not json.StringEmpty(, True) Then
                plan = If(LenientJsonParser.ParseJSON(json).CreateObject(Of ModulePlan), New ModulePlan)
                plan.module_name = ModuleName

                If (Not plan.goal.StringEmpty(, True)) AndAlso CheckPlanSteps(plan.execution_steps) Then
                    Exit For
                End If

                If Not plan.goal.StringEmpty(, True) Then
                    goal = plan.goal
                End If
                If Not plan.execution_steps.IsNullOrEmpty Then
                    actions = plan.execution_steps
                End If
                If Not plan.notes.StringEmpty(, True) Then
                    note = plan.notes
                End If

                If (Not goal.StringEmpty(, True)) AndAlso CheckPlanSteps(actions) Then
                    plan = New ModulePlan With {
                        .module_name = ModuleName,
                        .execution_steps = actions,
                        .goal = goal,
                        .notes = note
                    }

                    Exit For
                End If
            End If

            resp = Await llm.Chat($"You are not generates a valid json or your generated execution plan JSON string is missing the following required fields:

""goal"": Explains the expected outcome that the current analysis module can achieve in the context of the user’s research background.
""notes"": Highlights any issues that require special attention in this execution plan.
""execution_steps"" (array): Break down the current execution plan into multiple steps and fill them into the ""execution_steps"" array following the specified JSON format.

Simply generate the specific execution plan here. Do not execute the actual analysis pipeline code. Return your plan as JSON in your response output, at least one execution step for your plan must be generated but no more than three decomposed execution steps:
{GetPlantJSONTemplate()}
", cancellationToken)
            json = resp.ExtractJsonFromResponse
        Next

        plan.llm_response = If(resp, New LLMsResponse).output

        If Not NeedsPlantSteps Then
            plan.execution_steps = {}
        End If

        Return plan
    End Function

    ''' <summary>调用 LLM 生成分析计划</summary>
    Protected Overridable Async Function GeneratePlanAsync(llm As LLMClient, cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Dim prompt = $"
You are a bioinformatics analysis expert. Your task is to design a analysis plan for omics expression matrix data.

{BuildContextInfo()}

# Your Task
{GeneratePlanPromptText()}

Simply generate the specific execution plan here. Do not execute the actual analysis pipeline code. Return your plan as JSON in your response output, at least one execution step for your plan must be generated but no more than three decomposed execution steps:
{GetPlantJSONTemplate()}
"
        Return Await GeneratePlanAsync(llm, Await llm.Chat(prompt, cancellationToken), cancellationToken)
    End Function

    Protected Overridable Function GetPlantJSONTemplate() As String
        Return "{
  ""module_name"": ""name of the analysis"",
  ""goal"": ""<brief description of the analysis goal>"",
  ""input_files"": [""<input file paths>""],
  ""output_files"": [""<expected output file paths>""],
  ""execution_steps"": [{""action"": ""<description of current step action>"", ""goal"": ""<goal of current step...>""}, ...],
  ""notes"": ""<any special considerations>""
}"
    End Function

    ''' <summary>调用 LLM 编写并执行脚本</summary>
    Protected Async Function GenerateAndRunScriptAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task
        Using llm As LLMClient = _config.CreateLLMClient(FolderBaseName & "-analysis", _context.TmpDir)
            Call RegisterTools(llm, True)

            For Each [step] As [Step] In plan.execution_steps
                Await GenerateAndRunScriptAsync(llm, plan, [step], cancellationToken)
            Next
        End Using
    End Function

    ''' <summary>调用 LLM 生成阶段性总结</summary>
    Protected Async Function GenerateConclusionAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Using llm As LLMClient = _config.CreateLLMClient(FolderBaseName & "-conclusion", _context.TmpDir)
            RegisterTools(llm, False)
            Return Await GenerateConclusionAsync(llm, plan, cancellationToken)
        End Using
    End Function

    Protected MustOverride Function GeneratePlanPromptText() As String

    ''' <summary>调用 LLM 编写并执行脚本</summary>
    Protected Overridable Async Function GenerateAndRunScriptAsync(llm As LLMClient, plan As ModulePlan, [step] As [Step], cancellationToken As CancellationToken) As Task
        Dim prompt = $"

{BuildContextInfo()}

You are a bioinformatics R script expert. Write and execute R script to process the omics expression matrix data according to the following plan.

# Analysis: {plan.module_name}

{plan.notes}

# Your Current Task
Write a complete R script that:

{[step].action}
{[step].goal}

All scripts and the generated CSV files are placed in this designated temporary workspace folder: {Workspace.GetDirectoryFullPath}
All pdf/png figure image files should save to workspace folder: {FiguresDir.GetDirectoryFullPath}
All generated CSV file filename starting with prefix '{CsvFileNamePrefix}' 

# Important Notes
- Use the source() function to load helper scripts from the rscript/ folder when applicable
- Use ggplot2 for any visualization
- Save all output files using absolute paths
- The script should be self-contained and runnable via Rscript
- Handle both single-omics and multi-omics cases
- Print progress messages to stdout
"
        Await llm.Chat(prompt, cancellationToken)
    End Function

    ''' <summary>调用 LLM 生成阶段性总结</summary>
    Private Async Function GenerateConclusionAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Dim prompt = $"
You are a biomedical research expert. Based on the {FolderBaseName} analysis results, write a stage conclusion in Chinese.

{BuildContextInfo()}

# Current Analysis Plan
{plan.ToJson()}

# Your Task
Read the analysis output files in the tmp/ directory (files starting with '{CsvFileNamePrefix}') or the result files in folder '{Workspace}' and the tables/ directory which located at {TablesDir}.
Write a conclusion in Chinese that describes:

{GetConclusionItems()}

Do not write any file, just generates the conclusion text in markdown format and return it back to me. The conclusion should be 800-1200 words in Chinese. Be specific and rigorous. Do NOT fabricate data.
"
        Dim resp = Await llm.Chat(prompt, cancellationToken)
        Return resp.output
    End Function

    Protected MustOverride Function GetConclusionItems() As String

    ''' <summary>构建模块上下文信息字符串，提供给 LLM</summary>
    Protected Function BuildContextInfo() As String
        Dim sb As New StringBuilder()

        sb.AppendLine($"# Workspace Information")
        sb.AppendLine($"- Workspace root: {_context.WorkspaceDir}")
        sb.AppendLine($"- Tmp directory: {_context.TmpDir}")
        sb.AppendLine($"- Scripts directory: {Workspace}/scripts/")
        sb.AppendLine($"- R scripts tools directory(readonly): {AgentConfig.RScriptsDir}")
        sb.AppendLine($"- R-sharp scripts tools directory(readonly): {AgentConfig.RsharpScriptsDir}")
        sb.AppendLine($"- Python scripts tools directory(readonly): {AgentConfig.PythonScriptsDir}")
        sb.AppendLine($"- KEGG background data directory(readonly): {AgentConfig.KeggDataDir}")
        sb.AppendLine($"- molecule biological annotation table(readonly): {_context.AnnotationFile} ({StringFormats.Lanudry(_context.AnnotationFile.FileLength)})")
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
        For Each r As ModuleResult In _context.ModuleResults
            Dim c As String = r.Conclusion
            Dim stripLen As Integer = 5000

            sb.AppendLine($"## Module {r.ModuleIndex}: {r.ModuleName}")

            If c.Length > stripLen Then
                c = c.Substring(0, stripLen) & "...[truncated]"
            End If

            sb.AppendLine(c)
            sb.AppendLine()
        Next
        Return sb.ToString()
    End Function

    ''' <summary>
    ''' 注册 Function Calling 工具到 LLM 客户端
    ''' </summary>
    ''' <param name="allowWriteFile">
    ''' 是否允许LLM agent写文件
    ''' </param>
    Protected Sub RegisterTools(llm As LLMClient, allowWriteFile As Boolean)
        Dim fileTool As New FileTool(_context.WorkspaceDir, _logger)
        Dim shellTool As New ShellTool(_config, _context.WorkspaceDir, _logger)

        ' 注册文件操作工具
        If allowWriteFile Then
            llm.AddFunction(fileTool, "write_file")
        End If

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

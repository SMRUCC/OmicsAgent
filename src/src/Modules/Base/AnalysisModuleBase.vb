Imports Microsoft.VisualBasic.Data.Framework
Imports Microsoft.VisualBasic.Data.Trinity
Imports Microsoft.VisualBasic.MIME.application.json
Imports Microsoft.VisualBasic.MIME.application.json.LenientJson
Imports Microsoft.VisualBasic.Serialization.JSON
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

    Dim plan As ModulePlan

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

    ''' <summary>模块图像输出目录</summary>
    Public ReadOnly Property FiguresDir As String
        Get
            Return Path.Combine(OutputDir, "figures")
        End Get
    End Property

    ''' <summary>模块总结文件路径</summary>
    Public ReadOnly Property ConclusionFile As String
        Get
            Return Path.Combine(OutputDir, "conclusion.md")
        End Get
    End Property

    ''' <summary>
    ''' 执行模块分析流程
    ''' </summary>
    Public Async Function RunAsync(cancellationToken As CancellationToken) As Task
        LogInfo($"========== 模块 {ModuleIndex}: {ModuleName} ==========")

        ' 创建输出目录
        Call OutputDir.MakeDir
        Call FiguresDir.MakeDir

        Try
            Dim _result As New ModuleResult() With {
                .ModuleName = ModuleName,
                .ModuleIndex = ModuleIndex,
                .Conclusion = Await RunAgent(cancellationToken),
                .OutputDir = OutputDir,
                .Workdir = Workspace
            }

            _result.Goal = If(plan, New ModulePlan).goal
            _context.ModuleResults.Add(_result)

            Call JsonContract.GetJson(_result).SaveTo($"{Workspace}/result.json")
        Catch ex As Exception
            LogInfo($"[错误] 模块 {ModuleName} 执行失败：{ex.Message}")
            LogInfo(ex.StackTrace)

            Call $"Module {ModuleName} failed with error: {ex.Message}{vbCrLf}{vbCrLf}Stack trace:{vbCrLf}{ex.StackTrace}".SaveTo(ConclusionFile)
            Call App.LogException(ex)
        End Try
    End Function

    Private Async Function RunAgent(cancellationToken As CancellationToken) As Task(Of String)
        Dim conclusion As String

        Using llm As LLMClient = _config.CreateLLMClient(FolderBaseName & "-agent", _context.TmpDir)
            Call RegisterTools(llm, True)

            ' 1. 生成分析计划
            plan = Await GeneratePlanAsync(llm, cancellationToken)

            Call JsonContract.GetJson(plan).SaveTo($"{Workspace}/plan.json")
            Call LogInfo($"分析计划已生成：{plan.goal}")

            ' 2. 编写并执行脚本
            Await GenerateAndRunScriptAsync(llm, plan, cancellationToken)

            ' 3. 生成阶段性总结
            conclusion = Await GenerateConclusionAsync(llm, plan, cancellationToken)

            Call conclusion.SaveTo(ConclusionFile)
            Call LogInfo($"阶段性总结已保存：{ConclusionFile}")

            ' 4. 记录到上下文
            plan.conclusion = conclusion
            JsonContract.GetJson(plan).SaveTo($"{Workspace}/plan.json")
        End Using

        If ModuleName = ComparisonDesignModule.Name Then
            _context.Comparisons = plan.comparisons

            Call JsonContract.GetJson(plan.comparisons).SaveTo($"{_context.AnalysisDir}/design.json")
            Call plan.comparisons.SaveTo($"{_context.AnalysisDir}/comparison_design.csv", silent:=True)
        End If

        Return conclusion
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

            resp = Await llm.Chat($"你生成的 JSON 无效，或生成的执行计划 JSON 缺少以下必填字段：

""goal"": 说明当前分析模块在用户研究背景下可达到的预期成果。
""notes"": 指出本执行计划中需要特别注意的事项。
""execution_steps""（数组）：将当前执行计划拆分为多个步骤，按指定 JSON 格式填入 ""execution_steps"" 数组。

请仅生成本次执行计划，不要执行实际分析代码。以如下所示的 JSON 格式返回分析计划，至少生成 1 个执行步骤，最多不超过 3 个步骤：
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
你是一位生物信息学分析专家。你的任务是为组学表达矩阵数据设计分析计划。

{BuildContextInfo()}

# 组学范围
{OmicsScopeHint()}

# 你的任务
{GeneratePlanPromptText()}

请仅生成本次执行计划，不要执行实际分析代码。以如下所示的 JSON 格式返回分析计划，至少生成 1 个执行步骤，最多不超过 3 个步骤：
{GetPlantJSONTemplate()}
"
        Return Await GeneratePlanAsync(llm, Await llm.Chat(prompt, cancellationToken), cancellationToken)
    End Function

    Protected Overridable Function GetPlantJSONTemplate() As String
        Return "{
  ""module_name"": ""分析模块名称"",
  ""goal"": ""<简要描述本分析模块的目标>"",
  ""input_files"": [""<输入文件路径>""],
  ""output_files"": [""<预期输出文件路径>""],
  ""execution_steps"": [{""action"": ""<当前步骤操作的描述>"", ""goal"": ""<当前步骤的目标...>""}, ...],
  ""notes"": ""<需要特别注意的事项>""
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

    ''' <summary>调用 LLM 编写并执行脚本</summary>
    Private Async Function GenerateAndRunScriptAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task
        For Each [step] As [Step] In plan.execution_steps
            Await GenerateAndRunScriptAsync(llm, plan, [step], cancellationToken)
        Next
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

你是一位生物信息学 R 脚本专家。请根据以下计划编写并执行 R 脚本，处理组学表达矩阵数据。

# 分析模块：{plan.module_name}

{plan.notes}

# 当前任务
编写一个完整的 R 脚本，完成以下内容：

{[step].action}
{[step].goal}

所有脚本和生成的 CSV 文件放置在指定临时工作区目录：{Workspace.GetDirectoryFullPath}
所有 PDF/PNG 图片文件保存到图片目录：{FiguresDir.GetDirectoryFullPath}
所有生成的 CSV 文件名以 '{CsvFileNamePrefix}' 为前缀

# 组学范围
{OmicsScopeHint()}

# 输出文件命名
{PerOmicsOutputConvention(CsvFileNamePrefix)}

# 重要注意事项
- 为了保证分析结果可复现以及绘图标准划，你应该优先使用 source() 函数从 {AgentConfig.RScriptsDir} 中的对应子目录中加载模块化的辅助脚本，并使用其中的R函数做分析以及绘图
- {AgentConfig.RScriptsDir}/readme.md 文件为可利用的标准R函数模块的索引，可以阅读这个文件了解你有哪些标准模块函数可以使用
- 所有可视化均使用 ggplot2，优先使用从 {AgentConfig.RScriptsDir} 子目录中加载的辅助函数进行绘图
- 所有输出文件使用绝对路径保存
- 脚本须自包含，可通过 Rscript 直接运行
- 将进度信息输出到 stdout
"
        Await llm.Chat(prompt, cancellationToken)
    End Function

    ''' <summary>调用 LLM 生成阶段性总结</summary>
    Protected Overridable Async Function GenerateConclusionAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Dim prompt = $"
你是一位生物医学研究专家。请基于 {FolderBaseName} 的分析结果，撰写中文阶段性总结。

{BuildContextInfo()}

# 当前分析计划
{plan.ToJson()}

# 你的任务
读取 tmp/ 目录中的分析输出文件（文件名以 '{CsvFileNamePrefix}' 开头）或 '{Workspace}' 目录中的结果文件。
撰写中文总结，涵盖以下内容：

{GetConclusionItems()}

不要写入任何文件，仅以 Markdown 格式生成总结文本并返回。总结应为 800-1200 字中文。内容须具体严谨，不得编造数据。
"
        Dim resp = Await llm.Chat(prompt, cancellationToken)
        Return resp.output
    End Function

    Protected MustOverride Function GetConclusionItems() As String

    ''' <summary>构建模块上下文信息字符串，提供给 LLM</summary>
    Protected Function BuildContextInfo() As String
        Dim sb As New StringBuilder()

        sb.AppendLine($"# 工作区信息")
        sb.AppendLine($"- 工作区根目录: {_context.WorkspaceDir}")
        sb.AppendLine($"- 临时目录: {_context.TmpDir}")
        sb.AppendLine($"- 脚本目录: {Workspace}/scripts/")
        sb.AppendLine($"- R 脚本工具目录(只读): {AgentConfig.RScriptsDir}")
        sb.AppendLine($"- R-sharp 脚本工具目录(只读): {AgentConfig.RsharpScriptsDir}")
        sb.AppendLine($"- Python 脚本工具目录(只读): {AgentConfig.PythonScriptsDir}")
        sb.AppendLine($"- KEGG 背景数据目录(只读): {AgentConfig.KeggDataDir}")

        If _context.IsMultiOmics Then
            sb.AppendLine($"- 分子生物学注释总表(只读): {_context.AnnotationFile} ({StringFormats.Lanudry(_context.AnnotationFile.FileLength)})")
            sb.AppendLine($"  该表由各组学的注释表合并而成，含 omics_id / omics_label 列标识注释来源；")
            sb.AppendLine($"  针对某一组学做注释映射时，请优先使用下方该组学各自的注释表。")

            If _context.IsSampleAligned Then
                sb.AppendLine($"- 样本对齐产物目录(只读): {_context.AlignedDir}")
                sb.AppendLine($"- 样本对齐宽表(只读): {_context.SubjectMapFile}")
            End If
        Else
            sb.AppendLine($"- 分子生物学注释表(只读): {_context.AnnotationFile} ({StringFormats.Lanudry(_context.AnnotationFile.FileLength)})")
        End If

        sb.AppendLine()
        sb.AppendLine($"# 研究主题")
        sb.AppendLine(_context.ResearchTopic)
        sb.AppendLine()

        If _context.IsMultiOmics Then
            sb.AppendLine($"# 组学数据集（多组学分析，共 {_context.Datasets.Count} 个组学）")
        Else
            sb.AppendLine($"# 组学数据集（单组学分析）")
        End If

        For i = 0 To _context.Datasets.Count - 1
            Dim d = _context.Datasets(i)

            sb.AppendLine($"## 数据集 {i + 1}: [{d.Id}] {d.DisplayName}")
            sb.AppendLine($"- 组学类型: {d.OmicsType}")

            If Not d.Unit.StringEmpty(, True) Then
                sb.AppendLine($"- 数据单位: {d.Unit}")
            End If

            sb.AppendLine($"- 表达矩阵文件: {d.ExpressionFile.GetFullPath} ({StringFormats.Lanudry(d.ExpressionFile.FileLength)})")

            If d.SampleInfoFile.FileExists Then
                sb.AppendLine($"- 样本信息表文件: {d.SampleInfoFile.GetFullPath} ({StringFormats.Lanudry(d.SampleInfoFile.FileLength)})")
            Else
                sb.AppendLine($"- 样本信息表文件: (未提供)")
            End If

            If _context.IsMultiOmics AndAlso d.AnnotationFile.FileExists Then
                sb.AppendLine($"- 该组学专属注释表: {d.AnnotationFile.GetFullPath} ({StringFormats.Lanudry(d.AnnotationFile.FileLength)})")
            End If

            sb.AppendLine($"- 样本数量: {d.SampleIDs.Count}")
            sb.AppendLine($"- 分子数量: {d.MoleculeIDs.Count}")
            sb.AppendLine($"- 样本ID: {TruncateIDs(d.SampleIDs)}")
            sb.AppendLine($"- 本模块之前，模块 1 预处理产物应位于: tmp/{d.PreprocessedFileName}")

            If d.IsAligned Then
                sb.AppendLine($"- 该矩阵已完成跨组学样本对齐，列名即为统一的 subject_id")
            End If
        Next

        sb.AppendLine()

        ' 多组学场景下补充跨组学样本对齐信息，明确告知 LLM 各组学可直接按列名合并
        If _context.IsMultiOmics AndAlso _context.IsSampleAligned Then
            Dim subjects As String() = If(_context.SubjectIDs, New String() {})

            sb.AppendLine($"# 跨组学样本对齐")
            sb.AppendLine($"- 全部 {_context.Datasets.Count} 个组学的表达矩阵已完成样本对齐。")
            sb.AppendLine($"- 各矩阵的样本列名已统一替换为生物学个体标识 subject_id，且仅保留全部组学共有的个体。")
            sb.AppendLine($"- 共有个体数量: {subjects.Length}")
            sb.AppendLine($"- 共有个体ID: {TruncateIDs(subjects)}")
            sb.AppendLine($"- 因此跨组学合并数据时可直接按列名（subject_id）对齐，无需再做任何样本 ID 转换。")
            sb.AppendLine($"- 原始样本 ID 与 subject_id 的对应关系见: {_context.SubjectMapFile}")
            sb.AppendLine()
        End If

        sb.AppendLine($"# 知识库")
        If File.Exists(_context.KnowledgeBaseFile) Then
            Dim kbContent = File.ReadAllText(_context.KnowledgeBaseFile, Encoding.UTF8)
            Dim stripLen As Integer = 30000

            If kbContent.Length > stripLen Then
                sb.AppendLine(kbContent.Substring(0, stripLen) & "...[truncated]")
            Else
                sb.AppendLine(kbContent)
            End If
        Else
            sb.AppendLine("(无知识库文件)")
        End If
        sb.AppendLine()
        sb.AppendLine($"# 上游模块总结")
        For Each r As ModuleResult In _context.ModuleResults
            Dim c As String = r.Conclusion
            Dim stripLen As Integer = 5000

            sb.AppendLine($"## 模块 {r.ModuleIndex}: {r.ModuleName}")

            If c.Length > stripLen Then
                c = c.Substring(0, stripLen) & "...[truncated]"
            End If

            sb.AppendLine(c)
            sb.AppendLine()
        Next
        Return sb.ToString()
    End Function

    ''' <summary>
    ''' 样本/分子 ID 列表在提示词中的最大展示条数。
    ''' 组学数据的样本数可能很多，全量列出会占用大量 token 且对 LLM 决策无益。
    ''' </summary>
    Private Const MaxDisplayIDs As Integer = 60

    ''' <summary>把 ID 列表格式化为提示词文本，超长时截断并标注剩余数量</summary>
    Private Shared Function TruncateIDs(ids As IEnumerable(Of String)) As String
        If ids Is Nothing Then
            Return "(无)"
        End If

        Dim all As String() = ids.ToArray

        If all.Length = 0 Then
            Return "(无)"
        End If

        If all.Length <= MaxDisplayIDs Then
            Return all.JoinBy(", ")
        End If

        Return all.Take(MaxDisplayIDs).JoinBy(", ") & $", ...（共 {all.Length} 个，此处仅列出前 {MaxDisplayIDs} 个）"
    End Function

    ''' <summary>
    ''' 生成描述本次分析组学范围的提示词片段。
    ''' </summary>
    ''' <remarks>
    ''' 单组学与多组学在分析策略上存在实质差异，但两者共用同一套提示词模板。
    ''' 若在模板里直接写「若为多组学则……」这类条件句，会迫使 LLM 在单组学场景下
    ''' 也去做无谓的分支判断，反而容易产生错误的分支代码。
    ''' 因此这里根据实际场景直接给出确定性的指令，模板中按需插值即可。
    ''' </remarks>
    Protected Function OmicsScopeHint() As String
        Dim datasets = _context.Datasets

        If Not _context.IsMultiOmics Then
            Dim single_ = datasets.FirstOrDefault

            If single_ Is Nothing Then
                Return "本次为单组学分析。"
            End If

            Return $"本次为**单组学**分析，只有一个组学数据集：[{single_.Id}] {single_.DisplayName}" &
                   $"（组学类型 {single_.OmicsType}{If(single_.Unit.StringEmpty(, True), "", $"，数据单位 {single_.Unit}")}）。" &
                   "请直接针对该组学开展分析，不需要考虑任何跨组学整合的处理。"
        End If

        Dim list As String = datasets _
            .Select(Function(d) $"[{d.Id}] {d.DisplayName}（{d.OmicsType}{If(d.Unit.StringEmpty(, True), "", $"，{d.Unit}")}）") _
            .JoinBy("、")

        Dim hint As String =
            $"本次为**多组学**分析，共 {datasets.Count} 个组学数据集：{list}。" &
            "请对每个组学分别独立完成本模块的分析，各组学的结果需要分开保存并带上组学标识，" &
            "不要把不同组学的数据混在同一个矩阵里直接分析。"

        If _context.IsSampleAligned Then
            hint &= $"各组学矩阵的样本列名已统一为 subject_id（共有个体 {If(_context.SubjectIDs Is Nothing, 0, _context.SubjectIDs.Length)} 个），" &
                    "需要跨组学取用同一批个体时可直接按列名对齐。"
        End If

        Return hint
    End Function

    ''' <summary>
    ''' 生成描述模块 1 预处理产物输入位置的提示词片段。
    ''' </summary>
    ''' <remarks>
    ''' 多组学场景下每个组学各有一份预处理产物，若只笼统地说「读取 tmp/ 下以
    ''' preprocessed_ 开头的文件」，LLM 容易只处理其中一个或错误地把多个组学拼成一张表。
    ''' 因此这里把每个组学对应的具体文件名显式列出。
    ''' </remarks>
    Protected Function PreprocessedInputHint() As String
        Dim datasets = _context.Datasets

        If Not _context.IsMultiOmics Then
            Dim single_ = datasets.FirstOrDefault

            If single_ Is Nothing Then
                Return "读取模块 1 预处理后的表达矩阵（tmp/ 目录，文件名以 'preprocessed_' 开头）"
            End If

            Return $"读取模块 1 预处理后的表达矩阵：tmp/{single_.PreprocessedFileName}"
        End If

        Dim list As String = datasets _
            .Select(Function(d) $"  - [{d.Id}] {d.DisplayName}：tmp/{d.PreprocessedFileName}") _
            .JoinBy(vbLf)

        Return $"读取模块 1 预处理后的各组学表达矩阵，共 {datasets.Count} 个，逐一对应如下：" & vbLf & list
    End Function

    ''' <summary>
    ''' 生成中间产物文件命名约定的提示词片段。
    ''' </summary>
    ''' <remarks>
    ''' 多组学场景下若沿用统一的文件名前缀，多个组学的产物会互相覆盖，
    ''' 因此必须要求 LLM 在文件名中带上组学标识加以区分。
    ''' </remarks>
    Protected Function PerOmicsOutputConvention(filePrefix As String) As String
        Dim datasets = _context.Datasets

        If Not _context.IsMultiOmics Then
            Dim single_ = datasets.FirstOrDefault
            Dim id As String = If(single_ Is Nothing, "omics", single_.Id)

            Return $"输出文件统一命名为 '{filePrefix}{id}.csv' 形式（前缀 '{filePrefix}' + 组学标识）。"
        End If

        Dim examples As String = datasets.Select(Function(d) $"'{filePrefix}{d.Id}.csv'").JoinBy("、")

        Return $"每个组学的输出文件必须带上各自的组学标识以避免互相覆盖，" &
               $"依次命名为：{examples}。组学标识必须与上方数据集清单中的方括号内 id 完全一致。"
    End Function

    ''' <summary>
    ''' 
    ''' </summary>
    ''' <param name="llm"></param>
    ''' <param name="allowWriteFile"></param>
    ''' <param name="wsDir"></param>
    Protected Sub RegisterFileTools(llm As LLMClient, allowWriteFile As Boolean, Optional wsDir As String = Nothing)
        Dim fileTool As New FileTool(If(wsDir, _context.WorkspaceDir), _logger)

        ' 注册写入类文件操作工具（受 allowWriteFile 控制）
        If allowWriteFile Then
            llm.AddFunction(fileTool, "write_file")
            ' llm.AddFunction(fileTool, "delete_file")
            llm.AddFunction(fileTool, "copy_file")
            ' llm.AddFunction(fileTool, "move_file")
            ' llm.AddFunction(fileTool, "delete_directory")
            llm.AddFunction(fileTool, "create_zip")
            llm.AddFunction(fileTool, "extract_zip")
        End If

        ' 注册只读类文件操作工具（始终可用）
        llm.AddFunction(fileTool, "read_file")
        llm.AddFunction(fileTool, "file_exists")
        llm.AddFunction(fileTool, "list_files")
        llm.AddFunction(fileTool, "create_directory")
        llm.AddFunction(fileTool, "peek_csv")
        llm.AddFunction(fileTool, "peek_file")
        llm.AddFunction(fileTool, "get_file_info")
        llm.AddFunction(fileTool, "read_file_lines")
        llm.AddFunction(fileTool, "tail_file")
        llm.AddFunction(fileTool, "search_in_file")
        llm.AddFunction(fileTool, "list_directories")
        llm.AddFunction(fileTool, "directory_exists")
        llm.AddFunction(fileTool, "list_tree")
        llm.AddFunction(fileTool, "list_zip_contents")
        llm.AddFunction(fileTool, "read_zip_entry")
    End Sub


    ''' <summary>
    ''' 注册 Function Calling 工具到 LLM 客户端
    ''' </summary>
    ''' <param name="allowWriteFile">
    ''' 是否允许LLM agent写文件
    ''' </param>
    Protected Sub RegisterTools(llm As LLMClient, allowWriteFile As Boolean, Optional fileWsDir As String = Nothing)
        Dim shellTool As New ShellTool(_config, _context.WorkspaceDir, _logger)

        Call RegisterFileTools(llm, allowWriteFile, wsDir:=fileWsDir)

        ' 注册命令行执行工具
        llm.AddFunction(shellTool, "run_rscript")
        llm.AddFunction(shellTool, "run_python")
        llm.AddFunction(shellTool, "run_rsharp")
    End Sub

    Protected Sub LogInfo(msg As String)
        _logger?.Invoke(msg)
    End Sub

End Class

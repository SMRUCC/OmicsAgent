Imports Microsoft.VisualBasic.Language
Imports Microsoft.VisualBasic.Linq
Imports Microsoft.VisualBasic.MIME.application.json
Imports Microsoft.VisualBasic.MIME.application.json.LenientJson
Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime
Imports OmicsAgent.AppRuntime.Ini
Imports OmicsAgent.ReportData

' ============================================================================
' 模块 14: 撰写论文初稿（生成 HTML 报告并转换为 PDF）
' ============================================================================

''' <summary>
''' 论文初稿撰写模块。
''' 
''' 针对数据分析流程中每一步的研究分析结果总结性文本文件和生成的表格以及插图，
''' 采用中文以论文的形式撰写分析结果报告。
''' 
''' 报告要求：
''' - 每一章中出现的论文插图和表格，需要编写对应的图注文本说明
''' - 图注文本需要先中文编写，再翻译为英文
''' - 每一步分析结果采用独立的章节详尽描述
''' - 以 A3 大小编写 HTML 文件
''' - 使用 wkhtmltopdf 工具转换为 PDF 文件
''' </summary>
Public Class ReportModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Paper Draft Report"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 14

    Public Property debugCache As Boolean = False

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "report_"
        End Get
    End Property

    Protected Overrides ReadOnly Property NeedsPlantSteps As Boolean
        Get
            Return False
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Dim crossOmicsSection As String = ""
        Dim multiOmicsGuide As String = ""

        If _context.IsMultiOmics Then
            Dim omicsList As String = _context.Datasets _
                .Select(Function(d) $"[{d.Id}] {d.DisplayName}（{d.OmicsType}）") _
                .JoinBy("、")

            crossOmicsSection = "
   - 4.12 跨组学整合分析"

            multiOmicsGuide = $"

# 多组学报告撰写要求（重要）
本次研究为多组学分析，共涉及 {_context.Datasets.Count} 个组学：{omicsList}。
- 材料与方法部分需分别交代每个组学的数据来源、测定平台、数据单位与预处理方式，
  并说明各组学样本是如何对齐到同一生物学个体的（共有个体 {If(_context.SubjectIDs Is Nothing, 0, _context.SubjectIDs.Length)} 个）
- 结果部分的每个小节，凡涉及单组学分析的，都必须明确标注该结果来自哪个组学，
  不要把不同组学的结果混在一起叙述而不加区分
- 必须包含独立的「跨组学整合分析」小节，这是多组学研究区别于单组学研究的核心章节
- 讨论部分需要重点论述多组学证据之间的相互印证关系：
  不同组学层次的发现是否指向一致的生物学机制，何处相互支持，何处存在矛盾及其可能原因
- 结论部分应当给出贯穿多个组学层次的整体性结论，而不是各组学结论的简单罗列"
        End If

        Return $"为撰写综合性研究论文初稿设计计划，基于分析结果撰写报告。
报告应包含：
1. 标题和摘要（中文）
2. 引言（研究背景、目标）
3. 材料与方法（数据来源、分析方法）
4. 结果（按分析模块组织）：
   - 4.1 数据预处理
   - 4.2 PCA/PLSDA/OPLSDA 分析
   - 4.3 比对组别设计
   - 4.4 LIMMA 差异分析
   - 4.5 KEGG 功能分析
   - 4.6 WGCNA 性状关联分析
   - 4.7 CMeans 模糊聚类分析
   - 4.8 动态贝叶斯网络分析
   - 4.9 PLS-PM 因果路径分析
   - 4.10 随机森林分组预测分析
   - 4.11 回归分析（逻辑回归与线性回归）{crossOmicsSection}
5. 讨论（生物学机制解读）
6. 结论
7. 图表（图注同时提供中英文）{multiOmicsGuide}"
    End Function

    ''' <summary>调用 LLM 生成分析计划</summary>
    Protected Overrides Async Function GeneratePlanAsync(llm As LLMClient, cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Return Await Task.FromResult(New ModulePlan With {
            .execution_steps = {
                New [Step] With {.action = "以论文的形式生成分析结果报告", .goal = GeneratePlanPromptText()}
            },
            .goal = "以论文的形式生成分析结果报告",
            .module_name = ModuleName
        })
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 研究报告的整体结构完整性
2. 各章节内容的覆盖情况
3. 图表及其图注的完整性
4. 讨论部分对生物学机制的解读深度
5. 报告与用户研究主题的契合度"
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Return Await Task.FromResult(GetConclusionItems)
    End Function

    ''' <summary>调用 LLM 编写并执行脚本</summary>
    Protected Overrides Async Function GenerateAndRunScriptAsync(llm As LLMClient, plan As ModulePlan, [step] As [Step], cancellationToken As CancellationToken) As Task
        ' 这个模块直接由 VB.NET 代码生成 HTML 报告，并通过 LLM 函数调用 wkhtmltopdf 转换为 PDF
        LogInfo("Generating research report...")

        ' 收集所有模块的结论文本
        Dim conclusions = CollectModuleConclusions()
        ' 收集所有图表
        Dim figures = CollectAllFigures().ToArray
        ' 收集所有表格
        Dim tables = CollectAllTables().ToArray

        ' 调用 LLM 生成报告的各章节内容
        Dim reportCache As String = Path.Combine(_context.WorkspaceDir, "analysis", "report.json")
        Dim reportContent As ReportContent = Nothing

        ' 20260730
        ' 调试模式下优先复用缓存；旧版本缓存中的正文字段为字符串，与当前的内容块数组
        ' 模型不兼容，故此处必须捕获解析异常并自动回退到重新生成，避免程序中断
        If debugCache AndAlso reportCache.FileExists Then
            Try
                reportContent = reportCache.LoadJSON(Of ReportContent)
            Catch ex As Exception
                reportContent = Nothing
                LogInfo($"The cached report data is incompatible with current data model, regenerate it: {ex.Message}")
            End Try
        End If

        If reportContent Is Nothing Then
            reportContent = Await GenerateReportContentAsync(conclusions, figures, tables, cancellationToken)
        End If

        Dim resource As New ReportResource With {.figures = figures, .tables = tables}
        Dim analysisDir As String = Path.Combine(_context.WorkspaceDir, "analysis")
        Dim outputFormat As String = _config.Report.OutputFormat

        Call JsonContract.GetJson(reportContent).SaveTo(reportCache)

        ' 由同一份报告内容对象出发，按运行时配置选择输出 PDF、Word 或两者
        If ReportOutputFormats.RequirePdf(outputFormat) Then
            Call RenderPdfReport(reportContent, resource, analysisDir)
        End If

        If ReportOutputFormats.RequireDocx(outputFormat) Then
            Call reportContent.BuildWordReport(resource, Path.Combine(analysisDir, "report.docx"), AddressOf LogInfo)
        End If
    End Function

    ''' <summary>旧有输出路径：内容块渲染为 HTML，再由 wkhtmltopdf 转换为 PDF</summary>
    Private Sub RenderPdfReport(reportContent As ReportContent, resource As ReportResource, analysisDir As String)
        Dim htmlPath As String = Path.Combine(analysisDir, "report.html")
        Dim html As String = reportContent.BuildHtmlReport(resource, AddressOf LogInfo)

        Call html.SaveTo(htmlPath)

        LogInfo($"HTML report generated: {htmlPath}")

        ' 通过 LLM 函数调用工具执行 wkhtmltopdf 转换为 PDF
        Dim pdfPath As String = Path.Combine(analysisDir, "report.pdf")

        Call New ShellTool(_config, _context.WorkspaceDir, _logger).run_wkhtmltopdf(htmlPath, pdfPath, extra_args:="")
    End Sub

    ''' <summary>收集所有模块的结论文本</summary>
    Private Function CollectModuleConclusions() As Dictionary(Of Integer, String)
        Dim results As New Dictionary(Of Integer, String)()

        ' 20260805
        ' 结果表格与报告模块已改为「主循环之后强制执行」，当用户通过 --module 只运行
        ' 部分模块时，未执行模块的产出目录并不存在，故此处必须做存在性判断，
        ' 否则会直接抛出 FileNotFoundException 导致整个报告生成中断
        For Each result As ModuleResult In _context.ModuleResults
            Dim conclusionFile = Path.Combine(result.OutputDir, "conclusion.md")
            Dim idx As Integer = result.ModuleIndex

            If conclusionFile.FileExists Then
                results(idx) = conclusionFile.ReadAllText(Encoding.UTF8)
            End If
        Next

        Return results
    End Function

    ''' <summary>收集所有图表</summary>
    Private Iterator Function CollectAllFigures() As IEnumerable(Of ResourceFile)
        For Each result As ModuleResult In _context.ModuleResults
            Dim figuresDir As String = Path.Combine(result.OutputDir, "figures")
            Dim idx As Integer = result.ModuleIndex

            ' 未执行的模块没有 figures 目录，跳过而不是抛异常
            If Not Directory.Exists(figuresDir) Then
                Continue For
            End If

            For Each f In Directory.GetFiles(figuresDir, "*.png")
                Yield New ResourceFile(idx, f)
            Next
        Next
    End Function

    ''' <summary>收集所有表格</summary>
    Private Iterator Function CollectAllTables() As IEnumerable(Of ResourceFile)
        For Each result As ModuleResult In _context.ModuleResults
            Dim tablesDir = result.Workdir
            Dim idx As Integer = result.ModuleIndex

            ' 未执行的模块没有工作目录，跳过而不是抛异常
            If String.IsNullOrEmpty(tablesDir) OrElse Not Directory.Exists(tablesDir) Then
                Continue For
            End If

            For Each f In Directory.GetFiles(tablesDir, "*.csv")
                Yield New ResourceFile(idx, f)
            Next
        Next
    End Function

    ''' <summary>每个报告生成阶段的最大 JSON 解析重试次数</summary>
    Private Const MaxReportStageRetries As Integer = 3

    ''' <summary>
    ''' 结构化内容块（Block）的 schema 说明，供四个生成阶段的提示词统一引用。
    ''' 
    ''' 报告正文不再由 LLM 直接书写 markdown 文本，而是输出「内容块对象数组」，
    ''' 由程序侧渲染为 HTML 或 Word，从根源上消除 markdown 语法错误导致的排版混乱。
    ''' </summary>
    Private Const BlockSchemaPrompt As String = "
# 正文内容块（Block）格式规范

报告的所有正文部分均不得书写 markdown 语法文本，必须输出「内容块对象数组」。
数组中的每个元素都是一个对象，通过 type 字段声明该块的类型，不同类型使用各自专属的字段。
所有内容块之间为平级关系，不允许嵌套。

可用的块类型及其字段：

1. 段落（最常用，正文应以段落为主）
   {""type"": ""paragraph"", ""content"": ""段落的完整文本内容""}

2. 小标题（level 取值 2 到 4；正文内部如需分小节时使用，不要使用 level 1）
   {""type"": ""heading"", ""level"": 3, ""content"": ""小标题文本""}

3. 列表（ordered 为 true 表示有序列表，false 表示无序列表）
   {""type"": ""list"", ""ordered"": false, ""items"": [""第一项"", ""第二项"", ""第三项""]}

4. 表格（headers 为表头；rows 为二维数组，每行的元素个数必须与 headers 一致；
   alignments 可选，取值为 left / center / right，个数与 headers 一致）
   {""type"": ""table"", ""headers"": [""基因"", ""logFC""], ""rows"": [[""TP53"", ""2.31""], [""EGFR"", ""-1.85""]], ""alignments"": [""left"", ""right""]}

5. 引用块（用于强调重要结论）
   {""type"": ""blockquote"", ""content"": ""被强调的文本内容""}

6. 代码块（language 为语言标识，如 r / python / bash）
   {""type"": ""code"", ""language"": ""r"", ""content"": ""源代码文本""}

7. 分隔线
   {""type"": ""hr""}

强制约束（务必严格遵守）：
- content 字段的值必须是纯文本，其中不得出现 #、*、-、|、`、> 等 markdown 标记符号；
- 需要强调、分点、制表时，必须改用上述对应的块类型来表达，而不是在文本中书写 markdown 语法；
- 每个块对象都必须包含 type 字段，且 type 的取值必须来自上述列表；
- 段落文本应完整成句，不要将一个段落拆分为多个仅有短句的块。
"

    ''' <summary>
    ''' 调用 LLM 生成报告内容。采用分阶段（前置部分 / 结果章节 / 讨论结论 / 材料与方法）逐步生成，
    ''' 复用同一个 LLMClient 实例，并针对每个阶段加入 JSON 解析错误重试机制，确保返回有效的 ReportContent。
    ''' </summary>
    ''' <param name="conclusions">各模块结论文本（module_index -> 总结）</param>
    ''' <param name="figures">可用图片资源清单</param>
    ''' <param name="tables">可用表格资源清单</param>
    Private Async Function GenerateReportContentAsync(conclusions As Dictionary(Of Integer, String), figures As ResourceFile(), tables As ResourceFile(), cancellationToken As CancellationToken) As Task(Of ReportContent)
        Using llm As LLMClient = _config.CreateLLMClient(FolderBaseName & "-create_report", _context.TmpDir)
            Call RegisterFileTools(llm, allowWriteFile:=False)

            ' 构建阶段共享的上下文信息（研究主题、数据集、各模块总结等）
            Dim ctx As String = BuildContextInfo()

            ' 各模块段落总结文本
            Dim conclusionsText As String = String.Join(vbCrLf + vbCrLf, conclusions.Select(Function(c) $"## 模块 {c.Key}:{vbCrLf}{c.Value}"))

            ' 可用图片与表格清单
            Dim figuresList As String = String.Join(vbCrLf, figures.Select(Function(f) $"- 模块 {f.module_index}: {Path.GetFileName(f.filename)}"))
            Dim tablesList As String = String.Join(vbCrLf, tables.Select(Function(t) $"- 模块 {t.module_index}: {t.filename}"))

            ' 复用同一个 llm 对象，分四个阶段逐步生成报告内容
            Dim report As New ReportContent()
            report.title = "组学数据分析报告"

            ' 阶段一：标题 / 摘要 / 关键词 / 引言
            Dim front As ReportContent = Await GenerateFrontMatterAsync(llm, ctx, conclusionsText, cancellationToken)
            report.title = front.title
            report.abstract = front.abstract
            report.keywords = front.keywords
            report.introduction = front.introduction

            If cancellationToken.IsCancellationRequested Then Return report

            ' 阶段二：各分析模块的结果章节（含图 / 表引用）
            Dim results As ReportContent = Await GenerateResultsSectionsAsync(llm, ctx, conclusionsText, figuresList, tablesList, cancellationToken)
            report.results_sections = results.results_sections

            If cancellationToken.IsCancellationRequested Then Return report

            ' 阶段三：讨论与结论
            Dim disc As ReportContent = Await GenerateDiscussionConclusionAsync(llm, ctx, cancellationToken)
            report.discussion = disc.discussion
            report.conclusion = disc.conclusion

            If cancellationToken.IsCancellationRequested Then Return report

            ' 阶段四：材料与方法（阅读工作区中保存的 R 脚本）
            Dim methods As ReportContent = Await GenerateMethodologyAsync(llm, ctx, cancellationToken)
            report.materials_methods = methods.materials_methods

            ' 兜底标题，保证最终 ReportContent 始终有效
            If String.IsNullOrEmpty(report.title) Then report.title = "组学数据分析报告"

            ' 保留 report.txt 产出（便于排错），完整 JSON 仍由调用方写入 report.json
            Call JsonContract.GetJson(report).SaveTo($"{Workspace}/report.txt")

            Return report
        End Using
    End Function

    ''' <summary>
    ''' 统一的「对话 + JSON 解析 + 错误重试」助手。复用同一会话上下文，解析失败时追加纠正提示重新生成，
    ''' 直至解析成功或达到最大重试次数；失败时返回默认空 ReportContent，确保调用方始终获得有效对象。
    ''' </summary>
    Private Async Function ChatJsonWithRetryAsync(llm As LLMClient, initialPrompt As String, correctionPrompt As String, stageLabel As String, cancellationToken As CancellationToken) As Task(Of ReportContent)
        Dim lastErr As String = ""
        For attempt As Integer = 1 To MaxReportStageRetries
            If cancellationToken.IsCancellationRequested Then Exit For

            Dim prompt As String = If(attempt = 1, initialPrompt, initialPrompt & vbCrLf & vbCrLf & correctionPrompt & vbCrLf & lastErr)
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim json As String = Strings.Trim(resp.ExtractJsonFromResponse).Replace("\n\n", "\n")

            ' 落盘每个阶段的原始响应，便于排错
            Call resp.output.SaveTo($"{Workspace}/report_{stageLabel}.txt")

            If Not String.IsNullOrEmpty(json) Then
                Try
                    Dim part As ReportContent = LenientJsonParser.ParseJSON(json).CreateObject(Of ReportContent)
                    If part IsNot Nothing Then
                        Return part
                    End If
                Catch ex As Exception
                    LogInfo($"[{stageLabel}] 第 {attempt} 次解析报告 JSON 失败：{ex.Message}")
                End Try
            Else
                LogInfo($"[{stageLabel}] 第 {attempt} 次未获取到有效 JSON")
            End If

            lastErr = "上一轮你返回的 JSON 无效、缺失必填字段或无法解析，请重新检查格式，仅返回符合要求的合法 JSON，不要包含任何额外解释或 markdown 代码围栏。"
        Next

        LogInfo($"[{stageLabel}] 已达到最大重试次数（{MaxReportStageRetries}），该部分将使用默认空值。")
        Return New ReportContent()
    End Function

    ''' <summary>阶段一：生成标题 / 摘要 / 关键词 / 引言</summary>
    Private Async Function GenerateFrontMatterAsync(llm As LLMClient, ctx As String, conclusionsText As String, cancellationToken As CancellationToken) As Task(Of ReportContent)
        Dim prompt As String = $"
你是一位生物医学研究论文撰写专家。请基于以下分析结果撰写一份完整中文研究报告的前置部分。

# 工作区与上下文
{ctx}

# 各模块总结
{conclusionsText}
{BlockSchemaPrompt}
# 你的任务
仅撰写报告的前置部分，包含：
1. 标题（title）——基于用户研究主题，纯文本字符串
2. 摘要（abstract）——200-300 字，纯文本字符串
3. 关键词（keywords）——5-8 个，字符串数组
4. 引言（introduction）——内容块数组，分两个 paragraph 块分别讲述用户的研究背景、目的与意义，每一段大约 300 字，总共 600 字左右

以下面的 JSON 格式返回结果，不要包含任何额外解释或 markdown 代码围栏：
{{
  ""title"": ""<中文标题>"",
  ""abstract"": ""<中文摘要>"",
  ""keywords"": [""<关键词1>"", ""<关键词2>""],
  ""introduction"": [
    {{""type"": ""paragraph"", ""content"": ""<研究背景，约 300 字>""}},
    {{""type"": ""paragraph"", ""content"": ""<研究目的与意义，约 300 字>""}}
  ]
}}
"
        Dim correction As String = "请重新仅返回包含 title / abstract / keywords / introduction 四个字段的合法 JSON。其中 title 与 abstract 必须是字符串，keywords 必须是字符串数组，introduction 必须是内容块对象数组，数组中每个对象都必须包含 type 字段，且不得在 content 中书写任何 markdown 语法符号。"
        Return Await ChatJsonWithRetryAsync(llm, prompt, correction, "stage1_front", cancellationToken)
    End Function

    ''' <summary>阶段二：生成各分析模块的结果章节（含图 / 表引用）</summary>
    Private Async Function GenerateResultsSectionsAsync(llm As LLMClient, ctx As String, conclusionsText As String, figuresList As String, tablesList As String, cancellationToken As CancellationToken) As Task(Of ReportContent)
        Dim prompt As String = $"
你是一位生物医学研究论文撰写专家。请基于以下分析结果撰写报告中「结果（Results）」部分的各分析模块章节。

# 工作区与上下文
{ctx}

# 各模块总结
{conclusionsText}

# 可用图片
{figuresList}

# 可用表格
{tablesList}

对于表格内容，你应该首先通过 peek_csv 工具进行表格文件的内容预览，然后再决定将哪些表格，以及表格中的哪些字段放入到分析结果报告中。
在每一个小节中，需要进行图和表的混合展示，并且应该至少引用一张图以及一张表。
图引用统一放在该小节的 figures 数组中，表引用统一放在该小节的 tables 数组中，两者结构基本一致，
区别在于：figures 元素的 type 固定为 figure；tables 元素的 type 固定为 table，并额外通过 fields 字符串数组指定需要在报告中展示的列名。
figures 与 tables 中的 file 字段必须取自上面「可用图片」「可用表格」清单中真实存在的文件名，不得虚构。
{BlockSchemaPrompt}
# 你的任务
仅撰写「结果（Results）」部分，按模块（module_index）组织，每个模块详尽描述，并给出中英文双语图注 / 表注。
其中每个小节的 content 字段必须是内容块数组（不是字符串），正文以 paragraph 块为主，必要时可使用 list 或 table 块。
以下面的 JSON 格式返回结果，不要包含任何额外解释或 markdown 代码围栏：
{{
  ""results_sections"": [
    {{
      ""module_index"": 1,
      ""title"": ""<章节标题>"",
      ""content"": [
        {{""type"": ""paragraph"", ""content"": ""<该小节的结果描述正文>""}},
        {{""type"": ""paragraph"", ""content"": ""<对结果的进一步解读>""}}
      ],
      ""figures"": [
         {{""file"": ""<文件名>"", ""type"": ""figure"", ""caption_cn"": ""<中文图注>"", ""caption_en"": ""<英文图注>""}}
      ],
      ""tables"": [
         {{""file"": ""<文件名>"", ""type"": ""table"", ""caption_cn"": ""<中文表注>"", ""caption_en"": ""<英文表注>"", ""fields"": [""字段名称1"", ""字段名称2""]}}
      ]
    }}
  ]
}}
"
        Dim correction As String = "请重新仅返回包含 results_sections 数组的合法 JSON，每个元素必须包含 module_index / title / content / figures / tables 字段。其中 content 必须是内容块对象数组而不是字符串，数组中每个对象都必须包含 type 字段，且不得在 content 文本中书写任何 markdown 语法符号。"
        Return Await ChatJsonWithRetryAsync(llm, prompt, correction, "stage2_results", cancellationToken)
    End Function

    ''' <summary>阶段三：生成讨论与结论</summary>
    Private Async Function GenerateDiscussionConclusionAsync(llm As LLMClient, ctx As String, cancellationToken As CancellationToken) As Task(Of ReportContent)
        Dim prompt As String = $"
你是一位生物医学研究论文撰写专家。请基于前文已生成的研究结果，撰写报告的「讨论（Discussion）」与「结论（Conclusion）」部分。

# 工作区与上下文
{ctx}

{BlockSchemaPrompt}
# 你的任务
仅撰写以下两个部分，两者均为内容块数组：
1. 讨论（discussion）——分多个 paragraph 块进行生物学机制解读，并与知识库中已有文献进行对比，大约 1000 字
2. 结论（conclusion）——主要发现的精炼总结，大约 600 字

以下面的 JSON 格式返回结果，不要包含任何额外解释或 markdown 代码围栏：
{{
  ""discussion"": [
    {{""type"": ""paragraph"", ""content"": ""<讨论第一段>""}},
    {{""type"": ""paragraph"", ""content"": ""<讨论第二段>""}}
  ],
  ""conclusion"": [
    {{""type"": ""paragraph"", ""content"": ""<结论正文>""}}
  ]
}}
"
        Dim correction As String = "请重新仅返回包含 discussion / conclusion 两个字段的合法 JSON。两个字段都必须是内容块对象数组而不是字符串，数组中每个对象都必须包含 type 字段，且不得在 content 文本中书写任何 markdown 语法符号。"
        Return Await ChatJsonWithRetryAsync(llm, prompt, correction, "stage3_discussion", cancellationToken)
    End Function

    ''' <summary>阶段四：阅读工作区中保存的 R 脚本，生成材料与方法</summary>
    Private Async Function GenerateMethodologyAsync(llm As LLMClient, ctx As String, cancellationToken As CancellationToken) As Task(Of ReportContent)
        Dim prompt As String = $"
你是一位生物医学研究论文撰写专家。请基于本次分析实际执行的 R 脚本，撰写报告中「材料与方法（Materials and Methods）」部分。

# 工作区与上下文
{ctx}

# R 脚本所在位置
本次分析过程中，各分析模块编写的 R 脚本文件保存在以下目录中（请自行检索）：
- 临时工作区目录（含各模块子目录下的 scripts 文件夹）：{_context.TmpDir}
- 统一脚本目录：{_context.ScriptsDir}

# 你的任务
1. 使用 list_tree / list_files 工具在以上目录中查找所有 .R 脚本文件；
2. 使用 read_file 工具阅读这些 R 脚本，了解实际采用的数据来源与分析方法（如 PCA / PLSDA / OPLSDA、LIMMA 差异分析、KEGG 富集、WGCNA、CMeans、动态贝叶斯网络、PLS-PM 等）；
3. 基于实际执行的脚本内容，撰写「材料与方法」部分，描述数据来源、预处理流程与所采用的分析方法。
{BlockSchemaPrompt}
以下面的 JSON 格式返回结果，materials_methods 必须是内容块数组，不要包含任何额外解释或 markdown 代码围栏：
{{
  ""materials_methods"": [
    {{""type"": ""paragraph"", ""content"": ""<数据来源与样本描述>""}},
    {{""type"": ""heading"", ""level"": 3, ""content"": ""数据预处理""}},
    {{""type"": ""paragraph"", ""content"": ""<预处理流程描述>""}},
    {{""type"": ""heading"", ""level"": 3, ""content"": ""统计分析方法""}},
    {{""type"": ""paragraph"", ""content"": ""<所采用的分析方法及其参数设置>""}}
  ]
}}
"
        Dim correction As String = "请重新仅返回包含 materials_methods 字段的合法 JSON，该字段必须是内容块对象数组而不是字符串，数组中每个对象都必须包含 type 字段，不得在 content 文本中书写任何 markdown 语法符号，并且必须确实阅读了工作区中的 R 脚本文件。"
        Return Await ChatJsonWithRetryAsync(llm, prompt, correction, "stage4_methods", cancellationToken)
    End Function
End Class

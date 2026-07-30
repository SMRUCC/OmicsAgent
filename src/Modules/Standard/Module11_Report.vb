Imports Microsoft.VisualBasic.Linq
Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime
Imports OmicsAgent.ReportData

' ============================================================================
' 模块 11: 撰写论文初稿（生成 HTML 报告并转换为 PDF）
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
    Public Overrides ReadOnly Property ModuleIndex As Integer = 11

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
        Return "为撰写综合性研究论文初稿设计计划，基于分析结果撰写报告。
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
5. 讨论（生物学机制解读）
6. 结论
7. 图表（图注同时提供中英文）"
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
        Dim reportContent = Await GenerateReportContentAsync(conclusions, figures, tables, cancellationToken)

        ' 生成 HTML 文件
        Dim htmlPath = Path.Combine(_context.WorkspaceDir, "analysis", "report.html")
        Dim html = reportContent.BuildHtmlReport(New ReportResource With {.figures = figures, .tables = tables}, AddressOf LogInfo)

        html.SaveTo(htmlPath)
        reportContent.GetJson.SaveTo(Path.Combine(_context.WorkspaceDir, "analysis", "report.json"))

        LogInfo($"HTML report generated: {htmlPath}")

        ' 通过 LLM 函数调用工具执行 wkhtmltopdf 转换为 PDF
        Dim pdfPath = Path.Combine(_context.WorkspaceDir, "analysis", "report.pdf")

        Call New ShellTool(_config, _context.WorkspaceDir, _logger).run_wkhtmltopdf(htmlPath, pdfPath, extra_args:="")
    End Function

    ''' <summary>收集所有模块的结论文本</summary>
    Private Function CollectModuleConclusions() As Dictionary(Of Integer, String)
        Dim results As New Dictionary(Of Integer, String)()

        For Each result As ModuleResult In _context.ModuleResults
            Dim conclusionFile = Path.Combine(result.OutputDir, "conclusion.md")
            Dim idx As Integer = result.ModuleIndex

            results(idx) = conclusionFile.ReadAllText(Encoding.UTF8)
        Next

        Return results
    End Function

    ''' <summary>收集所有图表</summary>
    Private Iterator Function CollectAllFigures() As IEnumerable(Of HtmlReport.ResourceFile)
        For Each result As ModuleResult In _context.ModuleResults
            Dim figuresDir As String = Path.Combine(result.OutputDir, "figures")
            Dim idx As Integer = result.ModuleIndex

            For Each f In Directory.GetFiles(figuresDir, "*.png")
                Yield New ResourceFile(idx, f)
            Next
        Next
    End Function

    ''' <summary>收集所有表格</summary>
    Private Iterator Function CollectAllTables() As IEnumerable(Of HtmlReport.ResourceFile)
        For Each result As ModuleResult In _context.ModuleResults
            Dim tablesDir = result.Workdir
            Dim idx As Integer = result.ModuleIndex

            For Each f In Directory.GetFiles(tablesDir, "*.csv")
                Yield New ResourceFile(idx, f)
            Next
        Next
    End Function

    ''' <summary>每个报告生成阶段的最大 JSON 解析重试次数</summary>
    Private Const MaxReportStageRetries As Integer = 3

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
            Call report.GetJson.SaveTo($"{Workspace}/report.txt")

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
                    Dim part As ReportContent = json.LoadJSON(Of ReportContent)
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

# 你的任务
仅撰写报告的前置部分，包含：
1. 标题（title）——基于用户研究主题
2. 摘要（abstract）——200-300 字
3. 关键词（keywords）——5-8 个
4. 引言（introduction）——研究背景、目的与意义

以下面的 JSON 格式返回结果，不要包含任何额外解释或 markdown 代码围栏：
{{
  ""title"": ""<中文标题>"",
  ""abstract"": ""<中文摘要>"",
  ""keywords"": [""<关键词1>"", ""<关键词2>"", ...],
  ""introduction"": ""<中文引言>""
}}
"
        Dim correction As String = "请重新仅返回包含 title / abstract / keywords / introduction 四个字段的合法 JSON。"
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
在每一个小节中，需要进行图和表的混合展示，展示的图和表都以相同的数据结构存储在 figure_tables 这个属性中，这两种数据类型通过 type 属性值（figure 或 table）进行区分，对于 table 类别，仅仅是额外多了一个 fields 字符串数组属性。

# 你的任务
仅撰写「结果（Results）」部分，按模块（module_index）组织，每个模块详尽描述，并给出中英文双语图注 / 表注。
以下面的 JSON 格式返回结果：
{{
  ""results_sections"": [
    {{
      ""module_index"": 1,
      ""title"": ""<章节标题>"",
      ""content"": ""<章节内容>"",
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
        Dim correction As String = "请重新仅返回包含 results_sections 数组的合法 JSON，每个元素必须包含 module_index / title / content / figures / tables 字段。"
        Return Await ChatJsonWithRetryAsync(llm, prompt, correction, "stage2_results", cancellationToken)
    End Function

    ''' <summary>阶段三：生成讨论与结论</summary>
    Private Async Function GenerateDiscussionConclusionAsync(llm As LLMClient, ctx As String, cancellationToken As CancellationToken) As Task(Of ReportContent)
        Dim prompt As String = $"
你是一位生物医学研究论文撰写专家。请基于前文已生成的研究结果，撰写报告的「讨论（Discussion）」与「结论（Conclusion）」部分。

# 工作区与上下文
{ctx}

# 你的任务
仅撰写以下两个部分：
1. 讨论（discussion）——生物学机制解读，并与已有文献进行对比
2. 结论（conclusion）——主要发现的精炼总结

以下面的 JSON 格式返回结果，不要包含任何额外解释或 markdown 代码围栏：
{{
  ""discussion"": ""<中文讨论>"",
  ""conclusion"": ""<中文结论>""
}}
"
        Dim correction As String = "请重新仅返回包含 discussion / conclusion 两个字段的合法 JSON。"
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
3. 基于实际执行的脚本内容，撰写「材料与方法」部分文本，描述数据来源、预处理流程与所采用的分析方法。

以下面的 JSON 格式返回结果，不要包含任何额外解释或 markdown 代码围栏：
{{
  ""materials_methods"": ""<中文材料与方法>""
}}
"
        Dim correction As String = "请重新仅返回包含 materials_methods 字段的合法 JSON，并且必须确实阅读了工作区中的 R 脚本文件。"
        Return Await ChatJsonWithRetryAsync(llm, prompt, correction, "stage4_methods", cancellationToken)
    End Function
End Class

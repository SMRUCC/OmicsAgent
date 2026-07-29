Imports Microsoft.VisualBasic.Data.Framework.IO
Imports Microsoft.VisualBasic.Data.Framework.StorageProvider
Imports Microsoft.VisualBasic.Linq
Imports Microsoft.VisualBasic.MIME.text.markdown
Imports Microsoft.VisualBasic.Net.Http
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
        Dim html = reportContent.BuildHtmlReport(New ReportResource With {.figures = figures, .tables = tables}, AddressOf LogInfo).Replace("<br><br>", "")

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

    ''' <summary>调用 LLM 生成报告内容</summary>
    Private Async Function GenerateReportContentAsync(conclusions As Dictionary(Of Integer, String), figures As ResourceFile(), tables As ResourceFile(), cancellationToken As CancellationToken) As Task(Of ReportContent)
        Using llm As LLMClient = _config.CreateLLMClient(FolderBaseName & "-create_report", _context.TmpDir)
            Dim prompt = $"
你是一位生物医学研究论文撰写专家。请基于分析结果撰写一份完整的中文研究报告。

{BuildContextInfo()}

# 各模块总结
{String.Join(vbCrLf + vbCrLf, conclusions.Select(Function(c) $"## 模块 {c.Key}:{vbCrLf}{c.Value}"))}

# 可用图片
{String.Join(vbCrLf, figures.Select(Function(f) $"- 模块 {f.module_index}: {Path.GetFileName(f.filename)}"))}

# 可用表格
{String.Join(vbCrLf, tables.Select(Function(t) $"- 模块 {t.module_index}: {t.filename}"))}

对于表格内容，你应该首先通过 peek_csv 工具进行表格文件的内容预览，然后再决定将哪些表格，以及表格中的哪些字段放入到分析结果报告中。
在每一个小节中，需要进行图和表的混合展示，展示的图和表都以相同的数据结构存储在figure_tables这个属性中，这两种数据类型通过figure_tables.type属性值是否为table还是figure来进行区分，对于table类别，仅仅是额外多了一个fields字符串数组属性

# 你的任务
撰写一份完整的中文研究论文初稿，结构如下：
1. 标题（Title）- 基于用户研究主题
2. 摘要（Abstract）- 200-300 字
3. 关键词（Keywords）- 5-8 个
4. 引言（Introduction）- 研究背景、目的、意义
5. 材料与方法（Materials and Methods）- 数据来源、分析方法
6. 结果（Results）- 按模块组织，每个模块详尽描述
7. 讨论（Discussion）- 生物学机制解读，与文献对比
8. 结论（Conclusion）- 主要发现总结

对于涉及的每个图表，撰写中英文双语图注。以下面的 JSON 格式返回结果，以方便我做自动化解析：
{{
  ""title"": ""<中文标题>"",
  ""abstract"": ""<中文摘要>"",
  ""keywords"": [""<关键词1>"", ""<关键词2>""],
  ""introduction"": ""<中文引言>"",
  ""materials_methods"": ""<中文材料与方法>"",
  ""results_sections"": [
    {{
      ""module_index"": 1,
      ""title"": ""<章节标题>"",
      ""content"": ""<章节内容>"",
      ""figures"": [
         {{""file"": ""<文件名>"", ""type"": ""figure"", ""caption_cn"": ""<中文图注>"", ""caption_en"": ""<英文图注>""}},
         ...
      ],
      ""tables"": [
         {{""file"": ""<文件名>"", ""type"": ""table"", ""caption_cn"": ""<中文表注>"", ""caption_en"": ""<英文表注>"", ""fields"": [""字段名称1"",""字段名称2"", ...]}},
         ...
      ]
    }}
  ],
  ""discussion"": ""<中文讨论>"",
  ""conclusion"": ""<中文结论>""
}}
"
            Call RegisterFileTools(llm, allowWriteFile:=False)

            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim json = Strings.Trim(resp.ExtractJsonFromResponse).Replace("\n\n", "\n")

            Call resp.output.SaveTo($"{Workspace}/report.txt")

            If Not String.IsNullOrEmpty(json) Then
                Try
                    Return json.LoadJSON(Of ReportContent)
                Catch ex As Exception
                    LogInfo($"Failed to parse report JSON: {ex.Message}")
                End Try
            End If

            ' 返回默认内容
            Return New ReportContent() With {
                .title = "组学数据分析报告",
                .abstract = resp.output,
                .introduction = "",
                .materials_methods = "",
                .discussion = "",
                .conclusion = ""
            }
        End Using
    End Function
End Class

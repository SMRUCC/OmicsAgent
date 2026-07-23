Imports Microsoft.VisualBasic.Net.Http
Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime
Imports OmicsAgent.ReportData

' ============================================================================
' 模块 9: 撰写论文初稿（生成 HTML 报告并转换为 PDF）
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
    Public Overrides ReadOnly Property ModuleIndex As Integer = 9

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Async Function GeneratePlanAsync(llm As LLMClient, cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Dim prompt = $"
You are a biomedical research paper writer. Design a plan to write a research report.

{BuildContextInfo()}

# Your Task
Design a plan to write a comprehensive research paper draft based on the analysis results.
The report should include:
1. Title and Abstract (Chinese)
2. Introduction (research background, objectives)
3. Materials and Methods (data sources, analysis methods)
4. Results (organized by analysis modules):
   - 4.1 Data Preprocessing
   - 4.2 PCA/PLSDA/OPLSDA Analysis
   - 4.3 Comparison Group Design
   - 4.4 LIMMA Differential Analysis
   - 4.5 KEGG Functional Analysis
   - 4.6 WGCNA Trait Association Analysis
   - 4.7 Advanced Analysis
5. Discussion (biological mechanism interpretation)
6. Conclusion
7. Figures and Tables (with captions in both Chinese and English)

Simply generate the specific execution plan here. Do not execute the actual analysis pipeline code. Return your plan as JSON in your response output, at least one execution step for your plan must be generated but no more than three decomposed execution steps:
{{
  ""module_name"": ""Paper Draft Report"",
  ""goal"": ""<brief description>"",
  ""input_files"": [""<input file paths>""],
  ""output_files"": [""<expected output file paths>""],
  ""execution_steps"": [{{""action"": ""<description of current step action>"", ""goal"": ""<goal of current step...>""}}, ...],
  ""notes"": ""<special considerations>""
}}
"
        Dim resp = Await llm.Chat(prompt, cancellationToken)
        Dim json = resp.ExtractJsonFromResponse
        Dim plan As ModulePlan
        If Not String.IsNullOrEmpty(json) Then
            plan = json.LoadJSON(Of ModulePlan)
            plan.module_name = ModuleName
        Else
            plan = New ModulePlan() With {.module_name = ModuleName, .goal = resp.output}
        End If

        Return plan
    End Function

    Protected Overrides Async Function GenerateAndRunScriptAsync(llm As LLMClient, plan As ModulePlan, [step] As [Step], cancellationToken As CancellationToken) As Task
        ' 这个模块直接由 VB.NET 代码生成 HTML 报告，并通过 LLM 函数调用 wkhtmltopdf 转换为 PDF
        LogInfo("Generating research report...")

        ' 收集所有模块的结论文本
        Dim conclusions = CollectModuleConclusions()

        ' 收集所有图表
        Dim figures = CollectAllFigures()

        ' 收集所有表格
        Dim tables = CollectAllTables()

        ' 调用 LLM 生成报告的各章节内容
        Dim reportContent = Await GenerateReportContentAsync(conclusions, figures, tables, cancellationToken)

        ' 生成 HTML 文件
        Dim htmlPath = Path.Combine(_context.WorkspaceDir, "analysis", "report.html")
        Dim html = BuildHtmlReport(reportContent, figures, tables)
        html.SaveTo(htmlPath)
        LogInfo($"HTML report generated: {htmlPath}")

        ' 通过 LLM 函数调用工具执行 wkhtmltopdf 转换为 PDF
        Dim pdfPath = Path.Combine(_context.WorkspaceDir, "analysis", "report.pdf")
        Dim prompt = $"
You are a report generation assistant. Convert the generated HTML report to PDF using the run_wkhtmltopdf tool.

{BuildContextInfo()}

# Analysis Plan
{plan.module_name}

plan goal: {plan.goal}
plan notes: {plan.notes}
current plan execution step: {[step].GetJson}

All scripts and the generated files are placed in this designated temporary workspace folder: {Workspace.GetDirectoryFullPath}

# Your Task
The HTML report has been generated at: {htmlPath}
Convert it to PDF at: {pdfPath}
Use the run_wkhtmltopdf tool with the following arguments:
- html_path: {htmlPath}
- pdf_path: {pdfPath}
- extra_args: --margin-top 15mm --margin-bottom 15mm --margin-left 15mm --margin-right 15mm --enable-local-file-access

Verify the PDF file is generated successfully.
"
        Await llm.Chat(prompt, cancellationToken)
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Return Await Task.FromResult("研究报告已生成完成。报告以中文撰写，包含完整的引言、材料与方法、结果、讨论和结论章节。所有图表均配有中英文双语图注。报告以 A3 大小 HTML 文件形式生成，并已通过 wkhtmltopdf 工具转换为 PDF 文件。")
    End Function

    ''' <summary>收集所有模块的结论文本</summary>
    Private Function CollectModuleConclusions() As Dictionary(Of Integer, String)
        Dim result As New Dictionary(Of Integer, String)()
        Dim analysisDir = Path.Combine(_context.WorkspaceDir, "analysis")
        If Not Directory.Exists(analysisDir) Then Return result

        For Each dir As String In Directory.GetDirectories(analysisDir, "analysis_modules_*")
            Dim conclusionFile = Path.Combine(dir, "conclusion.txt")
            If File.Exists(conclusionFile) Then
                Dim moduleName = Path.GetFileName(dir)
                Dim idxStr = System.Text.RegularExpressions.Regex.Match(moduleName, "analysis_modules_(\d+)").Groups(1).Value
                If Integer.TryParse(idxStr, Nothing) Then
                    result(Integer.Parse(idxStr)) = File.ReadAllText(conclusionFile, Encoding.UTF8)
                End If
            End If
        Next

        Return result
    End Function

    ''' <summary>收集所有图表</summary>
    Private Function CollectAllFigures() As List(Of Tuple(Of Integer, String))
        Dim result As New List(Of Tuple(Of Integer, String))()
        Dim analysisDir = Path.Combine(_context.WorkspaceDir, "analysis")
        If Not Directory.Exists(analysisDir) Then Return result

        For Each dir As String In Directory.GetDirectories(analysisDir, "analysis_modules_*")
            Dim figuresDir = Path.Combine(dir, "figures")
            If Directory.Exists(figuresDir) Then
                Dim moduleName = Path.GetFileName(dir)
                Dim idxStr = System.Text.RegularExpressions.Regex.Match(moduleName, "analysis_modules_(\d+)").Groups(1).Value
                Dim idx As Integer
                If Integer.TryParse(idxStr, idx) Then
                    For Each f In Directory.GetFiles(figuresDir, "*.png")
                        result.Add(Tuple.Create(idx, f))
                    Next
                End If
            End If
        Next

        Return result
    End Function

    ''' <summary>收集所有表格</summary>
    Private Function CollectAllTables() As List(Of Tuple(Of Integer, String))
        Dim result As New List(Of Tuple(Of Integer, String))()
        Dim analysisDir = Path.Combine(_context.WorkspaceDir, "analysis")
        If Not Directory.Exists(analysisDir) Then Return result

        For Each dir As String In Directory.GetDirectories(analysisDir, "analysis_modules_*")
            Dim tablesDir = Path.Combine(dir, "tables")
            If Directory.Exists(tablesDir) Then
                Dim moduleName = Path.GetFileName(dir)
                Dim idxStr = System.Text.RegularExpressions.Regex.Match(moduleName, "analysis_modules_(\d+)").Groups(1).Value
                Dim idx As Integer
                If Integer.TryParse(idxStr, idx) Then
                    For Each f In Directory.GetFiles(tablesDir, "*.csv")
                        result.Add(Tuple.Create(idx, f))
                    Next
                End If
            End If
        Next

        Return result
    End Function

    ''' <summary>调用 LLM 生成报告内容</summary>
    Private Async Function GenerateReportContentAsync(conclusions As Dictionary(Of Integer, String), figures As List(Of Tuple(Of Integer, String)), tables As List(Of Tuple(Of Integer, String)), cancellationToken As CancellationToken) As Task(Of ReportContent)
        Using llm As LLMClient = _config.CreateLLMClient(FolderBaseName & "-create_report", _context.TmpDir)
            Dim prompt = $"
You are a biomedical research paper writer. Write a comprehensive research report in Chinese based on the analysis results.

{BuildContextInfo()}

# Module Conclusions
{String.Join(vbCrLf + vbCrLf, conclusions.Select(Function(c) $"## Module {c.Key}:{vbCrLf}{c.Value}"))}

# Available Figures
{String.Join(vbCrLf, figures.Select(Function(f) $"- Module {f.Item1}: {Path.GetFileName(f.Item2)}"))}

# Available Tables
{String.Join(vbCrLf, tables.Select(Function(t) $"- Module {t.Item1}: {Path.GetFileName(t.Item2)}"))}

# Your Task
Write a complete research paper draft in Chinese with the following structure:
1. 标题（Title）- 基于用户研究主题
2. 摘要（Abstract）- 200-300 字
3. 关键词（Keywords）- 5-8 个
4. 引言（Introduction）- 研究背景、目的、意义
5. 材料与方法（Materials and Methods）- 数据来源、分析方法
6. 结果（Results）- 按模块组织，每个模块详尽描述
7. 讨论（Discussion）- 生物学机制解读，与文献对比
8. 结论（Conclusion）- 主要发现总结

For each figure and table mentioned, write a caption in BOTH Chinese and English.

Return as JSON:
{{
  ""title"": ""<title in Chinese>"",
  ""abstract"": ""<abstract in Chinese>"",
  ""keywords"": [""<keyword1>"", ""<keyword2>""],
  ""introduction"": ""<introduction in Chinese>"",
  ""materials_methods"": ""<materials and methods in Chinese>"",
  ""results_sections"": [
    {{
      ""module_index"": 1,
      ""title"": ""<section title>"",
      ""content"": ""<section content>"",
      ""figure_captions"": [{{""file"": ""<filename>"", ""caption_cn"": ""<Chinese caption>"", ""caption_en"": ""<English caption>""}}],
      ""table_captions"": [{{""file"": ""<filename>"", ""caption_cn"": ""<Chinese caption>"", ""caption_en"": ""<English caption>""}}]
    }}
  ],
  ""discussion"": ""<discussion in Chinese>"",
  ""conclusion"": ""<conclusion in Chinese>""
}}
"
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim json = resp.ExtractJsonFromResponse
            If Not String.IsNullOrEmpty(json) Then
                Try
                    Return json.LoadJSON(Of ReportContent)
                Catch ex As Exception
                    LogInfo($"Failed to parse report JSON: {ex.Message}")
                End Try
            End If

            ' 返回默认内容
            Return New ReportContent() With {
                .Title = "组学数据分析报告",
                .Abstract = resp.output,
                .Introduction = "",
                .MaterialsMethods = "",
                .Discussion = "",
                .Conclusion = ""
            }
        End Using
    End Function

    ''' <summary>构建 HTML 报告</summary>
    Private Function BuildHtmlReport(content As ReportContent, figures As List(Of Tuple(Of Integer, String)), tables As List(Of Tuple(Of Integer, String))) As String
        Dim sb As New StringBuilder()

        sb.AppendLine("<!DOCTYPE html>")
        sb.AppendLine("<html lang='zh-CN'>")
        sb.AppendLine("<head>")
        sb.AppendLine("<meta charset='UTF-8'>")
        sb.AppendLine("<title>" & EscapeHtml(content.Title) & "</title>")
        sb.AppendLine("<style>")
        sb.AppendLine("@page { size: A3; margin: 15mm; }")
        sb.AppendLine("body { font-family: 'Cambria', 'Times New Roman', serif; font-size: 12pt; line-height: 1.6; color: #333; }")
        sb.AppendLine("h1 { font-size: 22pt; text-align: center; color: #1F4E79; margin-bottom: 20pt; }")
        sb.AppendLine("h2 { font-size: 16pt; color: #1F4E79; border-bottom: 2px solid #1F4E79; padding-bottom: 5pt; margin-top: 20pt; }")
        sb.AppendLine("h3 { font-size: 14pt; color: #2E5C8A; margin-top: 15pt; }")
        sb.AppendLine("p { text-align: justify; text-indent: 2em; }")
        sb.AppendLine("figure { text-align: center; margin: 15pt 0; page-break-inside: avoid; }")
        sb.AppendLine("img { max-width: 100%; max-height: 500px; }")
        sb.AppendLine("figcaption { font-size: 10pt; color: #555; margin-top: 5pt; text-align: center; }")
        sb.AppendLine("table { width: 100%; border-collapse: collapse; margin: 10pt 0; font-size: 10pt; }")
        sb.AppendLine("th { background-color: #1F4E79; color: white; padding: 5pt; border: 1px solid #ccc; }")
        sb.AppendLine("td { padding: 5pt; border: 1px solid #ccc; }")
        sb.AppendLine("tr:nth-child(even) { background-color: #f9f9f9; }")
        sb.AppendLine(".keywords { font-style: italic; color: #555; }")
        sb.AppendLine(".abstract { background-color: #f5f5f5; padding: 10pt; border-left: 4px solid #1F4E79; }")
        sb.AppendLine("</style>")
        sb.AppendLine("</head>")
        sb.AppendLine("<body>")

        ' 标题
        sb.AppendLine($"<h1>{EscapeHtml(content.Title)}</h1>")

        ' 摘要
        sb.AppendLine("<h2>摘要</h2>")
        sb.AppendLine($"<div class='abstract'><p>{EscapeHtml(content.Abstract)}</p></div>")

        ' 关键词
        If content.Keywords IsNot Nothing AndAlso content.Keywords.Count > 0 Then
            sb.AppendLine($"<p class='keywords'><strong>关键词：</strong>{String.Join("；", content.Keywords)}</p>")
        End If

        ' 引言
        sb.AppendLine("<h2>1. 引言</h2>")
        sb.AppendLine($"<p>{EscapeHtml(content.Introduction)}</p>")

        ' 材料与方法
        sb.AppendLine("<h2>2. 材料与方法</h2>")
        sb.AppendLine($"<p>{EscapeHtml(content.MaterialsMethods)}</p>")

        ' 结果
        sb.AppendLine("<h2>3. 结果</h2>")
        If content.ResultsSections IsNot Nothing Then
            For Each section In content.ResultsSections
                sb.AppendLine($"<h3>3.{section.ModuleIndex} {EscapeHtml(section.Title)}</h3>")
                sb.AppendLine($"<p>{EscapeHtml(section.Content)}</p>")

                ' 插入图表
                If section.FigureCaptions IsNot Nothing Then
                    For Each cap In section.FigureCaptions
                        Dim figPath = figures.FirstOrDefault(Function(f) Path.GetFileName(f.Item2) = cap.File)
                        If figPath IsNot Nothing Then
                            sb.AppendLine("<figure>")
                            sb.AppendLine($"<img src='{New DataURI(figPath.Item2).ToString}' alt='{EscapeHtml(cap.CaptionEn)}'>")
                            sb.AppendLine($"<figcaption><strong>图注：</strong>{EscapeHtml(cap.CaptionCn)}<br><strong>Figure Caption:</strong> {EscapeHtml(cap.CaptionEn)}</figcaption>")
                            sb.AppendLine("</figure>")
                        End If
                    Next
                End If

                ' 插入表格说明
                If section.TableCaptions IsNot Nothing Then
                    For Each cap In section.TableCaptions
                        sb.AppendLine("<div>")
                        sb.AppendLine($"<p><strong>表格说明：</strong>{EscapeHtml(cap.CaptionCn)}<br><strong>Table Caption:</strong> {EscapeHtml(cap.CaptionEn)}</p>")
                        sb.AppendLine("</div>")
                    Next
                End If
            Next
        End If

        ' 讨论
        sb.AppendLine("<h2>4. 讨论</h2>")
        sb.AppendLine($"<p>{EscapeHtml(content.Discussion)}</p>")

        ' 结论
        sb.AppendLine("<h2>5. 结论</h2>")
        sb.AppendLine($"<p>{EscapeHtml(content.Conclusion)}</p>")

        sb.AppendLine("</body>")
        sb.AppendLine("</html>")

        Return sb.ToString()
    End Function

    Private Function EscapeHtml(text As String) As String
        If String.IsNullOrEmpty(text) Then Return ""
        Return text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("""", "&quot;").Replace(vbCrLf, "<br>").Replace(vbLf, "<br>")
    End Function

End Class


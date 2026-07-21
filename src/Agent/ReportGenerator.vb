' ============================================================================
' 研究报告生成器
' ============================================================================
Imports System.Diagnostics
Imports System.IO
Imports System.Text
Imports OmicsAgent.Config
Imports OmicsAgent.Models
Imports OmicsAgent.Utils
Imports OmicsAgent.IO

Namespace Agent

    ''' <summary>
    ''' 生成 HTML 报告并通过 wkhtmltopdf 转换为 PDF
    ''' </summary>
    Public Class ReportGenerator

        Private ReadOnly _config As AppConfig
        Private ReadOnly _workspace As WorkspaceManager
        Private ReadOnly _input As AnalysisInput
        Private ReadOnly _logger As Logger
        Private ReadOnly _llmClientFactory As Func(Of LLMClient)

        Public Sub New(config As AppConfig, workspace As WorkspaceManager, input As AnalysisInput,
                       logger As Logger, llmClientFactory As Func(Of LLMClient))
            _config = config
            _workspace = workspace
            _input = input
            _logger = logger
            _llmClientFactory = llmClientFactory
        End Sub

        Public Async Function GenerateAsync(results As List(Of ModuleResult), kbPath As String) As Task
            ' 1. 收集所有模块的结论
            Dim conclusions = CollectConclusions(results)

            ' 2. 用 LLM 生成论文草稿
            Dim paperDraft = Await GeneratePaperDraftAsync(conclusions, kbPath)

            ' 3. 转换为 HTML
            Dim html = BuildHtml(paperDraft, results)

            ' 4. 保存 HTML
            File.WriteAllText(_workspace.HtmlReportPath, html, Encoding.UTF8)
            _logger.Info($"HTML report saved: {_workspace.HtmlReportPath}")

            ' 5. 转换为 PDF
            Await ConvertToPdfAsync()
        End Function

        Private Function CollectConclusions(results As List(Of ModuleResult)) As String
            Dim sb As New StringBuilder()
            For Each r In results
                sb.AppendLine($"## Module: {r.ModuleName}")
                sb.AppendLine(r.ConclusionText)
                sb.AppendLine()
                If r.Tables.Count > 0 Then
                    sb.AppendLine($"Tables: {String.Join(", ", r.Tables)}")
                End If
                If r.Figures.Count > 0 Then
                    sb.AppendLine($"Figures: {String.Join(", ", r.Figures)}")
                End If
                sb.AppendLine()
                sb.AppendLine("---")
                sb.AppendLine()
            Next
            Return sb.ToString()
        End Function

        Private Async Function GeneratePaperDraftAsync(conclusions As String, kbPath As String) As Task(Of String)
            Dim llm = _llmClientFactory()

            ' 注册工具供 LLM 读取模块结果
            Dim fileTool As New Tools.FileReadTool()
            llm.AddFunction(fileTool, "read_file")

            Dim kbContent = ""
            If File.Exists(kbPath) Then
                Try
                    kbContent = File.ReadAllText(kbPath)
                Catch
                End Try
            End If

            Dim prompt = <string><![CDATA[
You are a senior bioinformatics researcher writing a research paper based on the omics data analysis results.

# Research Topic
<%= topic %>

# Sample Information
<%= samples %>

# Knowledge Base (kb.json)
<%= kb %>

# Module Analysis Results
<%= conclusions %>

Your task: Write a complete research paper draft in CHINESE (中文) following this structure:

## 论文结构

### 1. 摘要 (Abstract)
- 研究背景与目的 (200-300 字)
- 主要方法
- 关键发现
- 结论与意义

### 2. 引言 (Introduction)
- 研究领域背景
- 当前研究空白
- 本研究目的与创新点
- (引用 kb.json 中的参考文献知识)

### 3. 材料与方法 (Materials and Methods)
- 样本来源与实验设计
- 数据预处理方法
- 多元统计分析方法 (PCA/PLSDA/OPLSDA)
- 差异分析 (LIMMA)
- KEGG 富集与 GSVA
- WGCNA 共表达网络
- CMeans 软聚类
- 动态贝叶斯网络 (bnlearn, 若适用)
- PLS-PM 因果路径分析

### 4. 结果 (Results)
- 数据质量控制结果
- 多元统计分析结果
- 差异分子分析结果
- 通路富集分析结果
- 共表达网络分析结果
- 聚类分析结果
- 因果网络分析结果
- (每个结果小节引用对应的 figures/tables)

### 5. 讨论 (Discussion)
- 主要发现的生物学意义
- 与已知文献的比较 (引用 kb.json)
- 研究局限性
- 未来研究方向

### 6. 结论 (Conclusion)
- 核心发现总结
- 研究意义

### 7. 图表说明
- 列出所有 figures/ 下的图片，给出图注（中英文双语）
- 列出所有 tables/ 下的表格，给出表注（中英文双语）

## 写作要求
1. 严格基于分析结果数据，严禁杜撰
2. 生物学机制解释优先使用 kb.json 中的知识
3. 图注和表注使用中英文双语
4. 论文整体使用中文撰写
5. 使用 Markdown 格式
6. 段落不少于 3-5 句话
7. 每个小节内容不少于 200 字

请直接输出论文 Markdown 内容。
]]></string>.Value
            prompt = prompt.Replace("<%= topic %>", _input.Research.RawText) _
                           .Replace("<%= samples %>", DescribeSamples()) _
                           .Replace("<%= kb %>", kbContent) _
                           .Replace("<%= conclusions %>", conclusions)

            _logger.Info("Asking LLM to generate paper draft...")
            Dim resp = Await llm.Chat(prompt)
            Return resp.output
        End Function

        Private Function DescribeSamples() As String
            Dim sb As New StringBuilder()
            For Each d In _input.Datasets
                sb.AppendLine($"- Dataset: {d.Name}")
                sb.AppendLine($"  Type: {d.OmicsType}")
                sb.AppendLine($"  Molecules: {d.MoleculeCount}")
                sb.AppendLine($"  Samples: {d.SampleCount}")
                sb.AppendLine($"  Groups: {String.Join(", ", d.SampleGroups)}")
                sb.AppendLine($"  Time series: {d.HasTimeSeries}")
            Next
            Return sb.ToString()
        End Function

        Private Function BuildHtml(markdownContent As String, results As List(Of ModuleResult)) As String
            ' 简单的 Markdown → HTML 转换（基础版）
            Dim html = MarkdownToHtml(markdownContent)

            ' 收集所有图片
            Dim figuresHtml As New StringBuilder()
            For Each r In results
                If r.Figures.Count = 0 Then Continue For
                Dim figDir = Path.Combine(r.ModuleDir, "figures")
                For Each f In r.Figures
                    Dim fullPath = Path.Combine(figDir, f)
                    If File.Exists(fullPath) Then
                        figuresHtml.AppendLine($"<div class='figure'><img src='file:///{fullPath.Replace("\", "/")}' /><p>{f}</p></div>")
                    End If
                Next
            Next

            Dim css = <string><![CDATA[
body {
    font-family: 'Noto Serif SC', 'SimSun', serif;
    font-size: 11pt;
    line-height: 1.6;
    margin: 2cm;
    color: #222;
}
h1 { font-size: 18pt; color: #1a3a5c; border-bottom: 2px solid #1a3a5c; padding-bottom: 5px; }
h2 { font-size: 15pt; color: #1a3a5c; margin-top: 20px; border-left: 4px solid #1a3a5c; padding-left: 8px; }
h3 { font-size: 13pt; color: #2c5282; margin-top: 15px; }
h4 { font-size: 12pt; color: #4a5568; }
p { text-align: justify; text-indent: 2em; }
.figure { text-align: center; margin: 15px 0; page-break-inside: avoid; }
.figure img { max-width: 90%; border: 1px solid #ddd; }
.figure p { text-indent: 0; font-size: 10pt; color: #555; }
table { border-collapse: collapse; width: 100%; margin: 10px 0; }
th, td { border: 1px solid #999; padding: 5px 8px; text-align: left; }
th { background: #edf2f7; font-weight: bold; }
code { background: #f7fafc; padding: 1px 4px; border-radius: 3px; font-family: 'Consolas', monospace; }
pre { background: #f7fafc; padding: 10px; border-radius: 5px; overflow-x: auto; }
blockquote { border-left: 4px solid #cbd5e0; padding-left: 15px; color: #555; }
]]></string>.Value

            Dim fullHtml = <string><![CDATA[
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8" />
<title>组学数据分析研究报告</title>
<style>
<%= css %>
</style>
</head>
<body>
<%= body %>

<hr/>
<h2>附录：分析图表</h2>
<%= figures %>
</body>
</html>
]]></string>.Value
            fullHtml = fullHtml.Replace("<%= css %>", css) _
                              .Replace("<%= body %>", html) _
                              .Replace("<%= figures %>", figuresHtml.ToString())
            Return fullHtml
        End Function

        ''' <summary>
        ''' 简单的 Markdown → HTML 转换
        ''' </summary>
        Private Function MarkdownToHtml(md As String) As String
            If String.IsNullOrEmpty(md) Then Return "<p>(empty)</p>"
            Dim lines = md.Split({vbCrLf, vbLf}, StringSplitOptions.None)
            Dim sb As New StringBuilder()
            Dim inCode As Boolean = False
            Dim inList As Boolean = False

            For Each line In lines
                Dim trimmed = line.Trim()
                If trimmed.StartsWith("```") Then
                    If inCode Then
                        sb.AppendLine("</pre>")
                        inCode = False
                    Else
                        sb.AppendLine("<pre>")
                        inCode = True
                    End If
                    Continue For
                End If
                If inCode Then
                    sb.AppendLine(System.Web.HttpUtility.HtmlEncode(line))
                    Continue For
                End If

                If trimmed.StartsWith("#### ") Then
                    If inList Then sb.AppendLine("</ul>") : inList = False
                    sb.AppendLine($"<h4>{trimmed.Substring(5)}</h4>")
                ElseIf trimmed.StartsWith("### ") Then
                    If inList Then sb.AppendLine("</ul>") : inList = False
                    sb.AppendLine($"<h3>{trimmed.Substring(4)}</h3>")
                ElseIf trimmed.StartsWith("## ") Then
                    If inList Then sb.AppendLine("</ul>") : inList = False
                    sb.AppendLine($"<h2>{trimmed.Substring(3)}</h2>")
                ElseIf trimmed.StartsWith("# ") Then
                    If inList Then sb.AppendLine("</ul>") : inList = False
                    sb.AppendLine($"<h1>{trimmed.Substring(2)}</h1>")
                ElseIf trimmed.StartsWith("- ") OrElse trimmed.StartsWith("* ") Then
                    If Not inList Then sb.AppendLine("<ul>") : inList = True
                    sb.AppendLine($"<li>{trimmed.Substring(2)}</li>")
                ElseIf trimmed.StartsWith("> ") Then
                    If inList Then sb.AppendLine("</ul>") : inList = False
                    sb.AppendLine($"<blockquote>{trimmed.Substring(2)}</blockquote>")
                ElseIf String.IsNullOrEmpty(trimmed) Then
                    If inList Then sb.AppendLine("</ul>") : inList = False
                    sb.AppendLine("")
                Else
                    If inList Then sb.AppendLine("</ul>") : inList = False
                    sb.AppendLine($"<p>{EscapeInline(trimmed)}</p>")
                End If
            Next
            If inList Then sb.AppendLine("</ul>")
            If inCode Then sb.AppendLine("</pre>")
            Return sb.ToString()
        End Function

        Private Function EscapeInline(text As String) As String
            ' 简单处理粗体和代码
            Dim t = text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
            ' **bold**
            t = System.Text.RegularExpressions.Regex.Replace(t, "\*\*(.+?)\*\*", "<strong>$1</strong>")
            ' *italic*
            t = System.Text.RegularExpressions.Regex.Replace(t, "\*(.+?)\*", "<em>$1</em>")
            ' `code`
            t = System.Text.RegularExpressions.Regex.Replace(t, "`(.+?)`", "<code>$1</code>")
            Return t
        End Function

        Private Async Function ConvertToPdfAsync() As Task
            If Not File.Exists(_config.WkHtmlToPdfPath) Then
                _logger.Warn($"wkhtmltopdf not found at: {_config.WkHtmlToPdfPath}. Skipping PDF conversion.")
                Return
            End If

            Try
                Dim args = $"--enable-local-file-access --page-size A3 --encoding UTF-8 ""{_workspace.HtmlReportPath}"" ""{_workspace.ReportPath}"""
                _logger.Info($"Converting HTML to PDF: {_config.WkHtmlToPdfPath} {args}")

                Dim psi As New ProcessStartInfo With {
                    .FileName = _config.WkHtmlToPdfPath,
                    .Arguments = args,
                    .UseShellExecute = False,
                    .RedirectStandardOutput = True,
                    .RedirectStandardError = True,
                    .CreateNoWindow = True
                }
                Using p As New Process()
                    p.StartInfo = psi
                    p.Start()
                    Dim stdoutTask = p.StandardOutput.ReadToEndAsync()
                    Dim stderrTask = p.StandardError.ReadToEndAsync()
                    Await p.WaitForExitAsync()
                    Dim stdout = Await stdoutTask
                    Dim stderr = Await stderrTask
                    If p.ExitCode <> 0 Then
                        _logger.Warn($"wkhtmltopdf exited with code {p.ExitCode}. stderr: {stderr}")
                    Else
                        _logger.Info($"PDF report generated: {_workspace.ReportPath}")
                    End If
                End Using
            Catch ex As Exception
                _logger.Error($"PDF conversion failed: {ex.Message}")
            End Try
        End Function

    End Class

End Namespace

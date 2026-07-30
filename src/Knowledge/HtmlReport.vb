Imports System.Runtime.CompilerServices
Imports Microsoft.VisualBasic.Data.Framework.IO
Imports Microsoft.VisualBasic.Data.Framework.StorageProvider
Imports Microsoft.VisualBasic.Linq
Imports Microsoft.VisualBasic.MIME.text.markdown
Imports Microsoft.VisualBasic.Net.Http
Imports OmicsAgent.ReportData

Module HtmlReport

    Friend Class ReportResource

        Public figures As ResourceFile()
        Public tables As ResourceFile()

    End Class

    Friend Class ResourceFile

        Public module_index As Integer
        Public filename As String

        Sub New(index As Integer, file As String)
            module_index = index
            filename = file
        End Sub

        Public Overrides Function ToString() As String
            Return $"[{module_index}] {filename}"
        End Function

    End Class

    ''' <summary>
    ''' 图/表自动编号计数器。以引用类型在章节间共享，
    ''' BuildFigure/BuildTable 调用时自增，实现全文档连续编号。
    ''' </summary>
    Friend Class ReportCounters
        Public figureNo As Integer = 0
        Public tableNo As Integer = 0
    End Class

    ''' <summary>构建 HTML 报告（编排函数，仅负责按顺序拼接各语义块）</summary>
    <Extension>
    Friend Function BuildHtmlReport(content As ReportContent, res As ReportResource, loginfo As Action(Of String)) As String
        Dim sb As New StringBuilder()
        Dim counters As New ReportCounters()

        sb.Append(BuildDocumentHead(content.title))
        sb.Append(BuildCoverPage(content))
        sb.Append(BuildTableOfContents(content))
        sb.Append(BuildAbstractSection(content))

        ' 标准章节：引言 / 材料与方法 / 讨论 / 结论
        sb.Append(BuildStandardSection("1", "sec-intro", "引言", content.introduction))
        sb.Append(BuildStandardSection("2", "sec-methods", "材料与方法", content.materials_methods))
        sb.AppendLine("<div style='page-break-after: always;'></div>")
        sb.Append(BuildResultsSection(content, res, counters, loginfo))
        sb.AppendLine("<div style='page-break-after: always;'></div>")
        sb.Append(BuildStandardSection("4", "sec-discussion", "讨论", content.discussion))
        sb.Append(BuildStandardSection("5", "sec-conclusion", "结论", content.conclusion))

        sb.AppendLine("</body>")
        sb.AppendLine("</html>")

        Return sb.ToString()
    End Function

    ' ------------------------------------------------------------------
    ' 子构建函数：每个函数负责一个语义块，返回 HTML 片段
    ' ------------------------------------------------------------------

    ''' <summary>文档头：doctype / head / meta / title / 内联样式 / body 起始</summary>
    Private Function BuildDocumentHead(title As String) As String
        Dim sb As New StringBuilder()
        Dim css As String = $"{App.HOME}/../docs/report.css".ReadAllText
        sb.AppendLine("<!DOCTYPE html>")
        sb.AppendLine("<html lang='zh-CN'>")
        sb.AppendLine("<head>")
        sb.AppendLine("<meta charset='UTF-8'>")
        sb.AppendLine("<meta name='viewport' content='width=device-width, initial-scale=1.0'>")
        sb.AppendLine("<title>" & EscapeText(title) & "</title>")
        sb.AppendLine("<style>")
        sb.AppendLine(css)
        sb.AppendLine("</style>")
        sb.AppendLine("</head>")
        sb.AppendLine("<body>")
        Return sb.ToString()
    End Function

    ''' <summary>封面页：标题、分隔线、生成日期、关键词</summary>
    Private Function BuildCoverPage(content As ReportContent) As String
        Dim sb As New StringBuilder()
        sb.AppendLine("<br />")
        sb.AppendLine("<br />")
        sb.AppendLine("<br />")
        sb.AppendLine("<br />")
        sb.AppendLine("<br />")
        sb.AppendLine("<br />")
        sb.AppendLine("<br />")
        sb.AppendLine("<br />")
        sb.AppendLine("<div class='cover'>")
        sb.AppendLine($"<h1 class='cover-title'>{EscapeText(content.title)}</h1>")
        sb.AppendLine("<div class='cover-rule'></div>")
        sb.AppendLine($"<p class='cover-date'>{DateTime.Now.ToString("yyyy 年 MM 月 dd 日")}</p>")
        If content.keywords IsNot Nothing AndAlso content.keywords.Count > 0 Then
            sb.AppendLine($"<p class='cover-keywords'><strong>关键词：</strong>{String.Join("；", content.keywords)}</p>")
        End If
        sb.AppendLine("</div>")
        Return sb.ToString()
    End Function

    ''' <summary>目录页：编号章节列表 + 结果子章节，锚点跳转</summary>
    Private Function BuildTableOfContents(content As ReportContent) As String
        Dim sb As New StringBuilder()
        sb.AppendLine("<div class='toc'>")
        sb.AppendLine("<h2 class='toc-title'>目录</h2>")
        sb.AppendLine("<ul class='toc-list'>")
        sb.AppendLine("<li><a href='#sec-intro'>1. 引言</a></li>")
        sb.AppendLine("<li><a href='#sec-methods'>2. 材料与方法</a></li>")
        sb.AppendLine("<li><a href='#sec-results'>3. 结果</a></li>")

        If content.results_sections IsNot Nothing Then
            Dim i As Integer = 1
            For Each section In content.results_sections
                sb.AppendLine($"<li class='toc-sub'><a href='#sec-result-{i}'>3.{i} {EscapeText(section.title)}</a></li>")
                i += 1
            Next
        End If

        sb.AppendLine("<li><a href='#sec-discussion'>4. 讨论</a></li>")
        sb.AppendLine("<li><a href='#sec-conclusion'>5. 结论</a></li>")
        sb.AppendLine("</ul>")
        sb.AppendLine("</div>")
        Return sb.ToString()
    End Function

    ''' <summary>摘要 + 关键词</summary>
    Private Function BuildAbstractSection(content As ReportContent) As String
        Dim sb As New StringBuilder()
        sb.AppendLine("<section class='abstract-section'>")
        sb.AppendLine("<h2>摘要</h2>")
        sb.AppendLine($"<div class='abstract'>{EscapeHtml(content.abstract)}</div>")
        If content.keywords IsNot Nothing AndAlso content.keywords.Count > 0 Then
            sb.AppendLine($"<p class='keywords'><strong>关键词：</strong>{String.Join("；", content.keywords)}</p>")
        End If
        sb.AppendLine("</section>")
        Return sb.ToString()
    End Function

    ''' <summary>通用标准章节（引言/材料与方法/讨论/结论）</summary>
    Private Function BuildStandardSection(sectionNumber As String, anchorId As String, heading As String, body As String) As String
        Dim sb As New StringBuilder()
        sb.AppendLine($"<section id='{anchorId}' class='section'>")
        sb.AppendLine($"<h2>{sectionNumber}. {EscapeText(heading)}</h2>")
        sb.AppendLine(EscapeHtml(body))
        sb.AppendLine("</section>")
        Return sb.ToString()
    End Function

    ''' <summary>结果章节：3. 标题 + 各子章节（3.1…3.n），子章节内按声明顺序渲染图与表</summary>
    Private Function BuildResultsSection(content As ReportContent, res As ReportResource, counters As ReportCounters, loginfo As Action(Of String)) As String
        Dim sb As New StringBuilder()
        sb.AppendLine("<section id='sec-results' class='section'>")
        sb.AppendLine("<h2>3. 结果</h2>")

        If content.results_sections IsNot Nothing Then
            Dim subNo As Integer = 1
            For Each section In content.results_sections
                sb.AppendLine($"<section id='sec-result-{subNo}' class='result-subsection'>")
                sb.AppendLine($"<h3>3.{subNo} {EscapeText(section.title)}</h3>")
                sb.AppendLine(EscapeHtml(section.content))

                ' 先渲染图（在 res.figures 中按文件名精确匹配），再渲染表（在 res.tables 中匹配）
                ' 各自按 JSON 声明顺序，避免原逻辑按文件名排序导致的图文错位
                If section.figures IsNot Nothing Then
                    For Each fig In section.figures
                        Dim figPath = res.figures.FirstOrDefault(Function(f) Path.GetFileName(f.filename).TextEquals(fig.file))
                        If figPath Is Nothing AndAlso fig.file.FileExists Then
                            figPath = New ResourceFile(0, fig.file)
                        End If
                        If figPath IsNot Nothing Then
                            sb.Append(BuildFigure(fig, figPath, counters))
                        End If
                    Next
                End If

                If section.tables IsNot Nothing Then
                    For Each tbl In section.tables
                        Dim tblPath = res.tables.FirstOrDefault(Function(t) Path.GetFileName(t.filename).TextEquals(tbl.file))
                        If tblPath Is Nothing AndAlso tbl.file.FileExists Then
                            tblPath = New ResourceFile(0, tbl.file)
                        End If
                        If tblPath IsNot Nothing Then
                            sb.Append(BuildTable(tbl, tblPath, counters, loginfo))
                        End If
                    Next
                End If

                sb.AppendLine("</section>")
                subNo += 1
            Next
        End If

        sb.AppendLine("</section>")
        Return sb.ToString()
    End Function

    ''' <summary>单张图：自增图号，输出 figure + 中英文图注</summary>
    Private Function BuildFigure(dataRep As TableFigureCaption, figPath As ResourceFile, counters As ReportCounters) As String
        counters.figureNo += 1
        Dim no As Integer = counters.figureNo
        Dim sb As New StringBuilder()
        sb.AppendLine("<figure>")
        sb.AppendLine($"<img src='{New DataURI(figPath.filename).ToString}' alt='{EscapeText(dataRep.caption_en)}' onerror=""this.style.display='none'"">")
        sb.AppendLine($"<figcaption><strong>图 {no}：</strong>{EscapeHtml(dataRep.caption_cn)}<br><strong>Figure {no}:</strong> {EscapeHtml(dataRep.caption_en)}</figcaption>")
        sb.AppendLine("</figure>")
        Return sb.ToString()
    End Function

    ''' <summary>单个表：自增表号，读取 CSV 前 9 行按指定列构建 HTML 表格</summary>
    Private Function BuildTable(dataRep As TableFigureCaption, tblPath As ResourceFile, counters As ReportCounters, loginfo As Action(Of String)) As String
        counters.tableNo += 1
        Dim no As Integer = counters.tableNo
        Dim sb As New StringBuilder()

        sb.AppendLine("<div class='table-block'>")
        sb.AppendLine($"<p class='table-caption'><strong>表 {no}：</strong>{EscapeHtml(dataRep.caption_cn)}<br><strong>Table {no}:</strong> {EscapeHtml(dataRep.caption_en)}</p>")

        Try
            Dim csvDf As DataFrameResolver = DataFrameResolver.Load(tblPath.filename)

            ' 确定需要显示的列名及其在 CSV 中的列索引
            ' fields 为空/Nothing 时显示全部列；非空时仅保留 CSV 中实际存在的字段
            Dim displayColumns As New List(Of String)()
            Dim columnOrdinals As New List(Of Integer)()

            If dataRep.fields.IsNullOrEmpty() Then
                For Each header As String In csvDf.HeadTitles
                    displayColumns.Add(header)
                    columnOrdinals.Add(csvDf.GetOrdinal(header))
                Next
            Else
                For Each fieldName As String In dataRep.fields
                    Dim ordinal As Integer = csvDf.GetOrdinal(fieldName)
                    If ordinal >= 0 Then
                        displayColumns.Add(fieldName)
                        columnOrdinals.Add(ordinal)
                    End If
                Next
            End If

            ' 仅当存在有效列时才生成表格
            If displayColumns.Count > 0 Then
                sb.AppendLine("<table>")
                sb.AppendLine("<thead>")
                sb.AppendLine("<tr>")
                For Each colName As String In displayColumns
                    sb.AppendLine($"<th>{EscapeHtml(colName)}</th>")
                Next
                sb.AppendLine("</tr>")
                sb.AppendLine("</thead>")
                sb.AppendLine("<tbody>")

                ' 提取前 9 行数据行（不含表头）
                For Each row As RowObject In csvDf.Rows.Take(9)
                    sb.AppendLine("<tr>")
                    For Each ordinal As Integer In columnOrdinals
                        sb.AppendLine($"<td>{EscapeHtml(row(ordinal))}</td>")
                    Next
                    sb.AppendLine("</tr>")
                Next

                sb.AppendLine("</tbody>")
                sb.AppendLine("</table>")
            End If
        Catch ex As Exception
            loginfo($"Failed to load csv table for report: {tblPath.filename} -> {ex.Message}")
            sb.AppendLine($"<p><em>(表格数据加载失败: {EscapeText(Path.GetFileName(tblPath.filename))})</em></p>")
        End Try

        sb.AppendLine("</div>")
        Return sb.ToString()
    End Function

    ' ------------------------------------------------------------------
    ' 工具函数
    ' ------------------------------------------------------------------

    ''' <summary>
    ''' 将 markdown 文本转换为 HTML（由 MarkdownRender 负责块级/内联排版）。
    ''' 注意：不再对换行做 blanket 的 &lt;br&gt; 替换，避免块级元素间产生多余空行。
    ''' </summary>
    Private Function EscapeHtml(text As String) As String
        If String.IsNullOrEmpty(text) Then
            Return ""
        Else
            Static markdown As New MarkdownRender
            Return markdown.Transform(text)
        End If
    End Function

    ''' <summary>对纯文本（标题、图注文字等）做 HTML 特殊字符转义，防止标签注入</summary>
    Private Function EscapeText(text As String) As String
        If String.IsNullOrEmpty(text) Then
            Return ""
        End If
        Return text _
            .Replace("&", "&amp;") _
            .Replace("<", "&lt;") _
            .Replace(">", "&gt;") _
            .Replace("""", "&quot;")
    End Function

End Module

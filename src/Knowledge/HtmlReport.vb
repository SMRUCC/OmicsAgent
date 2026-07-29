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

    ''' <summary>构建 HTML 报告</summary>
    ''' 
    <Extension>
    Friend Function BuildHtmlReport(content As ReportContent, res As ReportResource, loginfo As Action(Of String)) As String
        Dim sb As New StringBuilder()
        Dim figures = res.figures
        Dim tables = res.tables

        sb.AppendLine("<!DOCTYPE html>")
        sb.AppendLine("<html lang='zh-CN'>")
        sb.AppendLine("<head>")
        sb.AppendLine("<meta charset='UTF-8'>")
        sb.AppendLine("<title>" & content.title & "</title>")
        sb.AppendLine("<style>")
        sb.AppendLine($"{App.HOME}/../docs/report.css".ReadAllText)
        sb.AppendLine("</style>")
        sb.AppendLine("</head>")
        sb.AppendLine("<body>")

        ' 标题
        sb.AppendLine($"<h1>{content.title}</h1>")

        ' 摘要
        sb.AppendLine("<h2>摘要</h2>")
        sb.AppendLine($"<div class='abstract'>{EscapeHtml(content.abstract)}</div>")

        ' 关键词
        If content.keywords IsNot Nothing AndAlso content.keywords.Count > 0 Then
            sb.AppendLine($"<p class='keywords'><strong>关键词：</strong>{String.Join("；", content.keywords)}</p>")
        End If

        ' 引言
        sb.AppendLine("<h2>1. 引言</h2>")
        sb.AppendLine($"{EscapeHtml(content.introduction)}")

        ' 材料与方法
        sb.AppendLine("<h2>2. 材料与方法</h2>")
        sb.AppendLine($"{EscapeHtml(content.materials_methods)}")

        ' 结果
        sb.AppendLine("<h2>3. 结果</h2>")
        If content.results_sections IsNot Nothing Then
            For Each section In content.results_sections
                sb.AppendLine($"<h3>3.{section.module_index} {EscapeHtml(section.title)}</h3>")
                sb.AppendLine($"{EscapeHtml(section.content)}")

                ' 插入图表
                ' 插入表格说明
                For Each data_rep As TableFigureCaption In section.figures _
                    .JoinIterates(section.tables) _
                    .OrderBy(Function(a)
                                 Return a.file.BaseName
                             End Function)

                    Dim figPath = figures.FirstOrDefault(Function(f) Path.GetFileName(f.filename).TextEquals(data_rep.file))

                    If figPath Is Nothing AndAlso data_rep.file.FileExists Then
                        figPath = New ResourceFile(0, data_rep.file)
                    End If

                    If data_rep.type = "figure" OrElse Not data_rep.file.ExtensionSuffix("csv") Then
                        If figPath IsNot Nothing Then
                            sb.AppendLine("<figure>")
                            sb.AppendLine($"<img src='{New DataURI(figPath.filename).ToString}' alt='{EscapeHtml(data_rep.caption_en)}'>")
                            sb.AppendLine($"<figcaption><strong>图注：</strong>{EscapeHtml(data_rep.caption_cn)}<br><strong>Figure Caption:</strong> {EscapeHtml(data_rep.caption_en)}</figcaption>")
                            sb.AppendLine("</figure>")
                        End If
                    ElseIf figPath IsNot Nothing Then
                        ' 读取 CSV 表格文件，提取前 9 行数据，按 fields 指定的列构建 HTML 表格
                        sb.AppendLine("<div>")
                        sb.AppendLine($"<strong>表格说明：</strong>{EscapeHtml(data_rep.caption_cn)}<br><strong>Table Caption:</strong> {EscapeHtml(data_rep.caption_en)}")

                        Try
                            Dim csvDf As DataFrameResolver = DataFrameResolver.Load(figPath.filename)

                            ' 确定需要显示的列名及其在 CSV 中的列索引
                            ' fields 为空/Nothing 时显示全部列；非空时仅保留 CSV 中实际存在的字段
                            Dim displayColumns As New List(Of String)()
                            Dim columnOrdinals As New List(Of Integer)()

                            If data_rep.fields.IsNullOrEmpty() Then
                                ' 显示全部列
                                For Each header As String In csvDf.HeadTitles
                                    displayColumns.Add(header)
                                    columnOrdinals.Add(csvDf.GetOrdinal(header))
                                Next
                            Else
                                ' 仅显示 fields 中指定的、且在 CSV 中存在的列
                                For Each fieldName As String In data_rep.fields
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
                            loginfo($"Failed to load csv table for report: {figPath.filename} -> {ex.Message}")
                            sb.AppendLine($"<p><em>(表格数据加载失败: {EscapeHtml(Path.GetFileName(figPath.filename))})</em></p>")
                        End Try

                        sb.AppendLine("</div>")
                    End If
                Next
            Next
        End If

        ' 讨论
        sb.AppendLine("<h2>4. 讨论</h2>")
        sb.AppendLine($"{EscapeHtml(content.discussion)}")

        ' 结论
        sb.AppendLine("<h2>5. 结论</h2>")
        sb.AppendLine($"{EscapeHtml(content.conclusion)}")

        sb.AppendLine("</body>")
        sb.AppendLine("</html>")

        Return sb.ToString()
    End Function

    Private Function EscapeHtml(text As String) As String
        If String.IsNullOrEmpty(text) Then
            Return ""
        Else
            Static markdown As New MarkdownRender
            text = markdown.Transform(text)
        End If

        Return text _
            .Replace(vbCrLf, "<br>") _
            .Replace(vbLf, "<br>")
    End Function
End Module

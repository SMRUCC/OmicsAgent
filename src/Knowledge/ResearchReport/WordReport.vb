Imports System.Globalization
Imports System.Runtime.CompilerServices
Imports Microsoft.VisualBasic.Linq
Imports Microsoft.VisualBasic.MIME.Office.WordDocument
Imports OmicsAgent.ReportData

''' <summary>
''' Word（docx）报告构建器。
''' 
''' 与 <see cref="HtmlReport.BuildHtmlReport"/> 共享同一份
''' <see cref="ReportContent"/> 结构化内容块数据源，章节编排顺序与图表编号
''' 逻辑严格对齐，保证两种输出格式的内容完全一致。
''' </summary>
Module WordReport

    ''' <summary>单张插图在文档中的显示宽度（磅）</summary>
    Const FigureWidth As Double = 450

    ''' <summary>
    ''' 由报告内容对象生成 Word docx 文件。
    ''' </summary>
    ''' <param name="content">报告内容（正文为结构化内容块数组）</param>
    ''' <param name="res">图片与数据表资源池</param>
    ''' <param name="outFile">输出的 docx 文件路径</param>
    ''' <param name="loginfo">日志回调</param>
    ''' <returns>生成成功返回 True</returns>
    <Extension>
    Friend Function BuildWordReport(content As ReportContent,
                                    res As ReportResource,
                                    outFile As String,
                                    loginfo As Action(Of String)) As Boolean

        Dim doc As New WordDocument(
            author:="OmicsAgent",
            title:=content.title,
            tags:=If(content.keywords, New String() {}),
            subject:=content.title,
            description:=content.abstract
        )

        Call doc.ApplyReportStyles()

        ' ---- 封面 ----
        Call doc.DocTitle(content.title)
        Call doc.Paragraph($"{Date.Now.ToString("yyyy 年 MM 月 dd 日")}", New WordStyle With {.Alignment = "center"})

        If Not content.keywords.IsNullOrEmpty Then
            Call doc.Paragraph($"关键词：{String.Join("；", content.keywords)}")
        End If

        Call doc.PageBreak()

        ' ---- 目录（Word 原生 TOC 域，打开文档后需手动刷新域以显示页码）----
        Call doc.Toc(maxLevel:=3)
        Call doc.PageBreak()

        ' ---- 摘要 ----
        Call doc.H1("摘要")
        Call doc.Paragraph(If(content.abstract, ""))

        ' ---- 1. 引言 / 2. 材料与方法 ----
        Call doc.H1("1. 引言")
        Call doc.WriteBlocks(content.introduction.SafeQuery)

        Call doc.H1("2. 材料与方法")
        Call doc.WriteBlocks(content.materials_methods.SafeQuery)

        Call doc.PageBreak()

        ' ---- 3. 结果 ----
        Call doc.WriteResultsSections(content, res, loginfo)

        Call doc.PageBreak()

        ' ---- 4. 讨论 / 5. 结论 ----
        Call doc.H1("4. 讨论")
        Call doc.WriteBlocks(content.discussion.SafeQuery)

        Call doc.H1("5. 结论")
        Call doc.WriteBlocks(content.conclusion.SafeQuery)

        Call doc.Save(outFile)
        Call loginfo($"Word report has been saved: {outFile}")

        Return True
    End Function

    ''' <summary>
    ''' 结果章节：3. 标题 + 各子章节（3.1…3.n）。
    ''' 每个子章节先写正文内容块，再按声明顺序插图、插表，与 HTML 路径顺序一致。
    ''' </summary>
    <Extension>
    Private Sub WriteResultsSections(doc As WordDocument, content As ReportContent, res As ReportResource, loginfo As Action(Of String))
        Dim counters As New ReportCounters()

        Call doc.H1("3. 结果")

        If content.results_sections Is Nothing Then
            Return
        End If

        Dim subNo As Integer = 1

        For Each section As ResultSection In content.results_sections
            Call doc.H2($"3.{subNo} {section.title}")
            Call doc.WriteBlocks(section.content.SafeQuery)

            For Each fig As TableFigureCaption In section.figures.SafeQuery
                Call doc.WriteFigure(fig, ResolveResource(fig, res.figures), counters, loginfo)
            Next

            For Each tbl As TableFigureCaption In section.tables.SafeQuery
                Call doc.WriteTable(tbl, ResolveResource(tbl, res.tables), counters, loginfo)
            Next

            subNo += 1
        Next
    End Sub

    ''' <summary>单张图：自增图号，插入图片并附中英文双语图注</summary>
    <Extension>
    Private Sub WriteFigure(doc As WordDocument,
                            dataRep As TableFigureCaption,
                            figPath As ResourceFile,
                            counters As ReportCounters,
                            loginfo As Action(Of String))

        If figPath Is Nothing OrElse Not figPath.filename.FileExists Then
            Call loginfo($"Skip the missing figure file for word report: {dataRep.file}")
            Return
        End If

        counters.figureNo += 1

        Dim no As Integer = counters.figureNo
        Dim caption As String = $"图 {no}：{dataRep.caption_cn}"

        If Not dataRep.caption_en.StringEmpty(, True) Then
            caption &= $"{vbCrLf}Figure {no}: {dataRep.caption_en}"
        End If

        Call doc.Image(figPath.filename, width:=FigureWidth, caption:=caption)
    End Sub

    ''' <summary>单个表：自增表号，先写双语表注，再渲染 CSV 前若干行数据</summary>
    <Extension>
    Private Sub WriteTable(doc As WordDocument,
                           dataRep As TableFigureCaption,
                           tblPath As ResourceFile,
                           counters As ReportCounters,
                           loginfo As Action(Of String))

        If tblPath Is Nothing Then
            Call loginfo($"Skip the missing table file for word report: {dataRep.file}")
            Return
        End If

        counters.tableNo += 1

        Dim no As Integer = counters.tableNo

        Call doc.Paragraph($"表 {no}：{dataRep.caption_cn}")

        If Not dataRep.caption_en.StringEmpty(, True) Then
            Call doc.Paragraph($"Table {no}: {dataRep.caption_en}")
        End If

        Dim preview = LoadTablePreview(tblPath.filename, dataRep.fields, loginfo:=loginfo)

        If preview.headers.IsNullOrEmpty Then
            Call doc.Paragraph($"(表格数据加载失败: {Path.GetFileName(tblPath.filename)})")
        Else
            ' 对数据单元格按数值格式化规则处理（表头保持不变）
            Dim formattedRows(preview.rows.Length - 1)() As String
            For r As Integer = 0 To preview.rows.Length - 1
                Dim src = preview.rows(r)
                Dim dst(src.Length - 1) As String
                For c As Integer = 0 To src.Length - 1
                    dst(c) = FormatCellValue(src(c))
                Next
                formattedRows(r) = dst
            Next

            Call doc.TableAutoFitWindow(preview.headers, formattedRows, center:=True, threeLine:=True)
        End If
    End Sub

    ''' <summary>
    ''' 数值单元格格式化：仅当文本可解析为实数时生效，其他（表头、单位、类别名等）原样返回。
    ''' 规则：
    '''   - 绝对值大于 10000 或小于 0.001 的实数，按保留三位小数的科学计数法显示（如 1.234E+04）。
    '''   - 其余实数按四舍五入保留两位小数显示（如 12.34）。
    ''' </summary>
    Private Function FormatCellValue(raw As String) As String
        If raw.StringEmpty(, True) Then
            Return ""
        End If

        Dim x As Double
        If Double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, x) Then
            If x <> 0 AndAlso (Math.Abs(x) > 10000 OrElse Math.Abs(x) < 0.001) Then
                Return x.ToString("0.000E+00", CultureInfo.InvariantCulture)
            Else
                Return Math.Round(x, 2).ToString("F2", CultureInfo.InvariantCulture)
            End If
        End If

        Return raw
    End Function

    ''' <summary>集中配置报告文档的页面与各级样式</summary>
    <Extension>
    Private Function ApplyReportStyles(doc As WordDocument) As WordDocument
        Return doc _
            .PageSetupA4() _
            .HeadingStyle(1, New WordStyle With {
                .FontName = "Microsoft YaHei",
                .FontNameEastAsia = "Microsoft YaHei",
                .Size = 22,
                .Bold = True,
                .ForeColor = WordColors.DarkBlue,
                .SpaceBefore = 12,
                .SpaceAfter = 8
            }) _
            .HeadingStyle(2, New WordStyle With {
                .FontName = "Microsoft YaHei",
                .FontNameEastAsia = "Microsoft YaHei",
                .Size = 18,
                .Bold = True,
                .ForeColor = WordColors.Heading2Color,
                .SpaceBefore = 10,
                .SpaceAfter = 6
            }) _
            .HeadingStyle(3, New WordStyle With {
                .FontName = "Microsoft YaHei",
                .FontNameEastAsia = "Microsoft YaHei",
                .Size = 15,
                .Bold = True,
                .ForeColor = WordColors.Heading3Color,
                .SpaceBefore = 8,
                .SpaceAfter = 4
            }) _
            .ParagraphStyle(New WordStyle With {
                .FontName = "Calibri",
                .FontNameEastAsia = "Microsoft YaHei",
                .Size = 12,
                .LineSpacing = 1.5,
                .SpaceAfter = 8,
                .FirstLineIndent = 24
            }) _
            .TableStyle(New TableStyle With {
                .HeaderBackColor = "4472C4",
                .HeaderForeColor = "FFFFFF",
                .HeaderBold = True,
                .BorderColor = "8EAADB",
                .BorderSize = 4,
                .AltRowBackColor = "D6E4F0"
            })
    End Function

End Module

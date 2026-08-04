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
        Try
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
            Call doc.Paragraph($"{Date.Now.ToString("yyyy 年 MM 月 dd 日")}")

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
        Catch ex As Exception
            Call loginfo($"Failed to generate the word document report: {ex.ToString}")
            Return False
        End Try
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

            Call doc.WriteAutoFitTable(preview.headers, formattedRows)
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

    ''' <summary>
    ''' 写入窗口自适应（auto fit to window）的表格。
    ''' 复用 <see cref="ApplyReportStyles"/> 中配置的表格视觉样式（深蓝表头、隔行底纹、边框），
    ''' 仅将列宽策略改为自动：<c>w:tblW w:type="auto"</c> + <c>w:tblLayout w:type="autofit"</c>，
    ''' 单元格宽度 <c>w:tcW w:w="0" w:type="auto"</c>，由 Word 渲染时按页面窗口折列宽。
    ''' </summary>
    <Extension>
    Private Function WriteAutoFitTable(doc As WordDocument,
                                       headers As String(),
                                       rows As String()(),
                                       Optional alignments As String() = Nothing) As WordDocument
        Dim nCols As Integer = If(headers?.Length, 0)
        If nCols = 0 AndAlso rows?.Length > 0 Then
            nCols = If(rows(0)?.Length, 0)
        End If
        If nCols = 0 Then
            Return doc
        End If

        ' 与 ApplyReportStyles 中配置的 TableStyle 保持一致
        Dim headerBack As String = "4472C4"
        Dim headerFore As String = "FFFFFF"
        Dim headerBold As Boolean = True
        Dim borderColor As String = "8EAADB"
        Dim borderSize As Integer = 4
        Dim altRowBack As String = "D6E4F0"

        Dim sb As New StringBuilder()

        ' 表格属性：自动宽度 + 自动布局 + 边框
        sb.Append("<w:tbl><w:tblPr>")
        sb.Append("<w:tblW w:type=""auto""/>")
        sb.Append("<w:tblLayout w:type=""autofit""/>")
        sb.Append("<w:tblBorders>")
        sb.Append($"<w:top w:val=""single"" w:sz=""{borderSize}"" w:color=""{borderColor}""/>")
        sb.Append($"<w:left w:val=""single"" w:sz=""{borderSize}"" w:color=""{borderColor}""/>")
        sb.Append($"<w:bottom w:val=""single"" w:sz=""{borderSize}"" w:color=""{borderColor}""/>")
        sb.Append($"<w:right w:val=""single"" w:sz=""{borderSize}"" w:color=""{borderColor}""/>")
        sb.Append($"<w:insideH w:val=""single"" w:sz=""{borderSize}"" w:color=""{borderColor}""/>")
        sb.Append($"<w:insideV w:val=""single"" w:sz=""{borderSize}"" w:color=""{borderColor}""/>")
        sb.Append("</w:tblBorders>")
        sb.Append("</w:tblPr>")

        ' 列定义（自动宽度）
        sb.Append("<w:tblGrid>")
        For c As Integer = 0 To nCols - 1
            sb.Append("<w:gridCol w:w=""0""/>")
        Next
        sb.Append("</w:tblGrid>")

        ' 表头行
        If headers IsNot Nothing AndAlso headers.Length > 0 Then
            sb.Append("<w:tr><w:trPr><w:tblHeader/></w:trPr>")
            For c As Integer = 0 To nCols - 1
                sb.Append("<w:tc><w:tcPr>")
                sb.Append("<w:tcW w:w=""0"" w:type=""auto""/>")
                sb.Append($"<w:shd w:val=""clear"" w:color=""auto"" w:fill=""{headerBack}""/>")
                sb.Append("<w:vAlign w:val=""center""/></w:tcPr>")
                sb.Append("<w:p><w:pPr>")
                Dim align As String = GetCellAlign(alignments, c)
                If align <> "left" Then sb.Append($"<w:jc w:val=""{align}""/>")
                sb.Append("</w:pPr><w:r><w:rPr>")
                sb.Append("<w:rFonts w:ascii=""Calibri"" w:eastAsia=""Microsoft YaHei"" w:hAnsi=""Calibri""/>")
                If headerBold Then sb.Append("<w:b/>")
                sb.Append($"<w:color w:val=""{headerFore}""/>")
                sb.Append("<w:sz w:val=""24""/></w:rPr>")
                sb.Append($"<w:t xml:space=""preserve"">{XmlEscape(If(c < headers.Length, headers(c), ""))}</w:t></w:r></w:p></w:tc>")
            Next
            sb.Append("</w:tr>")
        End If

        ' 数据行
        For rIdx As Integer = 0 To rows.Length - 1
            Dim row As String() = rows(rIdx)
            sb.Append("<w:tr>")
            Dim rowBg As String = If(rIdx Mod 2 = 1 AndAlso altRowBack <> "", altRowBack, "")
            For c As Integer = 0 To nCols - 1
                sb.Append("<w:tc><w:tcPr>")
                sb.Append("<w:tcW w:w=""0"" w:type=""auto""/>")
                If rowBg <> "" Then sb.Append($"<w:shd w:val=""clear"" w:color=""auto"" w:fill=""{rowBg}""/>")
                sb.Append("<w:vAlign w:val=""center""/></w:tcPr>")
                sb.Append("<w:p><w:pPr>")
                Dim align As String = GetCellAlign(alignments, c)
                If align <> "left" Then sb.Append($"<w:jc w:val=""{align}""/>")
                sb.Append("</w:pPr><w:r><w:rPr>")
                sb.Append("<w:rFonts w:ascii=""Calibri"" w:eastAsia=""Microsoft YaHei"" w:hAnsi=""Calibri""/>")
                sb.Append("<w:sz w:val=""24""/></w:rPr>")
                sb.Append($"<w:t xml:space=""preserve"">{XmlEscape(If(c < If(row?.Length, 0), row(c), ""))}</w:t></w:r></w:p></w:tc>")
            Next
            sb.Append("</w:tr>")
        Next

        sb.Append("</w:tbl>")
        ' 表格后需要一个空段落
        sb.Append("<w:p/>")

        ' 通过反射无关方式追加到文档体：WordDocument 提供 Table 等方法，
        ' 此处直接复用其 StringBuilder 不可访问，故改用公开 API 拼接——
        ' 由于库未暴露追加原始 OOXML 的接口，采用 AppendRaw 扩展（见下）。
        Call doc.AppendRaw(sb.ToString())

        Return doc
    End Function

    ''' <summary>XML 文本转义，避免单元格内容破坏 OOXML 结构。</summary>
    Private Function XmlEscape(text As String) As String
        If text Is Nothing Then
            Return ""
        End If
        Return text _
            .Replace("&", "&amp;") _
            .Replace("<", "&lt;") _
            .Replace(">", "&gt;") _
            .Replace("""", "&quot;") _
            .Replace("'", "&apos;")
    End Function

    ''' <summary>根据对齐方式数组取第 c 列的对齐（默认 left）。</summary>
    Private Function GetCellAlign(alignments As String(), c As Integer) As String
        If alignments IsNot Nothing AndAlso c < alignments.Length AndAlso Not alignments(c).StringEmpty(, True) Then
            Return alignments(c)
        End If
        Return "left"
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

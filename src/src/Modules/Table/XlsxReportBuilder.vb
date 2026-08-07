Imports System.Globalization
Imports Microsoft.VisualBasic.Data.Framework.StorageProvider
Imports Microsoft.VisualBasic.MIME.Office.Excel
Imports Microsoft.VisualBasic.MIME.Office.Excel.XLSX.Writer

''' <summary>
''' 共享的 xlsx 报表构建工具。
'''
''' 依据 LLM 生成的表格注释信息（<see cref="SheetAnnotations"/>），在 VB.NET 端直接读取
''' CSV 文件并调用 <see cref="ReportHelper.WriteReportSheet"/> 写出带样式的 xlsx 工作簿，
''' 取代原先"由 LLM 编写 R 脚本再执行"的生成路径，消除 token 消耗与执行不确定性。
'''
''' 生成的工作表样式完全由 <see cref="ReportHelper.WriteReportSheet"/> 决定：
'''   - 第 1 行：跨列合并的草绿色斜体注释行（白底、左对齐）
'''   - 第 2 行：深蓝底白色加粗的列标题行
'''   - 第 3 行起：Cambria 11 号正文，首列为深灰色斜体行标题
'''   - 冻结窗格锚定于 B2
''' </summary>
Public Module XlsxReportBuilder

    ''' <summary>
    ''' Excel 工作表名称的最大长度限制
    ''' </summary>
    Private Const MaxSheetNameLength As Integer = 31

    ''' <summary>
    ''' 依据 LLM 生成的表格注释信息，把一组 CSV 编译为带样式的单个 xlsx 文件。
    ''' </summary>
    ''' <param name="annotations">含 sheets（csv 路径 / 工作表名 / 注释文本）的注释模型</param>
    ''' <param name="xlsxPath">输出 xlsx 的完整路径</param>
    ''' <param name="logger">日志回调，通常传入模块基类的 LogInfo</param>
    ''' <returns>成功写入的工作表数量；为 0 时表示未生成任何文件</returns>
    Public Function BuildWorkbook(annotations As SheetAnnotations,
                                  xlsxPath As String,
                                  logger As Action(Of String)) As Integer

        Dim log As Action(Of String) = If(logger, Sub(msg As String)
                                                      ' 未提供日志回调时静默处理
                                                  End Sub)

        If annotations Is Nothing OrElse annotations.sheets Is Nothing OrElse annotations.sheets.Length = 0 Then
            Call log($"[警告] 没有可用的表格注释信息，跳过 xlsx 生成：{xlsxPath}")
            Return 0
        End If

        ' 不使用 New Workbook(createWorkSheet:=True)，避免残留一张空的 Sheet1
        Dim workbook As New Workbook()
        Dim usedNames As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
        Dim success As Integer = 0

        For i As Integer = 0 To annotations.sheets.Length - 1
            Dim sheetInfo As SheetAnnotations.Sheet = annotations.sheets(i)

            If sheetInfo Is Nothing Then
                Continue For
            End If

            Try
                Call WriteOneSheet(workbook, sheetInfo, i, usedNames, log)
                success += 1
            Catch ex As Exception
                Call log($"[警告] 工作表生成失败，已跳过：{sheetInfo.csv} - {ex.Message}")
            End Try
        Next

        If success = 0 Then
            Call log($"[警告] 所有工作表均生成失败，未输出 xlsx 文件：{xlsxPath}")
            Return 0
        End If

        Dim outputDir As String = Path.GetDirectoryName(xlsxPath)

        If Not outputDir.StringEmpty AndAlso Not Directory.Exists(outputDir) Then
            Call Directory.CreateDirectory(outputDir)
        End If

        Call workbook.SaveAs(xlsxPath)
        Call log($"xlsx 已生成（{success} 张工作表）：{xlsxPath}")

        Return success
    End Function

    ''' <summary>
    ''' 读取单个 CSV 文件并作为一张工作表写入工作簿
    ''' </summary>
    Private Sub WriteOneSheet(workbook As Workbook,
                              sheetInfo As SheetAnnotations.Sheet,
                              index As Integer,
                              usedNames As HashSet(Of String),
                              log As Action(Of String))

        Dim csvPath As String = sheetInfo.csv

        If csvPath.StringEmpty OrElse Not File.Exists(csvPath) Then
            Throw New FileNotFoundException($"CSV 文件不存在：{csvPath}")
        End If

        ' 采用 sciBASIC 的 CSV 解析器，可正确处理字段内的逗号、引号与转义
        Dim rows As DataFrameResolver = DataFrameResolver.Load(csvPath)
        Dim header As String() = rows.HeadTitles

        If header Is Nothing OrElse header.Length = 0 Then
            Throw New InvalidDataException("CSV 文件没有表头行")
        End If

        Dim rowTitles As New List(Of String)
        Dim data As New List(Of IEnumerable(Of Object))

        For i As Integer = 0 To rows.Nrows - 1
            Dim row = rows.GetRow(i)

            If row Is Nothing OrElse row.Count = 0 Then
                Continue For
            End If

            rowTitles.Add(row(0))

            Dim cells As New List(Of Object)

            For j As Integer = 1 To row.Count - 1
                cells.Add(ParseCellValue(row(j)))
            Next

            data.Add(cells)
        Next

        Dim sheetName As String = ResolveSheetName(sheetInfo, csvPath, index, usedNames)
        Dim comment As String = If(sheetInfo.annotation, "")

        ' CSV 为空或仅有表头时，仍写出只含注释行与标题行的工作表
        Call workbook.WriteReportSheet(sheetName, comment, header, rowTitles, data)
        Call log($"  工作表 [{sheetName}] 写入完成，共 {rowTitles.Count} 行")
    End Sub

    ''' <summary>
    ''' 轻量数值探测：可解析为数值的单元格以 <see cref="Double"/> 写入，
    ''' 以保持 Excel 中的数值类型，否则按字符串写入。
    ''' </summary>
    Private Function ParseCellValue(text As String) As Object
        If text.StringEmpty Then
            Return ""
        End If

        Dim value As Double

        If Double.TryParse(text, NumberStyles.Any, CultureInfo.InvariantCulture, value) AndAlso
           Not Double.IsNaN(value) AndAlso Not Double.IsInfinity(value) Then

            Return value
        End If

        Return text
    End Function

    ''' <summary>
    ''' 解析并去重工作表名称。
    ''' 空名时回退为 CSV 文件名，再回退为 Sheet{index}；名称冲突时追加 _2 / _3 后缀，
    ''' 并保证结果不超过 Excel 的 31 字符限制。
    ''' </summary>
    Private Function ResolveSheetName(sheetInfo As SheetAnnotations.Sheet,
                                      csvPath As String,
                                      index As Integer,
                                      usedNames As HashSet(Of String)) As String

        Dim baseName As String = sheetInfo.sheet_name

        If baseName.StringEmpty Then
            baseName = Path.GetFileNameWithoutExtension(csvPath)
        End If
        If baseName.StringEmpty Then
            baseName = $"Sheet{index + 1}"
        End If

        baseName = SanitizeSheetName(baseName)

        Dim candidate As String = baseName
        Dim suffixIndex As Integer = 2

        While usedNames.Contains(candidate)
            Dim suffix As String = "_" & suffixIndex
            Dim keep As Integer = Math.Min(baseName.Length, MaxSheetNameLength - suffix.Length)

            If keep < 1 Then
                keep = 1
            End If

            candidate = baseName.Substring(0, keep) & suffix
            suffixIndex += 1
        End While

        Call usedNames.Add(candidate)

        Return candidate
    End Function

    ''' <summary>
    ''' 清理工作表名称中的非法字符并截断至 31 个字符
    ''' </summary>
    Private Function SanitizeSheetName(name As String) As String
        Dim clean As String = name

        For Each c As Char In New Char() {":"c, "\"c, "/"c, "?"c, "*"c, "["c, "]"c}
            clean = clean.Replace(c, "_"c)
        Next

        clean = clean.Trim()

        If clean.StringEmpty Then
            clean = "Sheet"
        End If
        If clean.Length > MaxSheetNameLength Then
            clean = clean.Substring(0, MaxSheetNameLength)
        End If

        Return clean
    End Function

End Module

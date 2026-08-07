Imports Microsoft.VisualBasic.Data.Framework.IO
Imports Microsoft.VisualBasic.Data.Framework.IO.CSVFile
Imports OmicsAgent.Dataset

''' <summary>
''' 多组学分子注释表合并器。
''' </summary>
''' <remarks>
''' 多组学场景下每个组学都有各自的分子注释表（基因注释、代谢物注释……），
''' 而既有的分析模块与提示词均以 <see cref="AnalysisContext.AnnotationFile"/> 这一
''' 全局注释表视角来工作。
'''
''' 本类把各组学的注释表纵向合并为一张总表，并追加 <c>omics_id</c> / <c>omics_label</c>
''' 两列用于标识每条注释的组学来源，写入工作区后让 <see cref="AnalysisContext.AnnotationFile"/>
''' 指向它，从而在引入多组学能力的同时完全不破坏既有模块的注释表引用方式。
'''
''' 单组学场景下不做任何合并，直接透传原注释表，行为与升级前完全一致。
''' </remarks>
Public Class AnnotationMerger

    Private ReadOnly _context As AnalysisContext
    Private ReadOnly _logger As Action(Of String)

    ''' <summary>合并总表中标识注释来源组学的列名</summary>
    Public Const OmicsIdColumn As String = "omics_id"

    ''' <summary>合并总表中标识注释来源组学展示名的列名</summary>
    Public Const OmicsLabelColumn As String = "omics_label"

    ''' <summary>注释总表在工作区中的文件名</summary>
    Public Const MergedFileName As String = "merged_annotation.csv"

    Public Sub New(context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        _context = context
        _logger = If(logger, Sub(s As String) Console.WriteLine(s))
    End Sub

    ''' <summary>
    ''' 执行注释表整理：读取各组学各自的注释表，必要时合并为全局总表。
    ''' </summary>
    Public Sub Merge()
        Dim datasets As List(Of OmicsDataset) = _context.Datasets

        If datasets.IsNullOrEmpty Then
            Return
        End If

        ' 先分别读入每个组学自己的注释表
        For Each ds As OmicsDataset In datasets
            If ds.AnnotationFile.FileExists Then
                Try
                    ds.AnnotationContent = Molecule.ReadCsv(ds.AnnotationFile).ToArray
                Catch ex As Exception
                    _logger($"  [!] Failed to parse the annotation table of dataset [{ds.Id}]: {ex.Message}")
                    ds.AnnotationContent = {}
                End Try
            Else
                ds.AnnotationContent = {}
            End If
        Next

        Dim annotated As List(Of OmicsDataset) = datasets.Where(Function(d) d.AnnotationFile.FileExists).AsList

        If annotated.Count = 0 Then
            _logger("  [!] No annotation table available in any omics dataset.")
            Return
        End If

        ' 单组学：直接沿用原注释表，不产生额外文件
        If datasets.Count = 1 Then
            _context.AnnotationFile = annotated(0).AnnotationFile
            _context.AnnotationContent = annotated(0).AnnotationContent
            Return
        End If

        ' 多组学：合并为带来源标识的全局总表
        Call MergeToGlobalTable(annotated)
    End Sub

    ''' <summary>把多个组学的注释表纵向合并为一张总表</summary>
    Private Sub MergeToGlobalTable(annotated As List(Of OmicsDataset))
        Dim destFile As String = Path.Combine(_context.WorkspaceDir, MergedFileName)

        ' 合并总表的列 = 各组学注释表列名的并集，并在最前面加上来源标识列。
        ' 取并集而非交集，是为了保留各组学注释中特有的信息列（例如代谢物的 HMDB 编号）。
        Dim columns As New List(Of String) From {OmicsIdColumn, OmicsLabelColumn}
        Dim seen As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase) From {OmicsIdColumn, OmicsLabelColumn}

        Dim headerOf As New Dictionary(Of String, String())

        For Each ds As OmicsDataset In annotated
            Dim header As String() = CsvUtils.ReadHeader(ds.AnnotationFile)

            headerOf(ds.Id) = header

            For Each col As String In header
                Dim name As String = If(col, "").Trim

                If Not name.StringEmpty(, True) AndAlso seen.Add(name) Then
                    columns.Add(name)
                End If
            Next
        Next

        Dim total As Integer = 0

        Using writer As New StreamWriter(destFile, append:=False, encoding:=New UTF8Encoding(False))
            writer.WriteLine(CsvUtils.ToCsvLine(columns))

            For Each ds As OmicsDataset In annotated
                Dim header As String() = headerOf(ds.Id)

                ' 建立「合并总表列序号 -> 该组学注释表列序号」的投影关系，
                ' 逐行处理时直接按索引取值，避免重复的列名查找。
                Dim projection As Integer() = columns _
                    .Select(Function(col) IndexOfColumn(header, col)) _
                    .ToArray

                Dim isFirstRow As Boolean = True

                Using s As Stream = ds.AnnotationFile.Open(FileMode.Open, doClear:=False, [readOnly]:=True)
                    For Each row As RowObject In RowIterator.RowSolver(s, simple:=True)
                        If row.IsNullOrEmpty Then
                            Continue For
                        End If

                        If isFirstRow Then
                            isFirstRow = False
                            Continue For
                        End If

                        Dim line As New List(Of String)

                        For i As Integer = 0 To columns.Count - 1
                            Select Case columns(i)
                                Case OmicsIdColumn : line.Add(ds.Id)
                                Case OmicsLabelColumn : line.Add(ds.DisplayName)
                                Case Else
                                    Dim srcIndex As Integer = projection(i)

                                    line.Add(If(srcIndex >= 0 AndAlso srcIndex < row.Count, row.DirectGet(srcIndex), ""))
                            End Select
                        Next

                        writer.WriteLine(CsvUtils.ToCsvLine(line))
                        total += 1
                    Next
                End Using
            Next
        End Using

        _context.AnnotationFile = destFile
        _context.AnnotationContent = annotated _
            .Where(Function(d) Not d.AnnotationContent.IsNullOrEmpty) _
            .SelectMany(Function(d) d.AnnotationContent) _
            .ToArray

        _logger($"[OK] Merged annotation table written: {destFile} ({total} records from {annotated.Count} omics datasets)")
    End Sub

    ''' <summary>在表头中按不区分大小写的方式查找列索引</summary>
    Private Shared Function IndexOfColumn(header As String(), columnName As String) As Integer
        For i As Integer = 0 To header.Length - 1
            If String.Equals(If(header(i), "").Trim, columnName, StringComparison.OrdinalIgnoreCase) Then
                Return i
            End If
        Next

        Return -1
    End Function

End Class

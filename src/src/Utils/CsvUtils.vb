' ============================================================================
' CSV 工具类 - 表达矩阵、注释表、样本元数据的读取与格式校验
' ============================================================================
Imports System.Globalization
Imports Microsoft.VisualBasic.Data.Framework.IO
Imports Microsoft.VisualBasic.Data.Framework.IO.CSVFile
Imports Microsoft.VisualBasic.Data.Framework.StorageProvider

''' <summary>
''' 提供对 CSV 文件的读取、写入、格式校验等通用工具方法。
''' 主要用于表达矩阵、分子注释表、样本元数据表的解析与验证。
''' </summary>
Public Module CsvUtils

    ''' <summary>
    ''' 校验表达矩阵 CSV 文件格式：
    ''' - 第一行为样本 ID
    ''' - 第一列为分子 ID
    ''' - 其他单元格为数值
    ''' </summary>
    Public Function ValidateExpressionMatrix(filePath As String, ByRef errorMsg As String) As Boolean
        errorMsg = ""
        If Not filePath.FileExists Then
            errorMsg = $"Expression matrix file not found: {filePath}"
            Return False
        End If

        Try
            Dim rows = DataFrameResolver.Load(filePath)
            If rows.Nrows <= 0 Then
                errorMsg = "Expression matrix must contain at least one data row."
                Return False
            End If

            Dim header = rows.HeadTitles
            If header.Length < 2 Then
                errorMsg = "Expression matrix must contain at least one sample column."
                Return False
            End If

            ' 检查数据行：第一列为分子 ID，其他列应为数值
            Dim sampleCount = header.Length - 1
            For i As Integer = 0 To Math.Min(rows.Nrows - 1, 5)
                Dim row = rows.GetRow(i)
                If row.Count <> header.Length Then
                    errorMsg = $"Row {i + 1} has {row.Count} fields, expected {header.Length}."
                    Return False
                End If
                For j = 1 To row.Count - 1
                    Dim v As Double
                    If Not Double.TryParse(row(j), NumberStyles.Any, CultureInfo.InvariantCulture, v) Then
                        errorMsg = $"Cell at row {i + 1}, column {j + 1} is not a valid number: '{row(j)}'"
                        Return False
                    End If
                Next
            Next

            Return True
        Catch ex As Exception
            errorMsg = $"Failed to validate expression matrix: {ex.Message}"
            Return False
        End Try
    End Function

    ''' <summary>
    ''' 校验分子注释表 CSV 文件格式：
    ''' 必须包含 id、type、name、kegg 列（class/category 可选）
    ''' </summary>
    Public Function ValidateAnnotation(filePath As String, ByRef errorMsg As String) As Boolean
        errorMsg = ""
        If Not filePath.FileExists Then
            errorMsg = $"Annotation file not found: {filePath}"
            Return False
        End If

        Try
            Dim rows = DataFrameResolver.Load(filePath)
            If rows.Nrows <= 0 Then
                errorMsg = "Annotation table must contain at least one data row."
                Return False
            End If

            Dim header = rows.HeadTitles.Select(Function(h) h.ToLower().Trim()).ToList()
            Dim requiredCols = {"id", "type", "name", "kegg"}
            For Each col In requiredCols
                If Not header.Contains(col) Then
                    errorMsg = $"Annotation table must contain column '{col}'. Found columns: {String.Join(", ", header)}"
                    Return False
                End If
            Next

            Return True
        Catch ex As Exception
            errorMsg = $"Failed to validate annotation table: {ex.Message}"
            Return False
        End Try
    End Function

    ''' <summary>
    ''' 校验样本元数据 CSV 文件格式：
    ''' 必须包含 ID、sample_name、sample_info 列
    ''' </summary>
    Public Function ValidateSampleInfo(filePath As String, ByRef errorMsg As String) As Boolean
        errorMsg = ""
        If Not filePath.FileExists Then
            errorMsg = $"Sample info file not found: {filePath}"
            Return False
        End If

        Try
            Dim rows = DataFrameResolver.Load(filePath)
            If rows.Nrows <= 0 Then
                errorMsg = "Sample info table must contain at least one data row."
                Return False
            End If

            Dim header = rows.HeadTitles.Select(Function(h) h.ToLower().Trim()).ToList()
            Dim requiredCols = {"id", "sample_name", "sample_info"}
            For Each col In requiredCols
                If Not header.Contains(col) Then
                    errorMsg = $"Sample info table must contain column '{col}'. Found columns: {String.Join(", ", header)}"
                    Return False
                End If
            Next

            Return True
        Catch ex As Exception
            errorMsg = $"Failed to validate sample info table: {ex.Message}"
            Return False
        End Try
    End Function

    ''' <summary>读取 CSV 文件第一列数据（不含表头）</summary>
    Public Iterator Function ReadFirstColumn(filePath As String) As IEnumerable(Of String)
        If filePath.FileExists Then
            Using s As Stream = filePath.Open(FileMode.Open, doClear:=False, [readOnly]:=True)
                Dim rows As IEnumerable(Of RowObject) = RowIterator.RowSolver(s, simple:=True)

                For Each row As RowObject In rows.Skip(1)
                    If Not row.IsNullOrEmpty Then
                        Yield row.DirectGet(0)
                    End If
                Next
            End Using
        End If
    End Function

    ''' <summary>读取 CSV 文件第一行（表头）除第一列外的所有列名</summary>
    Public Function ReadSampleIDs(filePath As String) As String()
        If filePath.FileExists Then
            Return Tokenizer.CharsParser(filePath.ReadFirstLine).Skip(1).ToArray
        Else
            Return {}
        End If
    End Function

    ''' <summary>读取 CSV 文件第一行（表头）的全部列名（含第一列）</summary>
    Public Function ReadHeader(filePath As String) As String()
        If filePath.FileExists Then
            Return Tokenizer.CharsParser(filePath.ReadFirstLine).ToArray
        Else
            Return {}
        End If
    End Function

    ''' <summary>
    ''' 以流式方式对表达矩阵做列投影重写：仅保留 <paramref name="keepColumnIndex"/> 指定的样本列，
    ''' 并把表头替换为 <paramref name="newHeader"/>。第一列（分子 ID 列）始终保留。
    ''' </summary>
    ''' <param name="sourceFile">源表达矩阵路径</param>
    ''' <param name="destFile">输出文件路径</param>
    ''' <param name="keepColumnIndex">
    ''' 需要保留的样本列在源文件中的列索引（从 0 开始，已包含第一列偏移，
    ''' 即索引 0 表示分子 ID 列，样本列索引应 &gt;= 1），按输出顺序排列。
    ''' </param>
    ''' <param name="newHeader">输出文件的样本列名（与 <paramref name="keepColumnIndex"/> 一一对应）</param>
    ''' <param name="idColumnName">输出文件第一列的列名，为空时沿用源文件的第一列列名</param>
    ''' <returns>写出的数据行数（不含表头）</returns>
    ''' <remarks>
    ''' 表达矩阵可能包含数十万行，此处采用逐行迭代 + 列索引投影的方式处理，
    ''' 全过程只在内存中保留单行数据，避免整表载入造成的内存压力。
    ''' 列索引在处理表头时一次性计算完成，逐行处理时不再做任何字符串查找。
    ''' </remarks>
    Public Function ProjectMatrixColumns(sourceFile As String,
                                         destFile As String,
                                         keepColumnIndex As Integer(),
                                         newHeader As String(),
                                         Optional idColumnName As String = Nothing) As Integer

        If Not sourceFile.FileExists Then
            Throw New FileNotFoundException($"Expression matrix file not found: {sourceFile}")
        End If
        If keepColumnIndex.Length <> newHeader.Length Then
            Throw New ArgumentException(
                $"Column index count ({keepColumnIndex.Length}) does not match the new header count ({newHeader.Length}).")
        End If

        Call EnsureParentDirectory(destFile)

        Dim nrows As Integer = 0
        Dim isFirstRow As Boolean = True

        Using writer As New StreamWriter(destFile, append:=False, encoding:=New UTF8Encoding(False)),
              s As Stream = sourceFile.Open(FileMode.Open, doClear:=False, [readOnly]:=True)

            For Each row As RowObject In RowIterator.RowSolver(s, simple:=True)
                If row.IsNullOrEmpty Then
                    Continue For
                End If

                If isFirstRow Then
                    ' 表头行：第一列沿用原列名（或使用指定名称），样本列全部替换为新列名
                    Dim firstCol As String = If(idColumnName.StringEmpty(, True), row.DirectGet(0), idColumnName)
                    Dim headerLine As New List(Of String) From {firstCol}

                    headerLine.AddRange(newHeader)
                    writer.WriteLine(ToCsvLine(headerLine))

                    isFirstRow = False
                Else
                    Dim line As New List(Of String) From {row.DirectGet(0)}

                    For Each colIndex As Integer In keepColumnIndex
                        line.Add(If(colIndex < row.Count, row.DirectGet(colIndex), ""))
                    Next

                    writer.WriteLine(ToCsvLine(line))
                    nrows += 1
                End If
            Next
        End Using

        Return nrows
    End Function

    ''' <summary>
    ''' 按样本 ID 映射关系重写样本元数据表：把 id 列的值替换为对应的 subject_id，
    ''' 并且只保留出现在映射表中的样本行，输出行顺序与 <paramref name="orderedSubjects"/> 一致。
    ''' </summary>
    ''' <param name="sourceFile">源样本元数据表路径</param>
    ''' <param name="destFile">输出文件路径</param>
    ''' <param name="sampleToSubject">原始样本 ID 到 subject_id 的映射</param>
    ''' <param name="orderedSubjects">输出行的 subject_id 顺序</param>
    ''' <returns>写出的数据行数（不含表头）</returns>
    Public Function RemapSampleInfo(sourceFile As String,
                                    destFile As String,
                                    sampleToSubject As Dictionary(Of String, String),
                                    orderedSubjects As String()) As Integer

        If Not sourceFile.FileExists Then
            Throw New FileNotFoundException($"Sample info file not found: {sourceFile}")
        End If

        Call EnsureParentDirectory(destFile)

        Dim header As String() = Nothing
        Dim idColumn As Integer = -1
        ' subject_id -> 重写后的该行内容
        Dim rowsBySubject As New Dictionary(Of String, List(Of String))(StringComparer.OrdinalIgnoreCase)

        Using s As Stream = sourceFile.Open(FileMode.Open, doClear:=False, [readOnly]:=True)
            For Each row As RowObject In RowIterator.RowSolver(s, simple:=True)
                If row.IsNullOrEmpty Then
                    Continue For
                End If

                If header Is Nothing Then
                    header = row.ToArray
                    idColumn = header _
                        .Select(Function(h, i) (h:=If(h, "").Trim.ToLower, i:=i)) _
                        .Where(Function(t) t.h = "id") _
                        .Select(Function(t) t.i) _
                        .DefaultIfEmpty(0) _
                        .First

                    Continue For
                End If

                Dim rawId As String = If(idColumn < row.Count, row.DirectGet(idColumn), "")
                Dim subjectId As String = Nothing

                If rawId.StringEmpty(, True) OrElse Not sampleToSubject.TryGetValue(rawId.Trim, subjectId) Then
                    ' 未参与对齐的样本直接丢弃
                    Continue For
                End If

                Dim line As List(Of String) = row.ToArray.AsList
                line(idColumn) = subjectId
                rowsBySubject(subjectId) = line
            Next
        End Using

        If header Is Nothing Then
            Throw New InvalidDataException($"Sample info file is empty: {sourceFile}")
        End If

        Dim nrows As Integer = 0

        Using writer As New StreamWriter(destFile, append:=False, encoding:=New UTF8Encoding(False))
            writer.WriteLine(ToCsvLine(header))

            For Each subjectId As String In orderedSubjects
                Dim line As List(Of String) = Nothing

                If rowsBySubject.TryGetValue(subjectId, line) Then
                    writer.WriteLine(ToCsvLine(line))
                    nrows += 1
                End If
            Next
        End Using

        Return nrows
    End Function

    ''' <summary>把一行字段序列化为 CSV 文本行，按需为字段补上双引号转义</summary>
    Public Function ToCsvLine(fields As IEnumerable(Of String)) As String
        Return String.Join(",", fields.Select(AddressOf EscapeCsvField))
    End Function

    ''' <summary>对单个 CSV 字段做必要的转义处理</summary>
    Private Function EscapeCsvField(field As String) As String
        Dim value As String = If(field, "")

        If value.IndexOfAny({","c, """"c, ControlChars.Cr, ControlChars.Lf}) >= 0 Then
            Return """" & value.Replace("""", """""") & """"
        End If

        Return value
    End Function

    ''' <summary>确保目标文件所在的目录已存在</summary>
    Private Sub EnsureParentDirectory(filePath As String)
        Dim dir As String = Path.GetDirectoryName(Path.GetFullPath(filePath))

        If Not dir.StringEmpty(, True) AndAlso Not Directory.Exists(dir) Then
            Call Directory.CreateDirectory(dir)
        End If
    End Sub

End Module

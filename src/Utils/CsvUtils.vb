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
                Dim row = rows(i)
                If row.Length <> header.Length Then
                    errorMsg = $"Row {i + 1} has {row.Length} fields, expected {header.Length}."
                    Return False
                End If
                For j = 1 To row.Length - 1
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

            ' 检查是否包含 time 列（用于判断时间序列数据）
            If header.Contains("time") Then
                ' 标记为时间序列数据
            End If

            Return True
        Catch ex As Exception
            errorMsg = $"Failed to validate sample info table: {ex.Message}"
            Return False
        End Try
    End Function

    ''' <summary>读取 CSV 文件第一列数据（不含表头）</summary>
    Public Function ReadFirstColumn(filePath As String) As List(Of String)
        Dim result As New List(Of String)()

        If filePath.FileExists Then
            Using s As Stream = filePath.Open(FileMode.Open, doClear:=False, [readOnly]:=True)
                Dim rows As IEnumerable(Of RowObject) = RowIterator.RowSolver(s, simple:=True)

                For Each row As RowObject In rows.Skip(1)
                    If Not row.IsNullOrEmpty Then
                        Call result.Add(row.DirectGet(0))
                    End If
                Next
            End Using
        End If

        Return result
    End Function

    ''' <summary>读取 CSV 文件第一行（表头）除第一列外的所有列名</summary>
    Public Function ReadSampleIDs(filePath As String) As List(Of String)
        Dim result As New List(Of String)()

        If filePath.FileExists Then
            result = New List(Of String)(Tokenizer.CharsParser(filePath.ReadFirstLine).Skip(1))
        End If

        Return result
    End Function

End Module

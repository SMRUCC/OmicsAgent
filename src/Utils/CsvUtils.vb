' ============================================================================
' CSV 工具类 - 表达矩阵、注释表、样本元数据的读取与格式校验
' ============================================================================
Imports System.IO
Imports System.Text
Imports System.Globalization

''' <summary>
''' 提供对 CSV 文件的读取、写入、格式校验等通用工具方法。
''' 主要用于表达矩阵、分子注释表、样本元数据表的解析与验证。
''' </summary>
Public Module CsvUtils

    ''' <summary>
    ''' 读取 CSV 文件为二维字符串数组（含表头）。
    ''' 使用简单的逗号分隔解析，支持双引号包裹的字段。
    ''' </summary>
    Public Function ReadCsv(filePath As String) As String()()
        If Not File.Exists(filePath) Then
            Throw New FileNotFoundException($"CSV file not found: {filePath}")
        End If

        Dim lines = File.ReadAllLines(filePath, Encoding.UTF8)
        Dim rows As New List(Of String())()

        For Each line In lines
            If String.IsNullOrEmpty(line) Then Continue For
            rows.Add(ParseCsvLine(line))
        Next

        Return rows.ToArray()
    End Function

    ''' <summary>解析单行 CSV 文本，支持双引号字段</summary>
    Public Function ParseCsvLine(line As String) As String()
        Dim fields As New List(Of String)()
        Dim sb As New StringBuilder()
        Dim inQuotes As Boolean = False

        For i = 0 To line.Length - 1
            Dim c = line(i)
            If c = """"c Then
                If inQuotes AndAlso i < line.Length - 1 AndAlso line(i + 1) = """"c Then
                    sb.Append(""""c)
                    i += 1
                Else
                    inQuotes = Not inQuotes
                End If
            ElseIf c = ","c AndAlso Not inQuotes Then
                fields.Add(sb.ToString())
                sb.Clear()
            Else
                sb.Append(c)
            End If
        Next

        fields.Add(sb.ToString())
        Return fields.ToArray()
    End Function

    ''' <summary>将二维字符串数组写入 CSV 文件</summary>
    Public Sub WriteCsv(filePath As String, rows As String()())
        Dim dir = Path.GetDirectoryName(filePath)
        If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
            Directory.CreateDirectory(dir)
        End If

        Dim sb As New StringBuilder()
        For Each row In rows
            sb.AppendLine(String.Join(",", row.Select(Function(f) EscapeCsvField(f))))
        Next

        File.WriteAllText(filePath, sb.ToString(), Encoding.UTF8)
    End Sub

    ''' <summary>转义 CSV 字段中的特殊字符</summary>
    Private Function EscapeCsvField(field As String) As String
        If field Is Nothing Then Return ""
        If field.Contains(",") OrElse field.Contains("""") OrElse field.Contains(vbCr) OrElse field.Contains(vbLf) Then
            Return $"""{field.Replace("""", """""")}"""
        End If
        Return field
    End Function

    ''' <summary>
    ''' 校验表达矩阵 CSV 文件格式：
    ''' - 第一行为样本 ID
    ''' - 第一列为分子 ID
    ''' - 其他单元格为数值
    ''' </summary>
    Public Function ValidateExpressionMatrix(filePath As String, ByRef errorMsg As String) As Boolean
        errorMsg = ""
        If Not File.Exists(filePath) Then
            errorMsg = $"Expression matrix file not found: {filePath}"
            Return False
        End If

        Try
            Dim rows = ReadCsv(filePath)
            If rows.Length < 2 Then
                errorMsg = "Expression matrix must contain at least one data row."
                Return False
            End If

            Dim header = rows(0)
            If header.Length < 2 Then
                errorMsg = "Expression matrix must contain at least one sample column."
                Return False
            End If

            ' 检查数据行：第一列为分子 ID，其他列应为数值
            Dim sampleCount = header.Length - 1
            For i = 1 To Math.Min(rows.Length - 1, 5)
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
        If Not File.Exists(filePath) Then
            errorMsg = $"Annotation file not found: {filePath}"
            Return False
        End If

        Try
            Dim rows = ReadCsv(filePath)
            If rows.Length < 2 Then
                errorMsg = "Annotation table must contain at least one data row."
                Return False
            End If

            Dim header = rows(0).Select(Function(h) h.ToLower().Trim()).ToList()
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
        If Not File.Exists(filePath) Then
            errorMsg = $"Sample info file not found: {filePath}"
            Return False
        End If

        Try
            Dim rows = ReadCsv(filePath)
            If rows.Length < 2 Then
                errorMsg = "Sample info table must contain at least one data row."
                Return False
            End If

            Dim header = rows(0).Select(Function(h) h.ToLower().Trim()).ToList()
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

    ''' <summary>读取 CSV 文件表头列名</summary>
    Public Function ReadHeader(filePath As String) As String()
        If Not File.Exists(filePath) Then Return {}
        Dim rows = ReadCsv(filePath)
        If rows.Length = 0 Then Return {}
        Return rows(0)
    End Function

    ''' <summary>读取 CSV 文件第一列数据（不含表头）</summary>
    Public Function ReadFirstColumn(filePath As String) As List(Of String)
        Dim result As New List(Of String)()
        If Not File.Exists(filePath) Then Return result
        Dim rows = ReadCsv(filePath)
        For i = 1 To rows.Length - 1
            If rows(i).Length > 0 Then result.Add(rows(i)(0))
        Next
        Return result
    End Function

    ''' <summary>读取 CSV 文件第一行（表头）除第一列外的所有列名</summary>
    Public Function ReadSampleIDs(filePath As String) As List(Of String)
        Dim result As New List(Of String)()
        If Not File.Exists(filePath) Then Return result
        Dim header = ReadHeader(filePath)
        If header.Length <= 1 Then Return result
        For j = 1 To header.Length - 1
            result.Add(header(j))
        Next
        Return result
    End Function

End Module

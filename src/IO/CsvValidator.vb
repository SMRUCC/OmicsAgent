' ============================================================================
' CSV 文件格式验证器
' ============================================================================
Imports System.IO

Namespace IO

    ''' <summary>
    ''' 验证用户输入的 CSV 文件格式是否符合规范
    ''' </summary>
    Public Class CsvValidator

        ''' <summary>
        ''' 验证表达矩阵 CSV：第一行为样本ID，第一列为分子ID，其他单元格为表达值
        ''' </summary>
        Public Function ValidateExpressionMatrix(csvPath As String, ByRef errMsg As String) As Boolean
            If Not File.Exists(csvPath) Then
                errMsg = $"Expression matrix file not found: {csvPath}"
                Return False
            End If

            Try
                Dim firstLine = File.ReadLines(csvPath).FirstOrDefault()
                If String.IsNullOrEmpty(firstLine) Then
                    errMsg = "Expression matrix file is empty."
                    Return False
                End If

                Dim headers = firstLine.Split(","c)
                If headers.Length < 3 Then
                    errMsg = $"Expression matrix must have at least 3 columns (1 molecule ID + 2 samples), found {headers.Length}."
                    Return False
                End If

                ' 第一列通常是 ID / gene / molecule 之类的
                Dim firstCol = headers(0).Trim().ToLower()
                If Not (firstCol.Contains("id") OrElse firstCol.Contains("gene") OrElse firstCol.Contains("molecule") OrElse firstCol.Contains("protein") OrElse firstCol.Contains("metabolite")) Then
                    Console.WriteLine($"[Validator] Warning: first column header '{headers(0)}' does not look like a molecule ID column.")
                End If

                Return True
            Catch ex As Exception
                errMsg = $"Failed to read expression matrix: {ex.Message}"
                Return False
            End Try
        End Function

        ''' <summary>
        ''' 验证分子注释 CSV：必须包含 id, type, name, class/category, kegg 列
        ''' </summary>
        Public Function ValidateAnnotation(csvPath As String, ByRef errMsg As String) As Boolean
            If Not File.Exists(csvPath) Then
                errMsg = $"Annotation file not found: {csvPath}"
                Return False
            End If

            Try
                Dim firstLine = File.ReadLines(csvPath).FirstOrDefault()
                If String.IsNullOrEmpty(firstLine) Then
                    errMsg = "Annotation file is empty."
                    Return False
                End If

                Dim headers = firstLine.Split(","c).Select(Function(h) h.Trim().ToLower()).ToArray()
                Dim required As String() = {"id", "type", "name", "kegg"}
                For Each r In required
                    If Not headers.Contains(r) Then
                        errMsg = $"Annotation file must contain column '{r}'. Found columns: {String.Join(", ", headers)}"
                        Return False
                    End If
                Next

                ' class 或 category 至少有一个
                If Not headers.Contains("class") AndAlso Not headers.Contains("category") Then
                    errMsg = "Annotation file must contain 'class' or 'category' column."
                    Return False
                End If

                Return True
            Catch ex As Exception
                errMsg = $"Failed to read annotation: {ex.Message}"
                Return False
            End Try
        End Function

        ''' <summary>
        ''' 验证样本元数据 CSV：必须包含 ID, sample_name, sample_info 列
        ''' </summary>
        Public Function ValidateSampleInfo(csvPath As String, ByRef errMsg As String) As Boolean
            If Not File.Exists(csvPath) Then
                errMsg = $"Sample info file not found: {csvPath}"
                Return False
            End If

            Try
                Dim firstLine = File.ReadLines(csvPath).FirstOrDefault()
                If String.IsNullOrEmpty(firstLine) Then
                    errMsg = "Sample info file is empty."
                    Return False
                End If

                Dim headers = firstLine.Split(","c).Select(Function(h) h.Trim().ToLower()).ToArray()
                Dim required As String() = {"id", "sample_name", "sample_info"}
                For Each r In required
                    If Not headers.Contains(r) Then
                        errMsg = $"Sample info file must contain column '{r}'. Found columns: {String.Join(", ", headers)}"
                        Return False
                    End If
                Next

                Return True
            Catch ex As Exception
                errMsg = $"Failed to read sample info: {ex.Message}"
                Return False
            End Try
        End Function

        ''' <summary>
        ''' 读取 CSV 表头
        ''' </summary>
        Public Function ReadHeaders(csvPath As String) As String()
            If Not File.Exists(csvPath) Then Return {}
            Dim firstLine = File.ReadLines(csvPath).FirstOrDefault()
            If String.IsNullOrEmpty(firstLine) Then Return {}
            Return firstLine.Split(","c).Select(Function(h) h.Trim()).ToArray()
        End Function

        ''' <summary>
        ''' 读取样本分组信息
        ''' </summary>
        Public Function ReadSampleGroups(sampleInfoCsv As String) As List(Of String)
            Dim groups As New List(Of String)()
            If Not File.Exists(sampleInfoCsv) Then Return groups

            Dim lines = File.ReadAllLines(sampleInfoCsv)
            If lines.Length < 2 Then Return groups

            Dim headers = lines(0).Split(","c).Select(Function(h) h.Trim().ToLower()).ToArray()
            Dim idx = Array.IndexOf(headers, "sample_info")
            If idx < 0 Then Return groups

            For i = 1 To lines.Length - 1
                Dim fields = lines(i).Split(","c)
                If idx < fields.Length Then
                    Dim g = fields(idx).Trim()
                    If Not String.IsNullOrEmpty(g) AndAlso Not groups.Contains(g) Then
                        groups.Add(g)
                    End If
                End If
            Next
            Return groups
        End Function

    End Class

End Namespace

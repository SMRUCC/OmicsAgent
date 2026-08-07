Imports Microsoft.VisualBasic.Serialization.JSON

Namespace AppRuntime.Manifest

    ''' <summary>
    ''' 多组学数据集定义文件（--dataset 参数指向的 JSON）的强类型模型。
    ''' </summary>
    ''' <remarks>
    ''' 文件结构示例：
    ''' <code>
    ''' {
    '''   "datasets": [
    '''     {
    '''       "id": "rna",
    '''       "type": "transcriptome",
    '''       "label": "肝脏转录组",
    '''       "expression": "./rna/counts.csv",
    '''       "annotation": "./rna/gene_anno.csv",
    '''       "sampleinfo": "./meta/sample_rna.csv",
    '''       "unit": "TPM"
    '''     }
    '''   ],
    '''   "sample_alignment": { "mapping_file": "./meta/subject_map.csv" }
    ''' }
    ''' </code>
    ''' JSON 内的所有相对路径均相对该 JSON 文件所在目录解析。
    ''' </remarks>
    Public Class DatasetManifest

        ''' <summary>参与分析的各个组学数据集</summary>
        Public Property datasets As DatasetEntry()

        ''' <summary>跨组学样本对齐定义。可以省略，表示各组学样本 ID 已经天然一致。</summary>
        Public Property sample_alignment As SampleAlignmentSpec

        ''' <summary>该定义文件自身的完整路径（由加载器回填，不属于 JSON 内容）</summary>
        Public Property ManifestFile As String = ""

        ''' <summary>
        ''' 从 JSON 文件加载数据集定义，并把其中的相对路径转换为绝对路径。
        ''' 解析失败或内容非法时抛出异常，异常信息中会指出具体出错的数组下标与字段。
        ''' </summary>
        Public Shared Function LoadFromFile(jsonPath As String) As DatasetManifest
            If jsonPath.StringEmpty(, True) Then
                Throw New ArgumentException("The dataset manifest file path is empty.")
            End If

            Dim fullPath As String = jsonPath.GetFullPath

            If Not fullPath.FileExists Then
                Throw New FileNotFoundException($"Dataset manifest file not found: {fullPath}")
            End If

            Dim manifest As DatasetManifest

            Try
                manifest = File.ReadAllText(fullPath, Encoding.UTF8).LoadJSON(Of DatasetManifest)()
            Catch ex As Exception
                Throw New InvalidDataException($"Failed to parse the dataset manifest file '{fullPath}': {ex.Message}", ex)
            End Try

            If manifest Is Nothing Then
                Throw New InvalidDataException($"The dataset manifest file '{fullPath}' is empty or malformed.")
            End If

            If manifest.datasets Is Nothing OrElse manifest.datasets.Length = 0 Then
                Throw New InvalidDataException($"The dataset manifest file '{fullPath}' declares no dataset in the 'datasets' array.")
            End If

            manifest.ManifestFile = fullPath

            ' JSON 中的相对路径以该 JSON 文件所在目录为基准
            Dim baseDir As String = fullPath.ParentPath

            Call manifest.ResolvePaths(baseDir)
            Call manifest.Validate(fullPath)

            Return manifest
        End Function

        ''' <summary>把 JSON 中出现的所有相对路径转换为基于 JSON 文件所在目录的绝对路径</summary>
        Private Sub ResolvePaths(baseDir As String)
            For Each entry As DatasetEntry In datasets
                entry.expression = ResolvePath(entry.expression, baseDir)
                entry.annotation = ResolvePath(entry.annotation, baseDir)
                entry.sampleinfo = ResolvePath(entry.sampleinfo, baseDir)
            Next

            If sample_alignment IsNot Nothing Then
                sample_alignment.mapping_file = ResolvePath(sample_alignment.mapping_file, baseDir)
            End If
        End Sub

        ''' <summary>
        ''' 将单个路径解析为绝对路径。空值原样返回；已经是绝对路径的原样保留。
        ''' </summary>
        Private Shared Function ResolvePath(filePath As String, baseDir As String) As String
            If filePath.StringEmpty(, True) Then
                Return ""
            End If

            Dim trimmed As String = filePath.Trim

            If Path.IsPathRooted(trimmed) Then
                Return trimmed.GetFullPath
            End If

            Return Path.Combine(baseDir, trimmed).GetFullPath
        End Function

        ''' <summary>校验数据集定义的完整性与合法性</summary>
        Private Sub Validate(manifestPath As String)
            Dim seenIds As New Dictionary(Of String, Integer)(StringComparer.OrdinalIgnoreCase)

            For i As Integer = 0 To datasets.Length - 1
                Dim entry As DatasetEntry = datasets(i)
                Dim at As String = $"datasets[{i}]"

                If entry Is Nothing Then
                    Throw New InvalidDataException($"{at} in '{manifestPath}' is null.")
                End If

                If entry.id.StringEmpty(, True) Then
                    Throw New InvalidDataException($"{at} in '{manifestPath}' is missing the required 'id' field.")
                End If

                entry.id = entry.id.Trim

                If seenIds.ContainsKey(entry.id) Then
                    Throw New InvalidDataException(
                        $"{at} in '{manifestPath}' uses a duplicated id '{entry.id}', which was already declared by datasets[{seenIds(entry.id)}]. " &
                        "Each dataset id must be unique because it is used as the column name of the sample alignment table.")
                End If

                seenIds(entry.id) = i

                If entry.expression.StringEmpty(, True) Then
                    Throw New InvalidDataException($"{at} ('{entry.id}') in '{manifestPath}' is missing the required 'expression' field.")
                End If

                If Not entry.expression.FileExists Then
                    Throw New FileNotFoundException($"{at} ('{entry.id}'): expression matrix file not found: {entry.expression}")
                End If

                If Not entry.annotation.StringEmpty(, True) AndAlso Not entry.annotation.FileExists Then
                    Throw New FileNotFoundException($"{at} ('{entry.id}'): annotation file not found: {entry.annotation}")
                End If

                If Not entry.sampleinfo.StringEmpty(, True) AndAlso Not entry.sampleinfo.FileExists Then
                    Throw New FileNotFoundException($"{at} ('{entry.id}'): sample info file not found: {entry.sampleinfo}")
                End If
            Next

            If sample_alignment IsNot Nothing Then
                Call sample_alignment.Validate(manifestPath, seenIds.Keys.ToArray)
            End If
        End Sub

    End Class

End Namespace

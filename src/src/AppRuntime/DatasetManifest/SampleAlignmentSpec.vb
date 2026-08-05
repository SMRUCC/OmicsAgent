Namespace AppRuntime.Manifest

    ''' <summary>
    ''' 跨组学样本对齐定义。<see cref="mapping_file"/> 与 <see cref="subject_map"/> 二选一；
    ''' 两者皆为空时视为各组学样本 ID 已经一致。
    ''' </summary>
    Public Class SampleAlignmentSpec

        ''' <summary>
        ''' 样本对齐宽表 CSV 文件路径。表头首列为 subject_id，其余列名与各 dataset 的 id 一一对应。
        ''' </summary>
        Public Property mapping_file As String

        ''' <summary>
        ''' 以内联 JSON 对象数组形式直接给出的样本对齐宽表。
        ''' 每个对象形如 { "subject_id": "P001", "rna": "S1_R", "metab": "M_001" }。
        ''' 由于键集合取决于用户声明的 dataset id，此处只能使用字典承载而无法定义固定字段。
        ''' </summary>
        Public Property subject_map As Dictionary(Of String, String)()

        ''' <summary>是否显式声明了对齐关系（未声明时按同名样本一一匹配）</summary>
        Public ReadOnly Property HasExplicitMapping As Boolean
            Get
                Return Not mapping_file.StringEmpty(, True) OrElse (subject_map IsNot Nothing AndAlso subject_map.Length > 0)
            End Get
        End Property

        Friend Sub Validate(manifestPath As String, datasetIds As String())
            Dim hasFile As Boolean = Not mapping_file.StringEmpty(, True)
            Dim hasInline As Boolean = subject_map IsNot Nothing AndAlso subject_map.Length > 0

            If hasFile AndAlso hasInline Then
                Throw New InvalidDataException(
                    $"'sample_alignment' in '{manifestPath}' declares both 'mapping_file' and 'subject_map'. " &
                    "Please keep only one of them.")
            End If

            If hasFile AndAlso Not mapping_file.FileExists Then
                Throw New FileNotFoundException($"'sample_alignment.mapping_file' not found: {mapping_file}")
            End If

            If hasInline Then
                For i As Integer = 0 To subject_map.Length - 1
                    Dim row As Dictionary(Of String, String) = subject_map(i)

                    If row Is Nothing OrElse row.Count = 0 Then
                        Throw New InvalidDataException($"'sample_alignment.subject_map[{i}]' in '{manifestPath}' is empty.")
                    End If

                    If Not row.Keys.Any(Function(k) String.Equals(k, SampleAlignment.SubjectIdColumn, StringComparison.OrdinalIgnoreCase)) Then
                        Throw New InvalidDataException(
                            $"'sample_alignment.subject_map[{i}]' in '{manifestPath}' is missing the '{SampleAlignment.SubjectIdColumn}' key.")
                    End If
                Next
            End If
        End Sub

    End Class

End Namespace
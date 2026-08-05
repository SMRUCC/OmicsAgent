Namespace Dataset

    ''' <summary>
    ''' 单个生物学个体在各组学中的样本 ID 对应关系。
    ''' </summary>
    Public Class SubjectMapping

        ''' <summary>统一的生物学个体标识</summary>
        Public ReadOnly Property SubjectId As String

        ''' <summary>组学 Id -> 该组学中对应的原始样本 ID</summary>
        Public ReadOnly Property OmicsSample As New Dictionary(Of String, String)

        Public Sub New(subjectId As String)
            _SubjectId = subjectId
        End Sub

        Public Overrides Function ToString() As String
            Return $"{SubjectId}: {String.Join(", ", OmicsSample.Select(Function(kv) $"{kv.Key}={kv.Value}"))}"
        End Function

    End Class
End Namespace
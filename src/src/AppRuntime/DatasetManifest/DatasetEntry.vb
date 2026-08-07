Namespace AppRuntime.Manifest

    ''' <summary>数据集定义文件中 datasets 数组的单个元素</summary>
    Public Class DatasetEntry

        ''' <summary>组学标识，须唯一。同时作为样本对齐宽表中该组学对应的列名。</summary>
        Public Property id As String

        ''' <summary>组学类型，例如 transcriptome / proteome / metabolome / lipidome</summary>
        Public Property type As String

        ''' <summary>中文展示名称，例如“肝脏转录组”</summary>
        Public Property label As String

        ''' <summary>表达矩阵 CSV 路径（必需）</summary>
        Public Property expression As String

        ''' <summary>该组学专属的分子注释表 CSV 路径</summary>
        Public Property annotation As String

        ''' <summary>该组学的样本元数据 CSV 路径</summary>
        Public Property sampleinfo As String

        ''' <summary>数据单位，例如 TPM / peak area</summary>
        Public Property unit As String

        Public Overrides Function ToString() As String
            Return $"[{id}] {label} <- {expression}"
        End Function

    End Class
End Namespace
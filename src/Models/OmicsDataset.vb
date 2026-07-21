Imports Microsoft.VisualBasic.Serialization.JSON

''' <summary>
''' 表示单个组学数据集的描述信息，包括表达矩阵、注释表、样本元数据等。
''' 对于多组学分析，会存在多个 OmicsDataset 实例。
''' </summary>
Public Class OmicsDataset

    ''' <summary>组学类型，例如 rna / protein / metabolite / lipid</summary>
    Public Property OmicsType As String = ""

    ''' <summary>表达矩阵 CSV 文件路径（行为分子，列为样本）</summary>
    Public Property ExpressionFile As String = ""

    ''' <summary>分子注释表 CSV 文件路径</summary>
    Public Property AnnotationFile As String = ""

    ''' <summary>样本元数据 CSV 文件路径</summary>
    Public Property SampleInfoFile As String = ""

    ''' <summary>表达矩阵文件名（不含扩展名），用于多组学场景下匹配样本元数据</summary>
    Public ReadOnly Property MatrixName As String
        Get
            If String.IsNullOrEmpty(ExpressionFile) Then Return ""
            Return Path.GetFileNameWithoutExtension(ExpressionFile)
        End Get
    End Property

    ''' <summary>样本 ID 列表（从表达矩阵第一行读取）</summary>
    Public Property SampleIDs As List(Of String) = New List(Of String)()

    ''' <summary>分子 ID 列表（从表达矩阵第一列读取）</summary>
    Public Property MoleculeIDs As List(Of String) = New List(Of String)()

    Public Function ToJson() As String
        Return Me.GetJson
    End Function

End Class
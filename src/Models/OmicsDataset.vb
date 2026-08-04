Imports Microsoft.VisualBasic.Serialization.JSON

''' <summary>
''' 表示单个组学数据集的描述信息，包括表达矩阵、注释表、样本元数据等。
''' 对于多组学分析，会存在多个 OmicsDataset 实例。
''' </summary>
Public Class OmicsDataset

    ''' <summary>
    ''' 数据集的稳定主键标识，例如 rna / metab。
    ''' 在多组学场景下用于中间产物文件命名、样本对齐宽表的列名以及注释表的来源标识。
    ''' 由 --dataset 定义文件中的 id 字段提供；传统参数模式下回退为表达矩阵文件名。
    ''' </summary>
    Public Property Id As String = ""

    ''' <summary>组学类型，例如 rna / protein / metabolite / lipid</summary>
    Public Property OmicsType As String = ""

    ''' <summary>该组学的中文展示名称，例如“肝脏转录组”（可选）</summary>
    Public Property Label As String = ""

    ''' <summary>数据单位，例如 TPM / peak area（可选）</summary>
    Public Property Unit As String = ""

    ''' <summary>
    ''' 表达矩阵 CSV 文件路径（行为分子，列为样本）。
    ''' 多组学样本对齐完成后，该属性会被重定向到工作区中对齐后的新矩阵。
    ''' </summary>
    Public Property ExpressionFile As String = ""

    ''' <summary>样本元数据 CSV 文件路径。样本对齐后同样会重定向到对齐后的新文件。</summary>
    Public Property SampleInfoFile As String = ""

    ''' <summary>该组学专属的分子注释表 CSV 文件路径</summary>
    Public Property AnnotationFile As String = ""

    ''' <summary>该组学专属注释表的解析结果</summary>
    Public Property AnnotationContent As Molecule()

    ''' <summary>用户最初提供的表达矩阵路径，用于日志与溯源（对齐后 ExpressionFile 会被改写）</summary>
    Public Property SourceExpressionFile As String = ""

    ''' <summary>用户最初提供的样本元数据路径，用于日志与溯源</summary>
    Public Property SourceSampleInfoFile As String = ""

    ''' <summary>表达矩阵文件名（不含扩展名），用于多组学场景下匹配样本元数据</summary>
    Public ReadOnly Property MatrixName As String
        Get
            If String.IsNullOrEmpty(ExpressionFile) Then Return ""
            Return Path.GetFileNameWithoutExtension(ExpressionFile)
        End Get
    End Property

    ''' <summary>
    ''' 供提示词与报告使用的展示名称：优先使用 Label，其次 Id，最后回退到组学类型。
    ''' </summary>
    Public ReadOnly Property DisplayName As String
        Get
            If Not String.IsNullOrEmpty(Label) Then Return Label
            If Not String.IsNullOrEmpty(Id) Then Return Id
            Return OmicsType
        End Get
    End Property

    ''' <summary>样本 ID 列表（从表达矩阵第一行读取）</summary>
    Public Property SampleIDs As String()

    ''' <summary>分子 ID 列表（从表达矩阵第一列读取）</summary>
    Public Property MoleculeIDs As String()

    ''' <summary>样本对齐后该组学保留的 subject_id 列表（与对齐矩阵的列顺序一致）</summary>
    Public Property SubjectIDs As String()

    ''' <summary>该数据集的表达矩阵是否已完成跨组学样本对齐重写</summary>
    Public Property IsAligned As Boolean = False

    ''' <summary>
    ''' 该数据集在工作区 tmp 目录下的预处理产物文件名（不含目录），
    ''' 按数据集 Id 区分，避免多组学场景下互相覆盖。
    ''' </summary>
    Public ReadOnly Property PreprocessedFileName As String
        Get
            Return $"preprocessed_{If(String.IsNullOrEmpty(Id), MatrixName, Id)}.csv"
        End Get
    End Property

    Public Overrides Function ToString() As String
        Return $"[{Id}] {DisplayName} ({OmicsType})"
    End Function

    Public Function ToJson() As String
        Return Me.GetJson
    End Function

End Class

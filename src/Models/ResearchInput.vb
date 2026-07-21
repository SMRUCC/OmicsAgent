' ============================================================================
' 输入数据模型
' ============================================================================
Imports System.IO
Imports System.Text

Namespace Models

    ''' <summary>
    ''' 研究主题描述（来自 research 文件）
    ''' </summary>
    Public Class ResearchDescription
        Public Property RawText As String = ""
        Public Property Topic As String = ""
        Public Property Disease As String = ""
        Public Property Species As String = ""
        Public Property Tissue As String = ""
        Public Property OmicsType As String = ""
        Public Property IsTimeSeries As Boolean = False
        Public Property SpecialNotes As String = ""
    End Class

    ''' <summary>
    ''' 单个组学数据集
    ''' </summary>
    Public Class OmicsDataset
        Public Property Name As String = ""
        Public Property OmicsType As String = ""
        Public Property ExpressionCsvPath As String = ""
        Public Property SampleInfoCsvPath As String = ""
        Public Property MoleculeCount As Integer = 0
        Public Property SampleCount As Integer = 0
        Public Property SampleGroups As New List(Of String)()
        Public Property HasTimeSeries As Boolean = False

        Public Overrides Function ToString() As String
            Return $"{Name} ({OmicsType}, {MoleculeCount} molecules x {SampleCount} samples)"
        End Function
    End Function

    ''' <summary>
    ''' 整体输入参数
    ''' </summary>
    Public Class ResearchInput

        ' ===== 必填 =====
        Public Property Research As ResearchDescription
        Public Property Datasets As New List(Of OmicsDataset)()
        Public Property AnnotationCsvPath As String = ""

        ' ===== 可选 =====
        Public Property ReferencesDir As String = ""
        Public Property WorkspaceDir As String = ""
        Public Property IsMultiOmics As Boolean = False

        ' ===== 派生 =====
        Public ReadOnly Property TmpDir As String
            Get
                Return Path.Combine(WorkspaceDir, "tmp")
            End Get
        End Property

        Public ReadOnly Property ScriptsDir As String
            Get
                Return Path.Combine(WorkspaceDir, "scripts")
            End Get
        End Property

        Public ReadOnly Property KbDir As String
            Get
                Return Path.Combine(WorkspaceDir, "research_kb")
            End Get
        End Property

        Public ReadOnly Property ReportPath As String
            Get
                Return Path.Combine(WorkspaceDir, "report.pdf")
            End Get
        End Property

    End Class

    ''' <summary>
    ''' 差异比较组别设计
    ''' </summary>
    Public Class ComparisonDesign
        Public Property Name As String = ""
        Public Property ControlGroup As String = ""
        Public Property TreatmentGroup As String = ""
        Public Property Covariates As New List(Of String)()
        Public Property BiologicalRationale As String = ""
    End Class

    ''' <summary>
    ''' 分析模块结果
    ''' </summary>
    Public Class ModuleResult
        Public Property ModuleName As String = ""
        Public Property ModuleDir As String = ""
        Public Property ConclusionText As String = ""
        Public Property Tables As New List(Of String)()
        Public Property Figures As New List(Of String)()
        Public Property Scripts As New List(Of String)()
        Public Property Success As Boolean = True
        Public Property ErrorMessage As String = ""
    End Class

End Namespace

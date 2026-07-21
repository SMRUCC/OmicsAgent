

''' <summary>
''' 表示一个差异比较组别的设计，例如 "disease vs control"。
''' </summary>
Public Class ComparisonGroup

    ''' <summary>比较组名称，例如 "Disease_vs_Control"</summary>
    Public Property Name As String = ""

    ''' <summary>对照组样本 ID 列表</summary>
    Public Property ControlSamples As List(Of String) = New List(Of String)()

    ''' <summary>处理组样本 ID 列表</summary>
    Public Property TreatmentSamples As List(Of String) = New List(Of String)()

    ''' <summary>对照组样本分组标签</summary>
    Public Property ControlLabel As String = ""

    ''' <summary>处理组样本分组标签</summary>
    Public Property TreatmentLabel As String = ""

    ''' <summary>该比较的生物学目的描述</summary>
    Public Property BiologicalPurpose As String = ""

End Class
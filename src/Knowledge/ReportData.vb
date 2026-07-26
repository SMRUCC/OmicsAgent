Namespace ReportData

    ''' <summary>报告内容数据模型</summary>
    Public Class ReportContent
        Public Property title As String = ""
        Public Property abstract As String = ""
        Public Property keywords As String()
        Public Property introduction As String = ""
        Public Property materials_methods As String = ""
        Public Property results_sections As ResultSection()
        Public Property discussion As String = ""
        Public Property conclusion As String = ""
    End Class

    Public Class ResultSection
        Public Property module_index As Integer
        Public Property title As String = ""
        Public Property content As String = ""
        Public Property figure_tables As TableFigureCaption()
    End Class

    Public Class TableFigureCaption
        Public Property file As String = ""
        Public Property type As String
        Public Property fields As String()
        Public Property caption_cn As String = ""
        Public Property caption_en As String = ""
    End Class

End Namespace

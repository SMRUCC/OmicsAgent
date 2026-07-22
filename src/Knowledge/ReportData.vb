Namespace ReportData

    ''' <summary>报告内容数据模型</summary>
    Public Class ReportContent
        Public Property Title As String = ""
        Public Property Abstract As String = ""
        Public Property Keywords As List(Of String) = New List(Of String)()
        Public Property Introduction As String = ""
        Public Property MaterialsMethods As String = ""
        Public Property ResultsSections As List(Of ResultSection) = New List(Of ResultSection)()
        Public Property Discussion As String = ""
        Public Property Conclusion As String = ""
    End Class

    Public Class ResultSection
        Public Property ModuleIndex As Integer
        Public Property Title As String = ""
        Public Property Content As String = ""
        Public Property FigureCaptions As List(Of FigureCaption) = New List(Of FigureCaption)()
        Public Property TableCaptions As List(Of TableCaption) = New List(Of TableCaption)()
    End Class

    Public Class FigureCaption
        Public Property File As String = ""
        Public Property CaptionCn As String = ""
        Public Property CaptionEn As String = ""
    End Class

    Public Class TableCaption
        Public Property File As String = ""
        Public Property CaptionCn As String = ""
        Public Property CaptionEn As String = ""
    End Class

End Namespace

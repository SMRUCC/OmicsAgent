Imports Microsoft.VisualBasic.MIME.application.json
Imports Microsoft.VisualBasic.MIME.application.json.Javascript
Imports Microsoft.VisualBasic.MIME.application.json.LenientJson

Public Class SheetAnnotations

    Public Property module_index As Integer
    Public Property module_name As String
    Public Property output_dir As String
    Public Property goal As String
    Public Property xlsx_file As String
    Public Property sheets As Sheet()

    Public Class Sheet

        Public Property csv As String
        Public Property sheet_name As String
        Public Property annotation As String

    End Class

    ''' <summary>
    ''' get json string of this data model, the <see cref="UserDataTablesModule.GenerateGoalAndAnnotationsForGroupAsync"/> is relay on this method
    ''' </summary>
    ''' <returns></returns>
    Public Overrides Function ToString() As String
        Return Me.GetJson
    End Function

    Public Shared Function ParseJSON(jsonstr As String) As SheetAnnotations
        Dim json As JsonElement = LenientJsonParser.ParseJSON(jsonstr)

        If Not TypeOf json Is JsonObject Then
            Return Nothing
        Else
            Return json.CreateObject(Of SheetAnnotations)(decodeMetachar:=False)
        End If
    End Function

End Class

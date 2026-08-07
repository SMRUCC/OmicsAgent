Imports Microsoft.VisualBasic.Serialization.JSON

Module JsonMsg

    Public Function [error](msg As String) As String
        Return New Dictionary(Of String, String) From {{"error", msg}}.GetJson
    End Function
End Module

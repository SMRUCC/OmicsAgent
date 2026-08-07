Imports Microsoft.VisualBasic.Data.Framework

Public Class Molecule

    Public Property id As String
    Public Property name As String
    Public Property type As String
    Public Property kegg As String

    Public Shared Function ReadCsv(filepath As String) As IEnumerable(Of Molecule)
        Return filepath.LoadCsv(Of Molecule)
    End Function

End Class

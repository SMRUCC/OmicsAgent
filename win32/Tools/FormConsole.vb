Imports Microsoft.VisualBasic.ApplicationServices

Public Class FormConsole

    Public Property workspace As String

    Private Sub FormConsole_Load(sender As Object, e As EventArgs) Handles Me.Load
        If workspace.StringEmpty Then
            Call WebViewConsole1.StartProcess("cmd", Nothing)
        Else
            Call WebViewConsole1.StartProcess("cmd", $"/k cd /d {workspace.CLIPath}")
        End If
    End Sub
End Class
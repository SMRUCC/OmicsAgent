Public Class FormOmicsAgent

    Public Property workspace As String

    Private Sub FormOmicsAgent_Load(sender As Object, e As EventArgs) Handles Me.Load
        TabText = $"Agent [{workspace.BaseName} - {workspace.ParentPath}]"
        WebViewConsole1.StartProcess(App.HOME & "/research.exe", Nothing)
    End Sub
End Class
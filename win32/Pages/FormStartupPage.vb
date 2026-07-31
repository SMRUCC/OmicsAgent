Imports Galaxy.Workbench

Public Class FormStartupPage

    Private Async Sub FormStartupPage_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
    End Sub
End Class
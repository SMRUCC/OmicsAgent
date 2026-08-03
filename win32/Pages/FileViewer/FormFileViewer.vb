Imports Galaxy.Workbench
Imports Microsoft.Web.WebView2.Core

Public Class FormFileViewer

    Public Property port As Integer

    Dim ready As Boolean = False

    Public Async Function CheckReady() As Task
        If ready Then
            Return
        End If

        Do While Not ready
            Await Task.Delay(100)
        Loop
    End Function

    Private Async Sub FormFileViewer_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
    End Sub

    Public Async Function ViewFile(rel As String) As Task
        Await WebView21.ExecuteScriptAsync($"openFile('{rel}');")
    End Function

    Private Sub WebView21_CoreWebView2InitializationCompleted(sender As Object, e As CoreWebView2InitializationCompletedEventArgs) Handles WebView21.CoreWebView2InitializationCompleted
        Call WebView21.CoreWebView2.Navigate($"http://localhost:{Workbench.port}/viewer.html")
    End Sub

    Private Async Sub WebView21_NavigationCompleted(sender As Object, e As CoreWebView2NavigationCompletedEventArgs) Handles WebView21.NavigationCompleted
        Await WebView21.ExecuteScriptAsync($"run('http://localhost:{port}/');")
        Await WebView21.ExecuteScriptAsync("document.getElementById('topbar').style.display = 'none';")

        ready = True
    End Sub
End Class
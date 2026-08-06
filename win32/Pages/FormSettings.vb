Imports Galaxy.Workbench
Imports Microsoft.Web.WebView2.Core

Public Class FormSettings

    Private Async Sub FormSettings_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
    End Sub

    Private Sub WebView21_CoreWebView2InitializationCompleted(sender As Object, e As CoreWebView2InitializationCompletedEventArgs) Handles WebView21.CoreWebView2InitializationCompleted
        WebView21.CoreWebView2.Navigate($"http://127.0.0.1:{Workbench.port}/settings.html")
    End Sub

    Private Sub WebView21_NavigationCompleted(sender As Object, e As CoreWebView2NavigationCompletedEventArgs) Handles WebView21.NavigationCompleted

    End Sub
End Class
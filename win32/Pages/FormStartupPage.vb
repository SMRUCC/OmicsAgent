Imports Galaxy.Workbench
Imports Microsoft.Web.WebView2.Core
Imports OmicsWorks.JavaScript

Public Class FormStartupPage

    Private Async Sub FormStartupPage_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
    End Sub

    Private Sub WebView21_NavigationCompleted(sender As Object, e As CoreWebView2NavigationCompletedEventArgs) Handles WebView21.NavigationCompleted

    End Sub

    Private Sub WebView21_CoreWebView2InitializationCompleted(sender As Object, e As CoreWebView2InitializationCompletedEventArgs) Handles WebView21.CoreWebView2InitializationCompleted
        WebView21.CoreWebView2.AddHostObjectToScript(BasePage.HostObject, New StartupPage(Me))
        Call WebView21.CoreWebView2.Navigate($"http://127.0.0.1:{Workbench.port}/index.html")
    End Sub
End Class
Imports Galaxy.Workbench
Imports Microsoft.Web.WebView2.Core
Imports OmicsWorks.JavaScript

Public Class FormDataSetEditor

    Public Property workspace As String

    Private Async Sub FormDataSetEditor_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
    End Sub

    Private Sub WebView21_CoreWebView2InitializationCompleted(sender As Object, e As CoreWebView2InitializationCompletedEventArgs) Handles WebView21.CoreWebView2InitializationCompleted
        Call WebView21.CoreWebView2.AddHostObjectToScript(BasePage.HostObject, New StartupPage(Me))
        Call WebView21.CoreWebView2.Navigate($"http://127.0.0.1:{Workbench.port}/dataset.html")
    End Sub
End Class

Imports Galaxy.Workbench
Imports Microsoft.Web.WebView2.Core

Public Class FormHtmlViewer

    Public Property URL As String

    Private Async Sub FormHtmlViewer_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
    End Sub

    Private Sub WebView21_CoreWebView2InitializationCompleted(sender As Object, e As CoreWebView2InitializationCompletedEventArgs) Handles WebView21.CoreWebView2InitializationCompleted
        WebView21.CoreWebView2.Navigate(URL)
    End Sub
End Class
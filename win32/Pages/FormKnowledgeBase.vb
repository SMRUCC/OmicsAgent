Imports Fluteway
Imports Galaxy.Workbench
Imports Microsoft.Web.WebView2.Core
Imports RibbonLib.Interop

Public Class FormKnowledgeBase

    Shared ReadOnly btnOpenKBLib As RibbonEventBinding

    Shared Sub New()
        btnOpenKBLib = New RibbonEventBinding(Ribbon.BtnOpenKBLib)
    End Sub

    Dim http As HttpServices

    Public Property kb_dir As String

    Private Async Sub FormKnowledgeBase_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)

        If kb_dir.DirectoryExists Then
            http = New HttpServices(kb_dir)
            http.StartHttp()
        Else
            Call CommonRuntime.Warning("Invalid knowledge base directory config!")
        End If

        Call AvtivateRibbon()
    End Sub

    Private Async Function openKBLib() As Task
        Await WebView21.CoreWebView2.ExecuteScriptAsync("showSummary();")
    End Function

    Private Sub AvtivateRibbon()
        Ribbon.MenuKBLib.ContextAvailable = ContextAvailability.Active

        btnOpenKBLib.Addhandler(Async Sub() Await openKBLib())
    End Sub

    Private Async Sub WebView21_NavigationCompleted(sender As Object, e As CoreWebView2NavigationCompletedEventArgs) Handles WebView21.NavigationCompleted
        ' Await WebView21.CoreWebView2.ExecuteScriptAsync("")
    End Sub

    Private Sub WebView21_CoreWebView2InitializationCompleted(sender As Object, e As CoreWebView2InitializationCompletedEventArgs) Handles WebView21.CoreWebView2InitializationCompleted
        WebView21.CoreWebView2.Navigate($"http://127.0.0.1:{Workbench.port}/kb.html")
    End Sub
End Class
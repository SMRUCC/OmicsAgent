Imports Galaxy.Workbench
Imports Microsoft.Web.WebView2.Core
Imports RibbonLib.Interop

Public Class FormKnowledgeBase

    Shared ReadOnly btnOpenKBLib As RibbonEventBinding
    Shared ReadOnly btnToggleTheme As RibbonEventBinding

    Shared Sub New()
        btnOpenKBLib = New RibbonEventBinding(Ribbon.BtnOpenKBLib)
        btnToggleTheme = New RibbonEventBinding(Ribbon.ButtonToggleTheme)
    End Sub

    Public Property kb_dir As String
    Public Property base As FormResearchWork

    Private Async Sub FormKnowledgeBase_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
        Call AvtivateRibbon()

        Dim jsons = kb_dir.EnumerateFiles("*.json").Where(Function(file) file.BaseName.IsPattern("per_doc_\d+")).Select(Function(file) file.FileName).ToArray
        Call jsons.SaveTo($"{kb_dir}/files.txt")
    End Sub

    Private Async Function openKBLib() As Task
        Await WebView21.CoreWebView2.ExecuteScriptAsync("showSummary();")
    End Function

    Private Async Function toggleTheme() As Task
        Await WebView21.CoreWebView2.ExecuteScriptAsync("toggleTheme();")
    End Function

    Private Sub AvtivateRibbon()
        Ribbon.MenuKBLib.ContextAvailable = ContextAvailability.Active

        btnOpenKBLib.Addhandler(Async Sub() Await openKBLib())
        btnToggleTheme.Addhandler(Async Sub() Await toggleTheme())
    End Sub

    Private Async Sub WebView21_NavigationCompleted(sender As Object, e As CoreWebView2NavigationCompletedEventArgs) Handles WebView21.NavigationCompleted
        Await WebView21.CoreWebView2.ExecuteScriptAsync("document.getElementById('topbar').style.display = 'none';")
        Await WebView21.CoreWebView2.ExecuteScriptAsync($"run('http://127.0.0.1:{base.port}/research_kb/');")
    End Sub

    Private Sub WebView21_CoreWebView2InitializationCompleted(sender As Object, e As CoreWebView2InitializationCompletedEventArgs) Handles WebView21.CoreWebView2InitializationCompleted
        WebView21.CoreWebView2.Navigate($"http://127.0.0.1:{Workbench.port}/kb.html")
    End Sub
End Class
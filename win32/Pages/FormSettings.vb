Imports Galaxy.Workbench
Imports Microsoft.VisualBasic.Serialization.JSON
Imports Microsoft.Web.WebView2.Core
Imports OmicsWorks.JavaScript
Imports OmicsWorks.Settings

Public Class FormSettings

    Private Async Sub FormSettings_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
    End Sub

    Private Sub WebView21_CoreWebView2InitializationCompleted(sender As Object, e As CoreWebView2InitializationCompletedEventArgs) Handles WebView21.CoreWebView2InitializationCompleted
        WebView21.CoreWebView2.AddHostObjectToScript(BasePage.HostObject, New SettingsPage(Me))
        WebView21.CoreWebView2.Navigate($"http://127.0.0.1:{Workbench.port}/settings.html")
    End Sub

    Private Async Sub WebView21_NavigationCompleted(sender As Object, e As CoreWebView2NavigationCompletedEventArgs) Handles WebView21.NavigationCompleted
        Await WebView21.ExecuteScriptAsync("document.getElementById('btn-group').style.display = 'none';")
        Await WebView21.ExecuteScriptAsync($"loadFromText({Workbench.config.ToJSON.GetJson})")
    End Sub

    Friend Async Function SaveSettings(json As String) As Task
        Dim config As AppConfig = Await Task.FromResult(AppConfig.FromJSON(json))
        Call config.Save()
        Call Workbench.LoadConfig()
    End Function
End Class
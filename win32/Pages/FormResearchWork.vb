Imports Fluteway
Imports Galaxy.Workbench
Imports Microsoft.Web.WebView2.Core
Imports RibbonLib.Interop

Public Class FormResearchWork

    Shared ReadOnly btnOpenKb As RibbonEventBinding
    Shared ReadOnly btnDataset As RibbonEventBinding
    Shared ReadOnly btnRun As RibbonEventBinding

    Shared Sub New()
        btnOpenKb = New RibbonEventBinding(Ribbon.ButtonOpenKb)
        btnDataset = New RibbonEventBinding(Ribbon.ButtonDataset)

        btnRun = New RibbonEventBinding(Ribbon.ButtonStart)
    End Sub

    Public ReadOnly Property port As Integer
        Get
            If http Is Nothing Then
                Return -1
            Else
                Return http.port
            End If
        End Get
    End Property

    Public Property Workspace As String

    Dim WithEvents http As HttpServices
    Dim WithEvents agentContainer As FormOmicsAgent

    Private Sub OpenKBPage()
        Call RibbonMenu.OpenKbPage(dir:=$"{Workspace}/research_kb/", Me)
    End Sub

    Private Sub OpenDatasetPage()
        Call CommonRuntime.ShowDocument(New FormDataSetEditor With {.workspace = Workspace})
    End Sub

    Private Sub RunAgentTask()
        If agentContainer Is Nothing Then
            agentContainer = New FormOmicsAgent With {
                .workspace = Workspace
            }
        End If

        Call CommonRuntime.ShowDocument(agentContainer)
    End Sub

    Private Sub ActiveRibbonMenu()
        Ribbon.MenuResearchWork.ContextAvailable = ContextAvailability.Active

        Call btnOpenKb.Addhandler(AddressOf OpenKBPage)
        Call btnDataset.Addhandler(AddressOf OpenDatasetPage)
        Call btnRun.Addhandler(AddressOf RunAgentTask)

        Call RibbonMenu.OpenFolder(Workspace)
    End Sub

    Private Async Sub FormResearchWork_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
        Call ActiveRibbonMenu()
        http = New HttpServices(Workspace)
        http.StartHttp()

        Dim dirs = $"{Workspace}/analysis".ListDirectory.Select(Function(d) d.BaseName).ToArray

        Call dirs.SaveTo($"{Workspace}/tmp/modules.txt")
    End Sub

    Private Sub WebView21_CoreWebView2InitializationCompleted(sender As Object, e As CoreWebView2InitializationCompletedEventArgs) Handles WebView21.CoreWebView2InitializationCompleted
        ' Call WebView21.CoreWebView2.AddHostObjectToScript(BasePage.HostObject, New StartupPage(Me))
        Call WebView21.CoreWebView2.Navigate($"http://127.0.0.1:{Workbench.port}/analysis.html")
    End Sub

    Private Async Sub WebView21_NavigationCompleted(sender As Object, e As CoreWebView2NavigationCompletedEventArgs) Handles WebView21.NavigationCompleted
        Await WebView21.ExecuteScriptAsync($"run('http://127.0.0.1:{port}/');")
    End Sub
End Class
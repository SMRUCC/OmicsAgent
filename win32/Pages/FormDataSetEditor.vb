Imports System.Text.Json
Imports Galaxy.Workbench
Imports Microsoft.VisualBasic.Serialization.JSON
Imports Microsoft.Web.WebView2.Core
Imports OmicsWorks.JavaScript
Imports RibbonLib.Interop

Public Class FormDataSetEditor

    Public Property workspace As String

    Shared btnLoad As RibbonEventBinding
    Shared btnSave As RibbonEventBinding
    Shared btnSaveAs As RibbonEventBinding

    Shared btnSingleMultiple As RibbonEventBinding

    Shared btnPreview As RibbonEventBinding
    Shared btnTheme As RibbonEventBinding

    Private ReadOnly Property Dataset_json As String
        Get
            Return Dataset_file.ReadAllText(throwEx:=False)
        End Get
    End Property

    Private ReadOnly Property Dataset_file As String
        Get
            Return $"{workspace}/tmp/dataset.json"
        End Get
    End Property

    Shared Sub New()
        btnLoad = New RibbonEventBinding(Ribbon.ButtonLoadDataSet)
        btnSave = New RibbonEventBinding(Ribbon.ButtonSaveDataSet)
        btnSaveAs = New RibbonEventBinding(Ribbon.ButtonSaveAsDataSet)

        btnSingleMultiple = New RibbonEventBinding(Ribbon.ButtonDataSetToggleOmics)

        btnPreview = New RibbonEventBinding(Ribbon.ButtonPreviewDataset)
        btnTheme = New RibbonEventBinding(Ribbon.ButtonDataSetEditorToggleTheme)
    End Sub

    Private Async Sub FormDataSetEditor_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
        Call ActivateMenu()
    End Sub

    Private Sub ActivateMenu()
        Ribbon.MenuDataSet.ContextAvailable = ContextAvailability.Active

        btnLoad.Addhandler(Async Sub() Await LoadDataset())
        btnSave.Addhandler(Async Sub() Await SaveDataset())
        btnSaveAs.Addhandler(Async Sub() Await SaveAsDataset())

        btnSingleMultiple.Addhandler(Async Sub() Await ToggleOmics())

        btnPreview.Addhandler(Async Sub() Await GetPreviewJSON())
        btnTheme.Addhandler(Async Sub() Await ToggleTheme())
    End Sub

    Private Async Function LoadDataset() As Task
        Using file As New OpenFileDialog With {.Filter = "Dataset manifest(*.json)|*.json"}
            If file.ShowDialog = DialogResult.OK Then
                Await WebView21.ExecuteScriptAsync($"loadManifestJson({file.FileName.ReadAllText.GetJson});")
            End If
        End Using
    End Function

    Private Async Function SaveDataset() As Task
        Dim json As String = Await WebView21.ExecuteScriptAsync("getManifestJson()")
        Call json.LoadJSON(Of String).SaveTo(Dataset_file)
    End Function

    Private Async Function SaveAsDataset() As Task
        Using file As New SaveFileDialog With {.Filter = "Dataset manifest(*.json)|*.json"}
            If file.ShowDialog = DialogResult.OK Then
                Dim json As String = Await WebView21.ExecuteScriptAsync("getManifestJson()")
                Call json.LoadJSON(Of String).SaveTo(file.FileName)
            End If
        End Using
    End Function

    Private Async Function ToggleOmics() As Task
        Await WebView21.ExecuteScriptAsync("toggleMode();")
    End Function

    Private Async Function GetPreviewJSON() As Task
        Await WebView21.ExecuteScriptAsync("document.getElementById('previewBtn').click();")
    End Function

    Private Async Function ToggleTheme() As Task
        Await WebView21.ExecuteScriptAsync("toggleTheme();")
    End Function

    Private Sub WebView21_CoreWebView2InitializationCompleted(sender As Object, e As CoreWebView2InitializationCompletedEventArgs) Handles WebView21.CoreWebView2InitializationCompleted
        Call WebView21.CoreWebView2.AddHostObjectToScript(BasePage.HostObject, New DataSetPage(Me))
        Call WebView21.CoreWebView2.Navigate($"http://127.0.0.1:{Workbench.port}/dataset.html")
    End Sub

    Private Async Sub WebView21_NavigationCompleted(sender As Object, e As CoreWebView2NavigationCompletedEventArgs) Handles WebView21.NavigationCompleted
        Await WebView21.ExecuteScriptAsync("document.getElementById('btn-group').style.display = 'none';")

        If Not Dataset_json.StringEmpty(, True) Then
            ' 1. 构造一个匿名对象，包含需要传递的数据
            Dim payload = New With {
                .type = "loadFile",
                .text = Dataset_json
            }
            ' 2. 序列化为 JSON 字符串
            Dim jsonPayload As String = JsonSerializer.Serialize(payload)

            ' 3. 通过消息通道发送（不会作为脚本执行，性能极高且安全）
            WebView21.CoreWebView2.PostWebMessageAsJson(jsonPayload)
        End If
    End Sub
End Class

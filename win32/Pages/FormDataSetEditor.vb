Imports System.Text.Json
Imports Galaxy.Workbench
Imports Microsoft.Web.WebView2.Core
Imports OmicsWorks.JavaScript
Imports RibbonLib.Interop

Public Class FormDataSetEditor

    Public Property workspace As String

    Private ReadOnly Property Dataset_json As String
        Get
            Return $"{workspace}/tmp/dataset.json".ReadAllText(throwEx:=False)
        End Get
    End Property

    Private Async Sub FormDataSetEditor_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
        Call ActivateMenu()
    End Sub

    Private Sub ActivateMenu()
        Ribbon.MenuDataSet.ContextAvailable = ContextAvailability.Active
    End Sub

    Private Sub WebView21_CoreWebView2InitializationCompleted(sender As Object, e As CoreWebView2InitializationCompletedEventArgs) Handles WebView21.CoreWebView2InitializationCompleted
        Call WebView21.CoreWebView2.AddHostObjectToScript(BasePage.HostObject, New DataSetPage(Me))
        Call WebView21.CoreWebView2.Navigate($"http://127.0.0.1:{Workbench.port}/dataset.html")
    End Sub

    Private Sub WebView21_NavigationCompleted(sender As Object, e As CoreWebView2NavigationCompletedEventArgs) Handles WebView21.NavigationCompleted
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

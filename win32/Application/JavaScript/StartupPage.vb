Imports System.Runtime.InteropServices

Namespace JavaScript

    ''' <summary>
    ''' WebView2 宿主对象：供前端 dataset.html 等页面调用，完成本地文件系统交互。
    ''' 注册名称为 <see cref="BasePage.HostObject"/> = "win32"，JS 侧通过
    ''' chrome.webview.hostObjects.win32 异步访问。
    ''' </summary>
    <ClassInterface(ClassInterfaceType.AutoDual)>
    <ComVisible(True)>
    Public Class StartupPage : Inherits BasePage

        Public Sub New(owner As Form)
            MyBase.New(owner)
        End Sub

        Public Async Function openVennTool() As Task(Of Boolean)
            Call RibbonMenu.OpenJVennTool()
            Return Await Task.FromResult(True)
        End Function

        Public Async Function openSettings() As Task(Of Boolean)
            Call RibbonMenu.OpenSettings()
            Return Await Task.FromResult(True)
        End Function

        Public Async Function openFolder() As Task(Of Boolean)
            Call RibbonMenu.OpenFolder()
            Return Await Task.FromResult(True)
        End Function

        Public Async Function openResearch() As Task(Of Boolean)
            Call RibbonMenu.OpenResearch()
            Return Await Task.FromResult(True)
        End Function
    End Class
End Namespace

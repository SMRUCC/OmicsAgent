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
    End Class
End Namespace

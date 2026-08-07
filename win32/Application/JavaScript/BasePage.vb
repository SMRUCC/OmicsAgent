Imports System.Runtime.InteropServices
Imports System.Text
Imports System.Text.Json

Namespace JavaScript

    <ClassInterface(ClassInterfaceType.AutoDual)>
    <ComVisible(True)>
    Public Class BasePage

        Public Const HostObject As String = "win32"

        ''' <summary>WinForms FileDialog.Filter 的兜底值。</summary>
        Public Const AllFilesFilter As String = "所有文件|*.*"

        ''' <summary>宿主窗口，用于把文件对话框调度回 UI 线程并设置其父窗口。</summary>
        Protected ReadOnly _owner As Form

        ''' <summary>
        ''' 序列化选项：忽略 Nothing 成员，使成功响应不出现多余的 "error": null。
        ''' 属性名保持原样（已是小写），以匹配 JS 侧的 { ok, data, error } 契约。
        ''' </summary>
        Protected Shared ReadOnly _jsonOptions As New JsonSerializerOptions With {
            .DefaultIgnoreCondition = Serialization.JsonIgnoreCondition.WhenWritingNull,
            .Encoder = Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
        }

        ''' <summary>
        ''' 带窗口句柄构造：对话框会始终在该窗口所在 UI 线程上弹出。
        ''' 推荐 dataset.html 宿主 FormDataSetEditor 使用。
        ''' </summary>
        Public Sub New(owner As Form)
            _owner = owner
        End Sub

        ''' <summary>
        ''' 文件对话框必须在 UI 线程上弹出；JS 侧的 COM 异步代理调用可能来自
        ''' 非 UI 线程，因此统一在此调度。
        ''' </summary>
        Protected Function RunOnUi(Of T)(task As Func(Of T)) As T
            If _owner IsNot Nothing AndAlso Not _owner.IsDisposed AndAlso _owner.InvokeRequired Then
                Return DirectCast(_owner.Invoke(task), T)
            Else
                Return task()
            End If
        End Function
    End Class
End Namespace
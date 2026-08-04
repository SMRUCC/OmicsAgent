Imports System.IO
Imports System.Runtime.InteropServices
Imports System.Text
Imports System.Text.Json
Imports OmicsWorks.CsvUtils

Namespace JavaScript

    ''' <summary>
    ''' WebView2 宿主对象：供前端 dataset.html 等页面调用，完成本地文件系统交互。
    ''' 注册名称为 <see cref="BasePage.HostObject"/> = "win32"，JS 侧通过
    ''' chrome.webview.hostObjects.win32 异步访问。
    ''' </summary>
    <ClassInterface(ClassInterfaceType.AutoDual)>
    <ComVisible(True)>
    Public Class StartupPage

        Private ReadOnly _owner As Form
        Private Shared ReadOnly _jsonOptions As New JsonSerializerOptions() With {
            .PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        }

        ''' <summary>无参构造：由 FormStartupPage / FormResearchWork 等既有页面使用。</summary>
        Public Sub New()
            _owner = Form.ActiveForm
        End Sub

        ''' <summary>
        ''' 带窗口句柄构造：对话框会始终在该窗口所在 UI 线程上弹出。
        ''' 推荐 dataset.html 宿主 FormDataSetEditor 使用。
        ''' </summary>
        Public Sub New(owner As Form)
            _owner = owner
        End Sub

        ''' <summary>
        ''' 打开文件选择对话框。
        ''' 入参 JSON：{ "title": "...", "filter": "CSV 文件|*.csv|所有文件|*.*", "multiselect": false, "initialDir": "..." }
        ''' 返回 JSON：{ "ok": true, "data": { "paths": ["C:\\..."] } }
        ''' </summary>
        Public Function OpenFileDialog(optionsJson As String) As String
            Return RunOnUi(Function()
                               Try
                                   Dim opts = ParseOptions(optionsJson)
                                   Using dlg As New OpenFileDialog()
                                       dlg.Title = If(opts.GetOpt("title", ""), "选择文件")
                                       SetFilter(dlg, If(opts.GetOpt("filter", ""), "所有文件|*.*"))
                                       dlg.Multiselect = opts.GetOpt("multiselect", False)
                                       dlg.InitialDirectory = NormalizeInitialDir(opts.GetOpt("initialDir", ""))

                                       If dlg.ShowDialog(_owner) = DialogResult.OK Then
                                           Return Ok(New With { .paths = dlg.FileNames.ToList() })
                                       Else
                                           Return Ok(New With { .paths = New List(Of String)() })
                                       End If
                                   End Using
                               Catch ex As Exception
                                   Return Err(ex.Message)
                               End Try
                           End Function)
        End Function

        ''' <summary>
        ''' 打开保存文件对话框。
        ''' 入参 JSON：{ "title": "...", "filter": "JSON 文件|*.json", "defaultName": "dataset.json", "initialDir": "..." }
        ''' 返回 JSON：{ "ok": true, "data": { "path": "C:\\..." } }
        ''' </summary>
        Public Function SaveFileDialog(optionsJson As String) As String
            Return RunOnUi(Function()
                               Try
                                   Dim opts = ParseOptions(optionsJson)
                                   Using dlg As New SaveFileDialog()
                                       dlg.Title = If(opts.GetOpt("title", ""), "保存文件")
                                       SetFilter(dlg, If(opts.GetOpt("filter", ""), "所有文件|*.*"))
                                       dlg.FileName = If(opts.GetOpt("defaultName", ""), "")
                                       dlg.InitialDirectory = NormalizeInitialDir(opts.GetOpt("initialDir", ""))

                                       If dlg.ShowDialog(_owner) = DialogResult.OK Then
                                           Return Ok(New With { .path = dlg.FileName })
                                       Else
                                           Return Ok(New With { .path = "" })
                                       End If
                                   End Using
                               Catch ex As Exception
                                   Return Err(ex.Message)
                               End Try
                           End Function)
        End Function

        ''' <summary>
        ''' 将文本写入本地文件。
        ''' 入参 JSON：{ "path": "C:\\...", "content": "...", "encoding": "utf-8" }
        ''' 返回 JSON：{ "ok": true, "data": { "path": "C:\\..." } }
        ''' </summary>
        Public Function WriteTextFile(argsJson As String) As String
            Return RunOnUi(Function()
                               Try
                                   Dim args = ParseOptions(argsJson)
                                   Dim path As String = args.GetOpt("path", "")
                                   Dim content As String = args.GetOpt("content", "")
                                   Dim encodingName As String = args.GetOpt("encoding", "utf-8")
                                   If String.IsNullOrWhiteSpace(path) Then Throw New ArgumentException("path 不能为空")

                                   Dim encoding As Encoding = Encoding.UTF8
                                   If Not String.IsNullOrWhiteSpace(encodingName) Then
                                       encoding = Encoding.GetEncoding(encodingName)
                                   End If

                                   File.WriteAllText(path, content, encoding)
                                   Return Ok(New With { .path = path })
                               Catch ex As Exception
                                   Return Err(ex.Message)
                               End Try
                           End Function)
        End Function

        ''' <summary>
        ''' 读取本地文本文件。
        ''' 入参：path 字符串
        ''' 返回 JSON：{ "ok": true, "data": { "content": "...", "path": "..." } }
        ''' </summary>
        Public Function ReadTextFile(path As String) As String
            Return RunOnUi(Function()
                               Try
                                   If String.IsNullOrWhiteSpace(path) Then Throw New ArgumentException("path 不能为空")
                                   Dim content As String = File.ReadAllText(path, Encoding.UTF8)
                                   Return Ok(New With { .content = content, .path = path })
                               Catch ex As Exception
                                   Return Err(ex.Message)
                               End Try
                           End Function)
        End Function

        ''' <summary>
        ''' 读取 CSV 首行表头列名。
        ''' 入参：path 字符串
        ''' 返回 JSON：{ "ok": true, "data": { "columns": ["gene_id", "S1", "S2"] } }
        ''' </summary>
        Public Function ReadCsvHeader(path As String) As String
            Return RunOnUi(Function()
                               Try
                                   If String.IsNullOrWhiteSpace(path) Then Throw New ArgumentException("path 不能为空")
                                   Dim columns As String() = CsvUtils.ReadHeader(path)
                                   Return Ok(New With { .columns = columns.ToList() })
                               Catch ex As Exception
                                   Return Err(ex.Message)
                               End Try
                           End Function)
        End Function

        ''' <summary>
        ''' 检查文件是否存在。
        ''' 入参：path 字符串
        ''' 返回 JSON：{ "ok": true, "data": { "exists": true/false } }
        ''' </summary>
        Public Function FileExists(path As String) As String
            Return RunOnUi(Function()
                               Try
                                   Return Ok(New With { .exists = (Not String.IsNullOrWhiteSpace(path) AndAlso File.Exists(path)) })
                               Catch ex As Exception
                                   Return Err(ex.Message)
                               End Try
                           End Function)
        End Function

#Region "私有辅助"

        ''' <summary>
        ''' 从 JsonElement 或普通 Object 中取值。System.Text.Json 反序列化
        ''' Dictionary(Of String, Object) 时，值类型为 JsonElement，因此需要
        ''' 统一封装转换。
        ''' </summary>
        Private Shared Function GetOpt(Of T)(opts As Dictionary(Of String, Object), key As String, defaultValue As T) As T
            If opts Is Nothing Then Return defaultValue
            If Not opts.ContainsKey(key) Then Return defaultValue

            Dim v As Object = opts(key)
            If TypeOf v Is JsonElement Then
                Dim e As JsonElement = DirectCast(v, JsonElement)
                Select Case GetType(T)
                    Case GetType(String)
                        If e.ValueKind = JsonValueKind.String Then
                            Return CType(CType(e.GetString(), Object), T)
                        End If
                    Case GetType(Boolean)
                        If e.ValueKind = JsonValueKind.True Then Return CType(CType(True, Object), T)
                        If e.ValueKind = JsonValueKind.False Then Return CType(CType(False, Object), T)
                End Select
            ElseIf v IsNot Nothing Then
                Try
                    Return CType(v, T)
                Catch
                End Try
            End If
            Return defaultValue
        End Function

        Private Shared Function ParseOptions(json As String) As Dictionary(Of String, Object)
            If String.IsNullOrWhiteSpace(json) Then Return New Dictionary(Of String, Object)()
            Try
                Return JsonSerializer.Deserialize(Of Dictionary(Of String, Object))(json, _jsonOptions)
            Catch
                Return New Dictionary(Of String, Object)()
            End Try
        End Function

        Private Shared Sub SetFilter(dlg As FileDialog, filter As String)
            If String.IsNullOrWhiteSpace(filter) Then
                dlg.Filter = "所有文件|*.*"
            Else
                dlg.Filter = filter
            End If
        End Sub

        Private Shared Function NormalizeInitialDir(dir As String) As String
            If String.IsNullOrWhiteSpace(dir) Then Return ""
            Try
                If Directory.Exists(dir) Then Return dir
                Dim parent = Path.GetDirectoryName(dir)
                If Directory.Exists(parent) Then Return parent
            Catch
                ' 忽略异常，InitialDirectory 非法时 WinForms 会忽略
            End Try
            Return ""
        End Function

        Private Shared Function Ok(data As Object) As String
            Return JsonSerializer.Serialize(New With { .ok = True, .data = data }, _jsonOptions)
        End Function

        Private Shared Function Err(message As String) As String
            Return JsonSerializer.Serialize(New With { .ok = False, .error = message }, _jsonOptions)
        End Function

        Private Function RunOnUi(Of T)(func As Func(Of T)) As T
            If _owner IsNot Nothing AndAlso _owner.InvokeRequired Then
                Return CType(_owner.Invoke(func), T)
            Else
                Return func()
            End If
        End Function

#End Region

    End Class
End Namespace

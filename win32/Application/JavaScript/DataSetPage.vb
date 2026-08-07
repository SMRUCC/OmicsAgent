Imports System.IO
Imports System.Runtime.InteropServices
Imports System.Text
Imports System.Text.Json
Imports OmicsAgent

Namespace JavaScript

    <ClassInterface(ClassInterfaceType.AutoDual)>
    <ComVisible(True)>
    Public Class DataSetPage : Inherits BasePage

        Public Sub New(owner As Form)
            MyBase.New(owner)
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
                                       dlg.Title = OptString(opts, "title", "选择文件")
                                       dlg.Filter = OptString(opts, "filter", AllFilesFilter)
                                       dlg.Multiselect = OptBoolean(opts, "multiselect", False)
                                       dlg.InitialDirectory = NormalizeInitialDir(OptString(opts, "initialDir", ""))

                                       If dlg.ShowDialog(_owner) = DialogResult.OK Then
                                           Return Success(New With {.paths = dlg.FileNames.ToList})
                                       Else
                                           Return Success(New With {.paths = New List(Of String)})
                                       End If
                                   End Using
                               Catch ex As Exception
                                   Return Failure(ex.Message)
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
                                       dlg.Title = OptString(opts, "title", "保存文件")
                                       dlg.Filter = OptString(opts, "filter", AllFilesFilter)
                                       dlg.FileName = OptString(opts, "defaultName", "")
                                       dlg.InitialDirectory = NormalizeInitialDir(OptString(opts, "initialDir", ""))

                                       If dlg.ShowDialog(_owner) = DialogResult.OK Then
                                           Return Success(New With {.path = dlg.FileName})
                                       Else
                                           Return Success(New With {.path = ""})
                                       End If
                                   End Using
                               Catch ex As Exception
                                   Return Failure(ex.Message)
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
                                   Dim path As String = OptString(args, "path", "")
                                   Dim content As String = OptString(args, "content", "")
                                   Dim encodingName As String = OptString(args, "encoding", "utf-8")
                                   If String.IsNullOrWhiteSpace(path) Then
                                       Throw New ArgumentException("path 不能为空")
                                   End If

                                   Dim textEncoding As Encoding = Encoding.UTF8

                                   If Not String.IsNullOrWhiteSpace(encodingName) Then
                                       Try
                                           textEncoding = Encoding.GetEncoding(encodingName)
                                       Catch
                                           textEncoding = Encoding.UTF8
                                       End Try
                                   End If

                                   Call File.WriteAllText(path, content, textEncoding)

                                   Return Success(New With {.path = path})
                               Catch ex As Exception
                                   Return Failure(ex.Message)
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
                                   If String.IsNullOrWhiteSpace(path) Then
                                       Throw New ArgumentException("path 不能为空")
                                   End If

                                   Dim content As String = File.ReadAllText(path, Encoding.UTF8)

                                   Return Success(New With {.content = content, .path = path})
                               Catch ex As Exception
                                   Return Failure(ex.Message)
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
                                   If String.IsNullOrWhiteSpace(path) Then
                                       Throw New ArgumentException("path 不能为空")
                                   End If

                                   Dim columns As String() = CsvUtils.ReadHeader(path)

                                   Return Success(New With {.columns = New List(Of String)(columns)})
                               Catch ex As Exception
                                   Return Failure(ex.Message)
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
                                   Dim exists As Boolean = Not String.IsNullOrWhiteSpace(path) AndAlso File.Exists(path)

                                   Return Success(New With {.exists = exists})
                               Catch ex As Exception
                                   Return Failure(ex.Message)
                               End Try
                           End Function)
        End Function

#Region "私有辅助"

        ''' <summary>
        ''' 解析 JS 侧传入的参数对象。System.Text.Json 反序列化
        ''' Dictionary(Of String, Object) 时，值类型为 JsonElement。
        ''' </summary>
        Private Shared Function ParseOptions(json As String) As Dictionary(Of String, JsonElement)
            If String.IsNullOrWhiteSpace(json) Then
                Return New Dictionary(Of String, JsonElement)
            End If

            Try
                Dim parse = JsonSerializer.Deserialize(Of Dictionary(Of String, JsonElement))(json)
                Return If(parse, New Dictionary(Of String, JsonElement))
            Catch
                ' 入参非法时返回空字典，各调用点会退化为默认值，不使 COM 调用崩溃
                Return New Dictionary(Of String, JsonElement)
            End Try
        End Function

        ''' <summary>读取字符串型参数，缺失或类型不符时返回 <paramref name="defaultValue"/>。</summary>
        Private Shared Function OptString(opts As Dictionary(Of String, JsonElement),
                                          key As String,
                                          defaultValue As String) As String

            Dim value As JsonElement = Nothing

            If opts Is Nothing OrElse Not opts.TryGetValue(key, value) Then
                Return defaultValue
            ElseIf value.ValueKind <> JsonValueKind.String Then
                Return defaultValue
            End If

            Dim text As String = value.GetString

            Return If(String.IsNullOrEmpty(text), defaultValue, text)
        End Function

        ''' <summary>读取布尔型参数，缺失或类型不符时返回 <paramref name="defaultValue"/>。</summary>
        Private Shared Function OptBoolean(opts As Dictionary(Of String, JsonElement),
                                           key As String,
                                           defaultValue As Boolean) As Boolean

            Dim value As JsonElement = Nothing

            If opts Is Nothing OrElse Not opts.TryGetValue(key, value) Then
                Return defaultValue
            End If

            Select Case value.ValueKind
                Case JsonValueKind.True : Return True
                Case JsonValueKind.False : Return False
                Case Else : Return defaultValue
            End Select
        End Function

        ''' <summary>
        ''' 规范化对话框初始目录：目录不存在时退回其父目录，仍不存在则返回空串
        ''' （WinForms 会忽略非法的 InitialDirectory）。
        ''' </summary>
        Private Shared Function NormalizeInitialDir(dir As String) As String
            If String.IsNullOrWhiteSpace(dir) Then
                Return ""
            End If

            Try
                If Directory.Exists(dir) Then
                    Return dir
                End If

                Dim parent As String = Path.GetDirectoryName(dir)

                If Not String.IsNullOrEmpty(parent) AndAlso Directory.Exists(parent) Then
                    Return parent
                End If
            Catch
                ' 路径含非法字符时忽略
            End Try

            Return ""
        End Function

        Private Shared Function Success(data As Object) As String
            Return JsonSerializer.Serialize(New ApiResult With {.ok = True, .data = data}, _jsonOptions)
        End Function

        Private Shared Function Failure(message As String) As String
            Return JsonSerializer.Serialize(New ApiResult With {.ok = False, .error = message}, _jsonOptions)
        End Function

        ''' <summary>统一的返回体：{ "ok": ..., "data": ..., "error": ... }。</summary>
        Private Class ApiResult

            Public Property ok As Boolean
            Public Property data As Object
            Public Property [error] As String

        End Class

#End Region

    End Class
End Namespace
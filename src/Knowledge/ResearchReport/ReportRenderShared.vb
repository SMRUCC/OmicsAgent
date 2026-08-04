Imports Microsoft.VisualBasic.Data.Framework.IO
Imports Microsoft.VisualBasic.Data.Framework.StorageProvider
Imports Microsoft.VisualBasic.Linq
Imports OmicsAgent.ReportData

''' <summary>
''' HTML 与 Word 两条报告渲染路径共享的基础设施。
''' 
''' 包含图表自动编号计数器、图表资源文件匹配、CSV 表格预览加载三部分，
''' 单点定义以保证两种输出格式的图表编号与数据内容完全一致。
''' </summary>
Module ReportRenderShared

    ''' <summary>报告中引用到的图片与数据表资源池</summary>
    Friend Class ReportResource

        Public figures As ResourceFile()
        Public tables As ResourceFile()

    End Class

    ''' <summary>单个资源文件（隶属于某个分析模块）</summary>
    Friend Class ResourceFile

        Public module_index As Integer
        Public filename As String

        Sub New(index As Integer, file As String)
            module_index = index
            filename = file
        End Sub

        Public Overrides Function ToString() As String
            Return $"[{module_index}] {filename}"
        End Function

    End Class

    ''' <summary>
    ''' 图/表自动编号计数器。以引用类型在章节间共享，
    ''' 渲染每张图/每个表时自增，实现全文档连续编号。
    ''' </summary>
    Friend Class ReportCounters
        Public figureNo As Integer = 0
        Public tableNo As Integer = 0
    End Class

    ''' <summary>
    ''' 在资源池中定位图表引用所对应的实际文件：
    ''' 先按文件名精确匹配，未命中则回退检查 <paramref name="caption"/>.file
    ''' 是否本身即为可用的磁盘路径；仍未命中返回 Nothing，由调用方跳过。
    ''' </summary>
    Friend Function ResolveResource(caption As TableFigureCaption, pool As ResourceFile()) As ResourceFile
        If caption Is Nothing Then
            Return Nothing
        End If

        Dim hit As ResourceFile = pool _
            .SafeQuery _
            .FirstOrDefault(Function(f) Path.GetFileName(f.filename).TextEquals(caption.file))

        If hit Is Nothing AndAlso Not caption.file.StringEmpty(, True) AndAlso caption.file.FileExists Then
            hit = New ResourceFile(0, caption.file)
        End If

        Return hit
    End Function

    ''' <summary>
    ''' 读取 CSV 表格预览：按 <paramref name="fields"/> 过滤列（为空则取全部列），
    ''' 最多取 <paramref name="maxRows"/> 行数据。
    ''' 加载失败时返回 headers/rows 均为空数组，由调用方输出占位提示。
    ''' </summary>
    Friend Function LoadTablePreview(file As String,
                                     fields As String(),
                                     Optional maxRows As Integer = 9,
                                     Optional loginfo As Action(Of String) = Nothing) As (headers As String(), rows As String()())

        Dim empty = (New String() {}, New String()() {})

        Try
            Dim csvDf As DataFrameResolver = DataFrameResolver.Load(file)

            ' 确定需要显示的列名及其在 CSV 中的列索引
            ' fields 为空/Nothing 时显示全部列；非空时仅保留 CSV 中实际存在的字段
            Dim displayColumns As New List(Of String)()
            Dim columnOrdinals As New List(Of Integer)()

            If fields.IsNullOrEmpty() Then
                For Each header As String In csvDf.HeadTitles
                    displayColumns.Add(header)
                    columnOrdinals.Add(csvDf.GetOrdinal(header))
                Next
            Else
                For Each fieldName As String In fields
                    Dim ordinal As Integer = csvDf.GetOrdinal(fieldName)
                    If ordinal >= 0 Then
                        displayColumns.Add(fieldName)
                        columnOrdinals.Add(ordinal)
                    End If
                Next
            End If

            If displayColumns.Count = 0 Then
                Return empty
            End If

            Dim rows As New List(Of String())

            For Each row As RowObject In csvDf.Rows.Take(maxRows)
                Dim cells(columnOrdinals.Count - 1) As String

                For i As Integer = 0 To columnOrdinals.Count - 1
                    cells(i) = row(columnOrdinals(i))
                Next

                rows.Add(cells)
            Next

            Return (displayColumns.ToArray, rows.ToArray)
        Catch ex As Exception
            If loginfo IsNot Nothing Then
                Call loginfo($"Failed to load csv table for report: {file} -> {ex.Message}")
            End If

            Return empty
        End Try
    End Function

End Module

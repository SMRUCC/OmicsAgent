
Imports OmicsAgent.Dataset

Namespace AppRuntime.Manifest

    ''' <summary>
    ''' 组学数据输入适配层。
    ''' </summary>
    ''' <remarks>
    ''' 程序支持两种互斥的数据输入模式：
    ''' <list type="number">
    ''' <item>数据集定义模式：<c>--dataset</c> 指向一份描述多组学的 JSON 文件；</item>
    ''' <item>传统参数模式：<c>--expression/--annotation/--sampleinfo</c> 直接给出文件或文件夹路径。</item>
    ''' </list>
    ''' 本类负责把两种输入归一化为结构完全一致的 <see cref="OmicsDataset"/> 集合，
    ''' 使得下游的校验、样本对齐与全部分析模块都无需感知数据来源，
    ''' 从而保证新增多组学能力不会影响原有的单组学分析行为。
    ''' </remarks>
    Public Class OmicsInputResolver

        ''' <summary>解析结果：归一化后的组学数据集集合</summary>
        Public ReadOnly Property Datasets As New List(Of OmicsDataset)

        ''' <summary>当输入为数据集定义模式时，此处保存已解析的定义文件内容</summary>
        Public ReadOnly Property Manifest As DatasetManifest

        ''' <summary>全局注释表路径（传统参数模式下由 --annotation 提供；数据集模式下为空，稍后由注释合并器填充）</summary>
        Public ReadOnly Property GlobalAnnotationFile As String = ""

        ''' <summary>样本元数据的原始输入路径（传统参数模式下由 --sampleinfo 提供）</summary>
        Public ReadOnly Property SampleInfoInput As String = ""

        Private ReadOnly _logger As Action(Of String)

        Public Sub New(Optional logger As Action(Of String) = Nothing)
            _logger = If(logger, Sub(s As String) Console.WriteLine(s))
        End Sub

        ''' <summary>
        ''' 依据命令行参数解析出组学数据集集合。
        ''' </summary>
        Public Function Resolve(opts As Opts) As OmicsInputResolver
            If opts.UseDatasetManifest Then
                Call ResolveFromManifest(opts.dataset)
            Else
                Call ResolveLegacy(opts)
            End If

            Return Me
        End Function

        ''' <summary>
        ''' 数据集定义模式：由 --dataset 指向的 JSON 文件构建数据集集合。
        ''' </summary>
        Private Sub ResolveFromManifest(manifestPath As String)
            _Manifest = DatasetManifest.LoadFromFile(manifestPath)

            _logger($"Loading dataset manifest: {_Manifest.ManifestFile}")

            For Each entry As DatasetEntry In _Manifest.datasets
                Dim ds As New OmicsDataset With {
                    .Id = entry.id,
                    .Label = If(entry.label, "").Trim,
                    .Unit = If(entry.unit, "").Trim,
                    .OmicsType = NormalizeOmicsType(entry.type, entry.expression),
                    .ExpressionFile = entry.expression,
                    .SourceExpressionFile = entry.expression,
                    .AnnotationFile = If(entry.annotation, ""),
                    .SampleInfoFile = If(entry.sampleinfo, ""),
                    .SourceSampleInfoFile = If(entry.sampleinfo, "")
                }

                Datasets.Add(ds)

                _logger($"  [OK] Dataset [{ds.Id}] {ds.DisplayName} (type={ds.OmicsType}{If(ds.Unit.StringEmpty(, True), "", $", unit={ds.Unit}")})")
                _logger($"       expression: {ds.ExpressionFile}")

                If Not ds.AnnotationFile.StringEmpty(, True) Then
                    _logger($"       annotation: {ds.AnnotationFile}")
                Else
                    _logger($"       annotation: (not provided)")
                End If

                If Not ds.SampleInfoFile.StringEmpty(, True) Then
                    _logger($"       sampleinfo: {ds.SampleInfoFile}")
                End If
            Next

            _logger($"  {Datasets.Count} omics dataset(s) declared in the manifest.")
        End Sub

        ''' <summary>
        ''' 传统参数模式：沿用原有的 --expression/--annotation/--sampleinfo 发现逻辑，行为保持不变。
        ''' </summary>
        Private Sub ResolveLegacy(opts As Opts)
            Dim exprPath As String = opts.expression

            If Directory.Exists(exprPath) Then
                ' 多组学：文件夹下的每个 CSV 视为一个组学矩阵
                For Each csv In Directory.GetFiles(exprPath, "*.csv")
                    Datasets.Add(New OmicsDataset With {
                        .ExpressionFile = csv,
                        .SourceExpressionFile = csv,
                        .OmicsType = InferOmicsType(Path.GetFileName(csv))
                    })
                Next
            ElseIf File.Exists(exprPath) Then
                ' 单组学：单个 CSV 文件
                Datasets.Add(New OmicsDataset With {
                    .ExpressionFile = exprPath,
                    .SourceExpressionFile = exprPath,
                    .OmicsType = InferOmicsType(Path.GetFileName(exprPath))
                })
            End If

            ' 全局注释表：所有组学共用
            _GlobalAnnotationFile = opts.annotation.GetFullPath

            For Each ds In Datasets
                ds.AnnotationFile = _GlobalAnnotationFile
            Next

            ' 样本元数据文件/文件夹
            _SampleInfoInput = opts.sampleinfo

            If File.Exists(_SampleInfoInput) Then
                ' 单个文件：所有组学共用
                For Each ds In Datasets
                    ds.SampleInfoFile = _SampleInfoInput
                Next
            ElseIf Directory.Exists(_SampleInfoInput) Then
                ' 文件夹：按表达矩阵文件名匹配同名的样本元数据
                For Each ds In Datasets
                    Dim matchedSampleInfo = Path.Combine(_SampleInfoInput, ds.MatrixName & ".csv")

                    If File.Exists(matchedSampleInfo) Then
                        ds.SampleInfoFile = matchedSampleInfo
                    End If
                Next
            End If

            ' 为每个数据集补一个稳定的 Id：传统模式下没有显式 id，使用表达矩阵文件名，
            ' 以便中间产物命名与多组学场景保持一致的规则。重名时追加序号以保证唯一。
            Dim usedIds As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)

            For Each ds In Datasets
                Dim baseId As String = NormalizeId(ds.MatrixName)
                Dim uniqueId As String = baseId
                Dim suffix As Integer = 2

                While usedIds.Contains(uniqueId)
                    uniqueId = $"{baseId}_{suffix}"
                    suffix += 1
                End While

                usedIds.Add(uniqueId)

                ds.Id = uniqueId
                ds.SourceSampleInfoFile = ds.SampleInfoFile
            Next
        End Sub

        ''' <summary>
        ''' 把数据集定义文件中的 type 字段归一化为程序内部使用的组学类型体系
        ''' （rna / protein / metabolite / lipid）。
        ''' 无法识别时回退到依据表达矩阵文件名进行推断。
        ''' </summary>
        Public Shared Function NormalizeOmicsType(declaredType As String, expressionFile As String) As String
            If Not declaredType.StringEmpty(, True) Then
                Dim t As String = declaredType.Trim.ToLower

                Select Case t
                    Case "rna", "transcriptome", "transcriptomics", "transcript", "mrna", "gene", "geneexpression", "gene_expression"
                        Return "rna"
                    Case "protein", "proteome", "proteomics"
                        Return "protein"
                    Case "metabolite", "metabolome", "metabolomics", "metabolic"
                        Return "metabolite"
                    Case "lipid", "lipidome", "lipidomics"
                        Return "lipid"
                End Select

                ' 未精确命中时按关键字宽松匹配，兼容 "targeted metabolome" 之类的写法
                If t.Contains("transcript") OrElse t.Contains("rna") OrElse t.Contains("gene") Then Return "rna"
                If t.Contains("proteom") OrElse t.Contains("protein") Then Return "protein"
                If t.Contains("metabol") Then Return "metabolite"
                If t.Contains("lipid") Then Return "lipid"
            End If

            ' 回退：从表达矩阵文件名推断
            If Not expressionFile.StringEmpty(, True) Then
                Return InferOmicsType(Path.GetFileName(expressionFile))
            End If

            Return "unknown"
        End Function

        ''' <summary>从文件名推断组学类型</summary>
        Public Shared Function InferOmicsType(fileName As String) As String
            Dim name = fileName.ToLower()

            If name.Contains("rna") OrElse name.Contains("transcript") OrElse name.Contains("gene") Then Return "rna"
            If name.Contains("protein") OrElse name.Contains("proteom") Then Return "protein"
            If name.Contains("metabol") Then Return "metabolite"
            If name.Contains("lipid") Then Return "lipid"

            Return "unknown"
        End Function

        ''' <summary>把任意字符串规整为可安全用作文件名片段的标识符</summary>
        Private Shared Function NormalizeId(raw As String) As String
            If raw.StringEmpty(, True) Then
                Return "omics"
            End If

            Dim chars = raw.Trim.Select(Function(c) If(Char.IsLetterOrDigit(c) OrElse c = "_"c OrElse c = "-"c, c, "_"c)).ToArray
            Dim id As String = New String(chars)

            Return If(id.StringEmpty(, True), "omics", id)
        End Function

    End Class

End Namespace

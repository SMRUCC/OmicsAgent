Imports Microsoft.VisualBasic.Data.Framework.StorageProvider
Imports OmicsAgent.AppRuntime.Manifest

Namespace Dataset

    ''' <summary>
    ''' 跨组学样本对齐执行器。
    ''' </summary>
    ''' <remarks>
    ''' 不同组学平台通常对同一批生物学个体使用各自独立的样本编号
    ''' （例如同一个体在转录组中记为 S1_R、在代谢组中记为 M_001），
    ''' 直接把这些矩阵交给下游分析会导致无法按个体合并。
    '''
    ''' 本类依据样本对齐宽表把各组学矩阵的样本列名统一替换为 <c>subject_id</c>，
    ''' 只保留所有组学共有的个体，并把重写后的新矩阵与新样本元数据写入工作区的
    ''' <c>aligned/</c> 目录，随后把 <see cref="OmicsDataset.ExpressionFile"/> 与
    ''' <see cref="OmicsDataset.SampleInfoFile"/> 重定向到这些新文件。
    '''
    ''' 这样处理之后，下游由 LLM 生成的 R 脚本无需理解任何映射关系，
    ''' 直接按统一的 subject_id 列名读取即可完成跨组学合并。
    ''' </remarks>
    Public Class SampleAligner

        Private ReadOnly _context As AnalysisContext
        Private ReadOnly _logger As Action(Of String)

        ''' <summary>组学 Id -> (样本 ID -> 该样本在源表达矩阵中的列索引)</summary>
        Private _columnLookup As Dictionary(Of String, Dictionary(Of String, Integer))

        ''' <summary>未匹配样本清单在日志中最多展示的条数，避免刷屏</summary>
        Private Const MaxReportedSamples As Integer = 15

        Public Sub New(context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
            _context = context
            _logger = If(logger, Sub(s As String) Console.WriteLine(s))
        End Sub

        ''' <summary>
        ''' 执行跨组学样本对齐。
        ''' </summary>
        ''' <param name="alignment">
        ''' 数据集定义文件中的 sample_alignment 节点。为 Nothing 或未声明显式映射时，
        ''' 认为各组学样本 ID 已经一致，按同名样本取交集做恒等映射。
        ''' </param>
        Public Sub Align(alignment As SampleAlignmentSpec)
            Dim datasets As List(Of OmicsDataset) = _context.Datasets

            If datasets.IsNullOrEmpty Then
                Throw New InvalidOperationException("No omics dataset available for sample alignment.")
            End If

            _logger("")
            _logger("Aligning samples across omics datasets ...")

            ' subject_id -> (组学 Id -> 该组学中的原始样本 ID)
            Dim subjectMap As List(Of SubjectMapping) = BuildSubjectMap(alignment, datasets)

            ' 只保留在每一个组学的表达矩阵中都真实存在对应样本列的个体
            Dim aligned As List(Of SubjectMapping) = FilterCommonSubjects(subjectMap, datasets)

            If aligned.Count = 0 Then
                Throw New InvalidDataException(
                    "Sample alignment produced an empty intersection: no subject could be matched across all omics datasets. " &
                    "Please check that the sample IDs in the alignment table match the column names of every expression matrix.")
            End If

            Dim subjectIds As String() = aligned.Select(Function(m) m.SubjectId).ToArray

            ' 依次重写每个组学的表达矩阵与样本元数据
            For Each ds As OmicsDataset In datasets
                Call AlignDataset(ds, aligned, subjectIds)
            Next

            ' 输出规范化后的对齐宽表，供 R 脚本按需引用
            Call WriteSubjectMapFile(aligned, datasets, subjectIds)

            _context.SubjectIDs = subjectIds
            _context.IsSampleAligned = True

            _logger($"[OK] Sample alignment finished: {subjectIds.Length} subject(s) shared by all {datasets.Count} omics datasets.")
            _logger($"     Aligned files: {_context.AlignedDir}")
            _logger($"     Subject map:   {_context.SubjectMapFile}")
        End Sub

        ''' <summary>
        ''' 把三种样本对齐声明方式归一为统一的映射结构。
        ''' </summary>
        Private Function BuildSubjectMap(alignment As SampleAlignmentSpec,
                                         datasets As List(Of OmicsDataset)) As List(Of SubjectMapping)

            If alignment Is Nothing OrElse Not alignment.HasExplicitMapping Then
                ' 情形一：未声明对齐关系，认为各组学样本 ID 已经天然一致
                Return BuildIdentityMap(datasets)
            End If

            If Not alignment.mapping_file.StringEmpty(, True) Then
                ' 情形二：由外部宽表 CSV 给出
                Return ReadMappingFile(alignment.mapping_file, datasets)
            End If

            ' 情形三：由内联 JSON 对象数组给出
            Return ReadInlineMap(alignment.subject_map, datasets)
        End Function

        ''' <summary>
        ''' 情形一：各组学样本 ID 已一致，取所有组学样本 ID 的交集并建立恒等映射。
        ''' </summary>
        Private Function BuildIdentityMap(datasets As List(Of OmicsDataset)) As List(Of SubjectMapping)
            _logger("  No 'sample_alignment' declared, assuming sample IDs are already consistent across omics.")

            Dim common As HashSet(Of String) = Nothing

            For Each ds As OmicsDataset In datasets
                Dim ids As String() = GetMatrixSampleIDs(ds)

                If common Is Nothing Then
                    common = New HashSet(Of String)(ids, StringComparer.Ordinal)
                Else
                    common.IntersectWith(ids)
                End If
            Next

            If common Is Nothing OrElse common.Count = 0 Then
                Throw New InvalidDataException(
                    "The omics datasets share no common sample ID. " &
                    "Please declare a 'sample_alignment' section in the dataset manifest to map sample IDs across omics.")
            End If

            ' 以第一个组学的列顺序作为输出顺序，保持结果稳定可复现
            Dim ordered As String() = GetMatrixSampleIDs(datasets(0)).Where(AddressOf common.Contains).ToArray

            Return ordered _
                .Select(Function(id)
                            Dim m As New SubjectMapping(id)

                            For Each ds As OmicsDataset In datasets
                                m.OmicsSample(ds.Id) = id
                            Next

                            Return m
                        End Function) _
                .AsList
        End Function

        ''' <summary>情形二：读取样本对齐宽表 CSV</summary>
        Private Function ReadMappingFile(mappingFile As String, datasets As List(Of OmicsDataset)) As List(Of SubjectMapping)
            _logger($"  Reading sample alignment table: {mappingFile}")

            Dim table = DataFrameResolver.Load(mappingFile)
            Dim header As String() = table.HeadTitles

            Dim subjectCol As Integer = IndexOfColumn(header, SampleAlignment.SubjectIdColumn)

            If subjectCol < 0 Then
                Throw New InvalidDataException(
                    $"The sample alignment table '{mappingFile}' must contain a '{SampleAlignment.SubjectIdColumn}' column. " &
                    $"Found columns: {String.Join(", ", header)}")
            End If

            ' 每个组学在宽表中对应的列
            Dim omicsCol As New Dictionary(Of String, Integer)

            For Each ds As OmicsDataset In datasets
                Dim col As Integer = IndexOfColumn(header, ds.Id)

                If col < 0 Then
                    Throw New InvalidDataException(
                        $"The sample alignment table '{mappingFile}' is missing the column '{ds.Id}' for omics dataset " &
                        $"'{ds.DisplayName}'. Each dataset id declared in the manifest must appear as a column. " &
                        $"Found columns: {String.Join(", ", header)}")
                End If

                omicsCol(ds.Id) = col
            Next

            Dim result As New List(Of SubjectMapping)

            For i As Integer = 0 To table.Nrows - 1
                Dim row = table.GetRow(i)
                Dim subjectId As String = SafeGet(row, subjectCol)

                If subjectId.StringEmpty(, True) Then
                    Continue For
                End If

                Dim m As New SubjectMapping(subjectId.Trim)

                For Each ds As OmicsDataset In datasets
                    m.OmicsSample(ds.Id) = SafeGet(row, omicsCol(ds.Id)).Trim
                Next

                result.Add(m)
            Next

            Return result
        End Function

        ''' <summary>情形三：解析内联 subject_map JSON 对象数组</summary>
        Private Function ReadInlineMap(subjectMap As Dictionary(Of String, String)(),
                                       datasets As List(Of OmicsDataset)) As List(Of SubjectMapping)

            _logger($"  Reading inline 'subject_map' with {subjectMap.Length} entries.")

            Dim result As New List(Of SubjectMapping)

            For i As Integer = 0 To subjectMap.Length - 1
                Dim row As Dictionary(Of String, String) = subjectMap(i)
                Dim lookup As New Dictionary(Of String, String)(row, StringComparer.OrdinalIgnoreCase)
                Dim subjectId As String = Nothing

                If Not lookup.TryGetValue(SampleAlignment.SubjectIdColumn, subjectId) OrElse subjectId.StringEmpty(, True) Then
                    Throw New InvalidDataException($"'sample_alignment.subject_map[{i}]' has an empty '{SampleAlignment.SubjectIdColumn}'.")
                End If

                Dim m As New SubjectMapping(subjectId.Trim)

                For Each ds As OmicsDataset In datasets
                    Dim sampleId As String = Nothing

                    If Not lookup.TryGetValue(ds.Id, sampleId) Then
                        Throw New InvalidDataException(
                            $"'sample_alignment.subject_map[{i}]' (subject '{subjectId}') is missing the key '{ds.Id}' " &
                            $"for omics dataset '{ds.DisplayName}'.")
                    End If

                    m.OmicsSample(ds.Id) = If(sampleId, "").Trim
                Next

                result.Add(m)
            Next

            Return result
        End Function

        ''' <summary>
        ''' 过滤出在所有组学的表达矩阵中都能找到对应样本列的个体，并输出丢弃情况的统计。
        ''' </summary>
        Private Function FilterCommonSubjects(subjectMap As List(Of SubjectMapping),
                                              datasets As List(Of OmicsDataset)) As List(Of SubjectMapping)

            ' 预先建立每个组学的「样本 ID -> 列索引」查找表
            For Each ds As OmicsDataset In datasets
                Dim sampleIds As String() = GetMatrixSampleIDs(ds)

                ds.SampleIDs = sampleIds
            Next

            Dim columnLookup As New Dictionary(Of String, Dictionary(Of String, Integer))

            For Each ds As OmicsDataset In datasets
                Dim lookup As New Dictionary(Of String, Integer)(StringComparer.Ordinal)
                Dim sampleIds As String() = ds.SampleIDs

                For i As Integer = 0 To sampleIds.Length - 1
                    ' 表达矩阵第一列为分子 ID，样本列的实际索引需要 +1
                    lookup(sampleIds(i)) = i + 1
                Next

                columnLookup(ds.Id) = lookup
            Next

            _columnLookup = columnLookup

            Dim kept As New List(Of SubjectMapping)
            Dim droppedBy As New Dictionary(Of String, List(Of String))

            For Each ds As OmicsDataset In datasets
                droppedBy(ds.Id) = New List(Of String)
            Next

            For Each m As SubjectMapping In subjectMap
                Dim ok As Boolean = True

                For Each ds As OmicsDataset In datasets
                    Dim sampleId As String = m.OmicsSample.TryGetValue(ds.Id)

                    If sampleId.StringEmpty(, True) OrElse Not columnLookup(ds.Id).ContainsKey(sampleId) Then
                        droppedBy(ds.Id).Add($"{m.SubjectId}=>{If(sampleId.StringEmpty(, True), "(empty)", sampleId)}")
                        ok = False
                    End If
                Next

                If ok Then
                    kept.Add(m)
                End If
            Next

            ' 输出对齐统计摘要
            For Each ds As OmicsDataset In datasets
                Dim dropped As List(Of String) = droppedBy(ds.Id)

                _logger($"  [{ds.Id}] {ds.DisplayName}: {ds.SampleIDs.Length} sample(s) in matrix, " &
                        $"{subjectMap.Count - dropped.Count} mapped, {dropped.Count} unmatched.")

                If dropped.Count > 0 Then
                    Dim shown = dropped.Take(MaxReportedSamples).ToArray

                    _logger($"       unmatched: {String.Join(", ", shown)}" &
                            If(dropped.Count > shown.Length, $" ... ({dropped.Count - shown.Length} more)", ""))
                End If
            Next

            Return kept
        End Function

        ''' <summary>
        ''' 重写单个组学的表达矩阵与样本元数据，并把数据集的文件指针重定向到对齐后的新文件。
        ''' </summary>
        Private Sub AlignDataset(ds As OmicsDataset, aligned As List(Of SubjectMapping), subjectIds As String())
            Dim lookup As Dictionary(Of String, Integer) = _columnLookup(ds.Id)

            ' 计算列投影索引：按 subject 顺序取出该组学对应样本列在源矩阵中的位置
            Dim keepColumns As Integer() = aligned _
                .Select(Function(m) lookup(m.OmicsSample(ds.Id))) _
                .ToArray

            Dim destMatrix As String = Path.Combine(_context.AlignedDir, $"aligned_{ds.Id}.csv")
            Dim nrows As Integer = CsvUtils.ProjectMatrixColumns(
                sourceFile:=ds.ExpressionFile,
                destFile:=destMatrix,
                keepColumnIndex:=keepColumns,
                newHeader:=subjectIds)

            ds.ExpressionFile = destMatrix
            ds.SubjectIDs = subjectIds
            ds.SampleIDs = subjectIds
            ds.IsAligned = True

            _logger($"  [OK] [{ds.Id}] aligned matrix written: {destMatrix} ({nrows} molecules x {subjectIds.Length} subjects)")

            ' 样本元数据同步做 ID 重映射
            If ds.SourceSampleInfoFile.FileExists Then
                Dim sampleToSubject As New Dictionary(Of String, String)(StringComparer.Ordinal)

                For Each m As SubjectMapping In aligned
                    sampleToSubject(m.OmicsSample(ds.Id)) = m.SubjectId
                Next

                Dim destSampleInfo As String = Path.Combine(_context.AlignedDir, $"aligned_sampleinfo_{ds.Id}.csv")

                Try
                    Dim written As Integer = CsvUtils.RemapSampleInfo(
                        sourceFile:=ds.SourceSampleInfoFile,
                        destFile:=destSampleInfo,
                        sampleToSubject:=sampleToSubject,
                        orderedSubjects:=subjectIds)

                    ds.SampleInfoFile = destSampleInfo

                    _logger($"       sample info remapped: {destSampleInfo} ({written} rows)")
                Catch ex As Exception
                    ' 样本元数据重写失败不应中断整个流程，保留原文件并给出告警
                    _logger($"       [!] Failed to remap sample info for [{ds.Id}]: {ex.Message}")
                End Try
            End If
        End Sub

        ''' <summary>把规范化后的对齐宽表写入工作区，供下游 R 脚本引用</summary>
        Private Sub WriteSubjectMapFile(aligned As List(Of SubjectMapping),
                                        datasets As List(Of OmicsDataset),
                                        subjectIds As String())

            Dim destFile As String = Path.Combine(_context.AlignedDir, "subject_map.csv")
            Dim header As New List(Of String) From {SampleAlignment.SubjectIdColumn}

            header.AddRange(datasets.Select(Function(d) d.Id))

            Using writer As New StreamWriter(destFile, append:=False, encoding:=New UTF8Encoding(False))
                writer.WriteLine(CsvUtils.ToCsvLine(header))

                For Each m As SubjectMapping In aligned
                    Dim line As New List(Of String) From {m.SubjectId}

                    line.AddRange(datasets.Select(Function(d) m.OmicsSample(d.Id)))
                    writer.WriteLine(CsvUtils.ToCsvLine(line))
                Next
            End Using

            _context.SubjectMapFile = destFile
        End Sub

        ''' <summary>读取表达矩阵的样本列名</summary>
        Private Shared Function GetMatrixSampleIDs(ds As OmicsDataset) As String()
            Dim ids As String() = CsvUtils.ReadSampleIDs(ds.ExpressionFile)

            If ids.IsNullOrEmpty Then
                Throw New InvalidDataException(
                    $"Failed to read any sample column from the expression matrix of dataset '{ds.Id}': {ds.ExpressionFile}")
            End If

            Return ids.Select(Function(s) If(s, "").Trim).ToArray
        End Function

        ''' <summary>在表头中按不区分大小写的方式查找列索引</summary>
        Private Shared Function IndexOfColumn(header As String(), columnName As String) As Integer
            For i As Integer = 0 To header.Length - 1
                If String.Equals(If(header(i), "").Trim, columnName, StringComparison.OrdinalIgnoreCase) Then
                    Return i
                End If
            Next

            Return -1
        End Function

        Private Shared Function SafeGet(row As IList(Of String), index As Integer) As String
            If index >= 0 AndAlso index < row.Count Then
                Return If(row(index), "")
            End If

            Return ""
        End Function

    End Class

End Namespace

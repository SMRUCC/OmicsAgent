Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 14: 整理结果文件（生成 xlsx 表格）
' ============================================================================

''' <summary>
''' 结果表格整理模块。
'''
''' 遍历 _context.ModuleResults 列表中每个已完成模块的分析结果，
''' 针对每个模块独立生成一个 xlsx 文件：
''' 1. 在 VB.NET 中通过 For 循环遍历 _context.ModuleResults 每一个模块；
''' 2. 列举当前循环模块中位于 ModuleResult.Workdir 下的 csv 表格文件；
''' 3. 提示 LLM 结合当前模块的 ModuleResult.Goal、ModuleResult.Conclusion 与 kb.json
'''    知识库内容，为每张 sheet 第一行编写英文注释（讲解分析结果内容 + 每一列含义）；
''' 4. 调用 <see cref="XlsxReportBuilder.BuildWorkbook"/>，在 VB.NET 端直接读取 CSV 并
'''    写出带样式的 xlsx 结果文件，保存到当前循环模块的 OutputDir。
'''
''' xlsx 表格样式由 ReportHelper.WriteReportSheet 统一实现：
''' - 第 1 行（注释说明文本行）：白底、草绿色斜体字，跨列合并、左对齐
''' - 第 2 行（列标题行）：深蓝色背景，白色加粗字体
''' - 第 3 行起（正文）：Cambria 11 号字体，首列为深灰色斜体行标题
''' - 冻结窗格锚定于 B2
''' - 所有文本信息（文件名、注释、标题、列标题）均为英文
''' </summary>
Public Class ResultTablesModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Result Tables Compilation"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 14

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "result_tables_"
        End Get
    End Property

    Protected Overrides ReadOnly Property NeedsPlantSteps As Boolean
        Get
            Return False
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "为结果表格整理设计计划，将中间分析 CSV 结果表编译为结构化的 XLSX 文件，每个分析模块生成一个 XLSX 文件。
1. 遍历 _context.ModuleResults（已完成的分析模块列表）
2. 对每个 ModuleResult，递归列出 ModuleResult.Workdir 下的所有 CSV 文件
3. 跳过未产生 CSV 文件的模块
4. 对每个模块生成一个 XLSX 文件，每个 CSV 对应一个工作表：
   - 第 1 行：描述/注释文本（草绿色斜体字），使用英文
   - 第 2 行：列标题（深蓝色背景，白色加粗字体）
   - 第 3 行起：数据，首列为深灰色斜体行标题
   - 在 B2 处冻结窗格
5. 每个工作表第 1 行的注释文本须由 LLM 结合当前模块的 Goal、Conclusion 和 kb.json 知识库内容生成
6. XLSX 文件在 VB.NET 端直接读取 CSV 生成（无需编写脚本），保存到当前模块的 ModuleResult.OutputDir"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 结果表格整理的整体情况（遍历的模块数量、生成的 XLSX 文件数量、包含的工作表数量）
2. 每个分析模块的结果 xlsx 文件汇总情况（保存于各模块 OutputDir）
3. 表格样式规范的应用情况（字体、背景色、冻结窗格等）
4. 各工作表的英文注释说明内容（结合模块目标/结论与知识库）
5. 与用户研究主题的关联性说明"
    End Function

    ' Protected Overrides Async Function GenerateConclusionAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
    '     Return Await Task.FromResult(GetConclusionItems)
    ' End Function

    ''' <summary>调用 LLM 生成分析计划</summary>
    Protected Overrides Async Function GeneratePlanAsync(llm As LLMClient, cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Return Await Task.FromResult(New ModulePlan With {
            .execution_steps = {
                New [Step] With {.action = "生成xlsx文件", .goal = "生成xlsx文件"}
            },
            .goal = "生成xlsx文件",
            .module_name = ModuleName
        })
    End Function

    ''' <summary>
    ''' 调用 LLM 编写并执行脚本。
    ''' 通过 For 循环遍历 _context.ModuleResults 中每个已完成模块，
    ''' 为每个模块独立生成注释 JSON 与 xlsx 文件。
    ''' </summary>
    Protected Overrides Async Function GenerateAndRunScriptAsync(llm As LLMClient, plan As ModulePlan, [step] As [Step], cancellationToken As CancellationToken) As Task
        LogInfo("Compiling result tables into XLSX files (per-module iteration)...")

        If _context.ModuleResults.IsNullOrEmpty Then
            LogInfo("No module results available. Skipping XLSX generation.")
            Return
        End If

        ' 在循环外一次性读取 kb.json 知识库内容，复用于每个模块的注释提示词
        Dim kbContent = ReadKnowledgeBaseContent()

        ' 遍历每个已完成模块的分析结果
        For Each mr As ModuleResult In _context.ModuleResults
            If cancellationToken.IsCancellationRequested Then Exit For

            Try
                Await ProcessModuleAsync(mr, kbContent, cancellationToken)
            Catch ex As Exception
                LogInfo($"[警告] 模块 {mr.ModuleIndex} ({mr.ModuleName}) 的 xlsx 生成失败：{ex.Message}")
                LogInfo(ex.StackTrace)
                ' 单个模块失败不影响其他模块处理
                Continue For
            End Try
        Next
    End Function

    ''' <summary>处理单个模块：收集 CSV → 生成注释 → 直接在 VB.NET 端生成 xlsx</summary>
    Private Async Function ProcessModuleAsync(mr As ModuleResult, kbContent As String, cancellationToken As CancellationToken) As Task
        ' 1. 列举当前模块 Workdir 下的所有 CSV 文件
        Dim csvFiles = CollectModuleCsvFiles(mr.Workdir)

        If csvFiles.Count = 0 Then
            LogInfo($"模块 {mr.ModuleIndex} ({mr.ModuleName}) 在 Workdir 中未发现 CSV 文件，跳过：{mr.Workdir}")
            Return
        End If

        LogInfo($"正在处理模块 {mr.ModuleIndex} ({mr.ModuleName})：发现 {csvFiles.Count} 个 CSV 文件")

        ' 确保输出目录存在
        If Not String.IsNullOrEmpty(mr.OutputDir) Then
            Call mr.OutputDir.MakeDir
        Else
            LogInfo($"模块 {mr.ModuleIndex} ({mr.ModuleName}) 的 OutputDir 为空，跳过。")
            Return
        End If

        Dim xlsxFileName = GetModuleXlsxFileName(mr)

        ' 2. 第一次 LLM 调用：生成该模块每张 sheet 第一行的英文注释说明，保存为 JSON
        Dim descJson As SheetAnnotations = Await GenerateAnnotationsForModuleAsync(mr, csvFiles, kbContent, cancellationToken)
        Dim descPath = Path.Combine(mr.OutputDir, "table_descriptions.json")
        Call descJson.ToString.SaveTo(descPath)
        LogInfo($"模块 {mr.ModuleIndex} 注释 JSON 已保存：{descPath}")

        ' 3. 在 VB.NET 端直接读取 CSV 并生成带样式的 xlsx（不再走 LLM + R 脚本路线）
        Dim xlsxPath As String = Path.Combine(mr.OutputDir, xlsxFileName)
        Dim nsheets As Integer = XlsxReportBuilder.BuildWorkbook(descJson, xlsxPath, AddressOf LogInfo)

        If nsheets = 0 Then
            LogInfo($"[警告] 模块 {mr.ModuleIndex} ({mr.ModuleName}) 未生成任何工作表，xlsx 未输出。")
        Else
            LogInfo($"模块 {mr.ModuleIndex} ({mr.ModuleName}) 的 xlsx 已生成：{xlsxPath}")
        End If
    End Function

    ''' <summary>递归收集指定 Workdir 下的所有 CSV 文件</summary>
    Private Function CollectModuleCsvFiles(workdir As String) As List(Of String)
        Dim result As New List(Of String)()

        If String.IsNullOrEmpty(workdir) OrElse Not Directory.Exists(workdir) Then
            Return result
        End If

        Try
            result.AddRange(Directory.GetFiles(workdir, "*.csv", SearchOption.AllDirectories))
        Catch ex As Exception
            LogInfo($"[警告] 扫描 Workdir 失败 ({workdir})：{ex.Message}")
        End Try

        Return result
    End Function

    ''' <summary>
    ''' 读取 kb.json 知识库内容并截断至 30000 字符，返回字符串。
    ''' 在循环外调用一次，复用于每个模块的注释提示词。
    ''' </summary>
    Private Function ReadKnowledgeBaseContent() As String
        If File.Exists(_context.KnowledgeBaseFile) Then
            Try
                Dim kb = File.ReadAllText(_context.KnowledgeBaseFile, Encoding.UTF8)
                Dim stripLen As Integer = 30000
                If kb.Length > stripLen Then
                    Return kb.Substring(0, stripLen) & "...[truncated]"
                Else
                    Return kb
                End If
            Catch ex As Exception
                LogInfo($"[警告] 读取 kb.json 失败：{ex.Message}")
            End Try
        End If

        Return "(无知识库文件)"
    End Function

    ''' <summary>
    ''' 根据模块索引与名称生成 xlsx 文件名，格式为 {ModuleIndex}_{normalize(ModuleName)}.xlsx
    ''' </summary>
    Private Function GetModuleXlsxFileName(mr As ModuleResult) As String
        Dim safeName = mr.ModuleName.NormalizePathString(alphabetOnly:=True).Replace(" ", "_").ToLower()
        Return $"{mr.ModuleIndex}_{safeName}.xlsx"
    End Function

    ''' <summary>
    ''' 多组学场景下，结果表往往按组学拆分为多个文件，
    ''' 注释文本需要说明该表属于哪个组学，否则用户在 XLSX 中无法分辨。
    ''' </summary>
    Private Function OmicsScopeAnnotationHint() As String
        If Not _context.IsMultiOmics Then
            Return ""
        End If

        Dim omicsList As String = _context.Datasets _
            .Select(Function(d) $"{d.Id} = {d.DisplayName} ({d.OmicsType})") _
            .JoinBy("; ")

        Return $"- This study is a multi-omics analysis involving: {omicsList}. " &
               "Many result tables are split per omics and carry the omics id in their file name or in an omics_id column. " &
               "When a table belongs to a specific omics layer, the annotation MUST state explicitly which omics it comes from."
    End Function

    ''' <summary>读取 CSV 文件的第一行表头</summary>
    Private Function GetCsvHeader(csvPath As String) As List(Of String)
        Dim result As New List(Of String)()
        Try
            Dim firstLine = File.ReadLines(csvPath).FirstOrDefault()
            If Not String.IsNullOrEmpty(firstLine) Then
                result.AddRange(firstLine.Split(","c))
            End If
        Catch
        End Try
        Return result
    End Function

    ''' <summary>清洗工作表名称，符合 Excel 限制（&lt;=31 字符，无非法字符）</summary>
    Private Function SanitizeSheetName(name As String) As String
        Dim s = Path.GetFileNameWithoutExtension(name)
        If s.Length > 31 Then s = s.Substring(0, 31)
        s = s.Replace(":"c, "_"c).Replace("\"c, "_"c).Replace("/"c, "_"c).Replace("?"c, "_"c).Replace("*"c, "_"c).Replace("["c, "_"c).Replace("]"c, "_"c)
        Return s
    End Function

    ''' <summary>
    ''' 第一次 LLM 调用：结合当前模块的 Goal、Conclusion 与 kb.json 知识库内容，
    ''' 为该模块每张 sheet 第一行生成英文注释（讲解分析结果内容 + 每一列含义），
    ''' 并保存为结构化 JSON。
    ''' </summary>
    Private Async Function GenerateAnnotationsForModuleAsync(mr As ModuleResult, csvFiles As List(Of String), kbContent As String, cancellationToken As CancellationToken) As Task(Of SheetAnnotations)
        ' 构建单模块骨架 JSON（含 csv 绝对路径、英文 sheet 名、空注释）
        Dim sk As New SheetAnnotations With {
            .module_index = mr.ModuleIndex,
            .module_name = mr.ModuleName,
            .xlsx_file = GetModuleXlsxFileName(mr),
            .output_dir = mr.OutputDir,
            .sheets = csvFiles.Select(Function(csv)
                                          Return New SheetAnnotations.Sheet With {
                                              .annotation = "",
                                              .csv = csv,
                                              .sheet_name = SanitizeSheetName(csv)
                                          }
                                      End Function)
        }
        Dim skeleton = sk.ToString()
        ' 构建每个 sheet 的表头信息，供 LLM 编写注释
        Dim headersInfo As New StringBuilder()
        headersInfo.AppendLine($"## 模块 {mr.ModuleIndex}: {mr.ModuleName}")
        For Each csv In csvFiles
            Dim hdr = GetCsvHeader(csv)
            headersInfo.AppendLine($"- CSV文件: {Path.GetFileName(csv)} ({csv})")
            headersInfo.AppendLine($"  工作表名: {SanitizeSheetName(csv)}")
            headersInfo.AppendLine($"  列数 ({hdr.Count}): {String.Join(", ", hdr)}")
        Next

        Using llm As LLMClient = _config.CreateLLMClient(FolderBaseName & "-sheet_comment_" & mr.ModuleIndex, _context.TmpDir)
            Call RegisterTools(llm, True)

            Dim prompt As String = <root><![CDATA[
你是一位生物信息学数据分析师。你的任务是为结果 XLSX 文件中每个工作表的第一行编写英文注释文本。该 XLSX 文件汇总了某个分析模块产生的 CSV 结果表。

# 模块信息
- 模块序号: {MODULE_INDEX}
- 模块名称: {MODULE_NAME}
- 模块分析目标: {MODULE_GOAL}

# 模块阶段性总结（分析发现）
{MODULE_CONCLUSION}

# 知识库 (kb.json)
{KB_CONTENT}

# 本模块产生的 CSV 文件（每个文件对应一个工作表）
{HEADERS}

# 表格描述骨架 (JSON)
以下 JSON 列出了本模块 XLSX 文件中应包含的 CSV 文件（工作表）。'annotation' 字段当前为空。

{SKELETON}

# 你的任务
为每个工作表填写 'annotation' 字段（字符串），内容为清晰的英文描述，将放置在该工作表的第一行。注释须：
- 说明该表包含的数据/内容
- 解释每一列的含义（使用上方提供的该 CSV 的列列表）
- 将表格内容与本模块的目标和结论关联，并在适用时关联知识库中的相关生物学知识（如关键基因/通路/机制）
- 说明用户可从该表获得的生物学知识/见解
{OMICS_SCOPE}
保持信息丰富但简洁（通常 2-5 句）。你还可以优化 'sheet_name' 为更清晰的英文名称（<=31 字符，不含 : \ / ? * [ ] 字符），但你必须保持 'csv' 绝对路径与给定值完全一致。

仅返回填写完成的 JSON（不要额外解释，不要 markdown 代码围栏）。
]]></root>.Value

            prompt = prompt.Replace("{MODULE_INDEX}", mr.ModuleIndex.ToString()) _
                           .Replace("{MODULE_NAME}", mr.ModuleName) _
                           .Replace("{MODULE_GOAL}", If(mr.Goal, "(未提供)")) _
                           .Replace("{MODULE_CONCLUSION}", If(mr.Conclusion, "(未提供)")) _
                           .Replace("{KB_CONTENT}", kbContent) _
                           .Replace("{HEADERS}", headersInfo.ToString()) _
                           .Replace("{SKELETON}", skeleton) _
                           .Replace("{OMICS_SCOPE}", OmicsScopeAnnotationHint())

            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim json = resp.ExtractJsonFromResponse
            Dim result As SheetAnnotations = SheetAnnotations.ParseJSON(json)

            If Not result Is Nothing Then
                Return result
            End If
        End Using

        ' LLM 调用失败时回退到骨架（注释为空），保证 xlsx 仍可正常生成
        Return sk
    End Function

End Class

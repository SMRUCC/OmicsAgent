Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 10: 整理结果文件（生成 xlsx 表格）
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
''' 4. 提示 LLM 编写基于 openxlsx 的 R 脚本，按规定的样式读取 CSV 并生成 xlsx 结果文件；
''' 5. 由 ShellTool 执行该 R 脚本，所生成的 xlsx 保存到当前循环模块的 OutputDir。
'''
''' xlsx 表格样式要求（写入 LLM 提示词）：
''' - 全局采用 Cambria Math 11 号字体
''' - 表格缩放 90%
''' - 背景色为默认的白色
''' - 第一列（id 列）：浅灰色背景色，斜体，黑色字体颜色
''' - 第一行（注释说明文本行）：默认背景色，草绿色字体颜色
''' - 第二行（列标题行）：深蓝色背景色，白色字体颜色，加粗字体
''' - 第一列 + 第二行进行 freeze panes 冻结
''' - 所有文本信息（文件名、注释、标题、列标题）均为英文
''' </summary>
Public Class ResultTablesModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Result Tables Compilation"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 10

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "result_tables_"
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
   - 第 1 行：描述/注释文本（草绿色字体），使用英文
   - 第 2 行：列标题（深蓝色背景，白色加粗字体）
   - 第 3 行起：数据
   - 第 1 列：浅灰色背景，斜体，黑色字体
   - 在 B3 处冻结窗格
5. 每个工作表第 1 行的注释文本须由 LLM 结合当前模块的 Goal、Conclusion 和 kb.json 知识库内容生成
6. XLSX 文件由 LLM 编写的 R 脚本（基于 openxlsx）生成，保存到当前模块的 ModuleResult.OutputDir"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 结果表格整理的整体情况（遍历的模块数量、生成的 XLSX 文件数量、包含的工作表数量）
2. 每个分析模块的结果 xlsx 文件汇总情况（保存于各模块 OutputDir）
3. 表格样式规范的应用情况（字体、背景色、冻结窗格等）
4. 各工作表的英文注释说明内容（结合模块目标/结论与知识库）
5. 与用户研究主题的关联性说明"
    End Function

    ''' <summary>
    ''' 调用 LLM 编写并执行脚本。
    ''' 通过 For 循环遍历 _context.ModuleResults 中每个已完成模块，
    ''' 为每个模块独立生成注释 JSON 与 xlsx 文件。
    ''' </summary>
    Protected Overrides Async Function GenerateAndRunScriptAsync(llm As LLMClient, plan As ModulePlan, [step] As [Step], cancellationToken As CancellationToken) As Task
        LogInfo("Compiling result tables into XLSX files via LLM-generated R script (per-module iteration)...")

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
                Await ProcessModuleAsync(mr, kbContent, plan, [step], cancellationToken)
            Catch ex As Exception
                LogInfo($"[警告] 模块 {mr.ModuleIndex} ({mr.ModuleName}) 的 xlsx 生成失败：{ex.Message}")
                LogInfo(ex.StackTrace)
                ' 单个模块失败不影响其他模块处理
                Continue For
            End Try
        Next
    End Function

    ''' <summary>处理单个模块：收集 CSV → 生成注释 → 生成并执行 R 脚本</summary>
    Private Async Function ProcessModuleAsync(mr As ModuleResult, kbContent As String, plan As ModulePlan, [step] As [Step], cancellationToken As CancellationToken) As Task
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
        Dim descJson = Await GenerateAnnotationsForModuleAsync(mr, csvFiles, kbContent, cancellationToken)
        Dim descPath = Path.Combine(mr.OutputDir, "table_descriptions.json")
        Call descJson.SaveTo(descPath)
        LogInfo($"模块 {mr.ModuleIndex} 注释 JSON 已保存：{descPath}")

        ' 3. 第二次 LLM 调用：通过函数调用工具编写并执行生成 xlsx 的 R 脚本
        Dim prompt = BuildRScriptPrompt(descPath, mr.OutputDir, xlsxFileName, mr, plan, [step])

        Using llmRscript As LLMClient = _config.CreateLLMClient(FolderBaseName & "-xlsx_" & mr.ModuleIndex, _context.TmpDir)
            Call RegisterTools(llmRscript, True)
            Await llmRscript.Chat(prompt, cancellationToken)
        End Using

        LogInfo($"模块 {mr.ModuleIndex} ({mr.ModuleName}) 的 xlsx 已生成：{Path.Combine(mr.OutputDir, xlsxFileName)}")
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
    Private Async Function GenerateAnnotationsForModuleAsync(mr As ModuleResult, csvFiles As List(Of String), kbContent As String, cancellationToken As CancellationToken) As Task(Of String)
        ' 构建单模块骨架 JSON（含 csv 绝对路径、英文 sheet 名、空注释）
        Dim sk As New StringBuilder()
        sk.AppendLine("{")
        sk.AppendLine($"  ""module_index"": {mr.ModuleIndex},")
        sk.AppendLine($"  ""module_name"": ""{mr.ModuleName}"",")
        sk.AppendLine($"  ""xlsx_file"": ""{GetModuleXlsxFileName(mr)}"",")
        sk.AppendLine($"  ""output_dir"": ""{mr.OutputDir}"",")
        sk.AppendLine("  ""sheets"": [")
        Dim firstSheet = True
        For Each csv In csvFiles
            If Not firstSheet Then sk.AppendLine("    },")
            firstSheet = False
            sk.AppendLine("    {")
            sk.AppendLine($"      ""csv"": ""{csv}"",")
            sk.AppendLine($"      ""sheet_name"": ""{SanitizeSheetName(csv)}"",")
            sk.AppendLine("      ""annotation"": """"")
        Next
        If csvFiles.Count > 0 Then sk.AppendLine("    }")
        sk.AppendLine("  ]")
        sk.AppendLine("}")

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
保持信息丰富但简洁（通常 2-5 句）。你还可以优化 'sheet_name' 为更清晰的英文名称（<=31 字符，不含 : \ / ? * [ ] 字符），但你必须保持 'csv' 绝对路径与给定值完全一致。

仅返回填写完成的 JSON（不要额外解释，不要 markdown 代码围栏）。
]]></root>.Value

            prompt = prompt.Replace("{MODULE_INDEX}", mr.ModuleIndex.ToString()) _
                           .Replace("{MODULE_NAME}", mr.ModuleName) _
                           .Replace("{MODULE_GOAL}", If(mr.Goal, "(未提供)")) _
                           .Replace("{MODULE_CONCLUSION}", If(mr.Conclusion, "(未提供)")) _
                           .Replace("{KB_CONTENT}", kbContent) _
                           .Replace("{HEADERS}", headersInfo.ToString()) _
                           .Replace("{SKELETON}", skeleton)

            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim json = resp.ExtractJsonFromResponse
            If Not String.IsNullOrEmpty(json) Then
                Return json
            End If
        End Using

        ' LLM 调用失败时回退到骨架（注释为空），保证 R 脚本仍可运行
        Return skeleton
    End Function

    ''' <summary>
    ''' 构建第二次 LLM 调用的提示词：要求 LLM 编写基于 openxlsx 的 R 脚本，
    ''' 按规定的样式读取 CSV 与注释 JSON，生成单个 xlsx 结果文件并保存到模块 OutputDir。
    ''' </summary>
    Private Function BuildRScriptPrompt(descPath As String, outputDir As String, xlsxFileName As String, mr As ModuleResult, plan As ModulePlan, [step] As [Step]) As String
        Dim prompt As String = <root><![CDATA[
你是一位生物信息学 R 脚本专家。请编写一个完整的 R 脚本，使用 openxlsx 包将某个分析模块的 CSV 结果表编译为一个结构化、带样式的 XLSX 文件。

# 输入
- JSON 文件路径: {DESC_PATH}
  描述了要创建的模块 XLSX 文件、包含的 CSV 文件（工作表），以及每个工作表第一行的英文注释文本。
- XLSX 文件输出目录: {OUT_DIR}
- XLSX 文件名: {XLSX_FILE}

# 计划执行上下文
- 模块: 结果表格整理（正在处理模块 {MODULE_INDEX}: {MODULE_NAME}）
- 计划目标: {PLAN_GOAL}
- 当前执行步骤: {STEP}
- 所有脚本和生成的文件放置在指定临时工作区目录: {WORKSPACE}

# JSON 结构 (table_descriptions.json)
{
  'module_index': <整数>,
  'module_name': '<模块名称>',
  'xlsx_file': '<xlsx文件名>',
  'output_dir': '<绝对输出目录路径>',
  'sheets': [
    { 'csv': '<CSV绝对路径>', 'sheet_name': '<英文工作表名>', 'annotation': '<第1行英文注释文本>' }
  ]
}

# 你的任务
编写一个 R 脚本，完成以下操作：
1. 确保 openxlsx 包可用（使用: if (!require(openxlsx)) install.packages('openxlsx'); library(openxlsx)）。同样确保 jsonlite 可用。
2. 使用 jsonlite::fromJSON('{DESC_PATH}', simplifyVector = TRUE) 读取 JSON。
3. 创建新工作簿: wb <- createWorkbook()
4. 对 desc$sheets 中的每个工作表条目：
   a. 读取 CSV: df <- read.csv(sh$csv, stringsAsFactors = FALSE, check.names = FALSE)
   b. 添加工作表，使用合法的英文工作表名（<=31 字符，不含 : \ / ? * [ ] 字符）: addWorksheet(wb, sheetName = sh$sheet_name)
   c. 将注释文本写入 A1 单元格（第 1 行）: writeData(wb, sh$sheet_name, x = sh$annotation, startRow = 1, startCol = 1, colNames = FALSE, rowNames = FALSE)
   d. 将 CSV 列标题写入第 2 行: writeData(wb, sh$sheet_name, x = as.data.frame(t(colnames(df))), startRow = 2, startCol = 1, colNames = FALSE, rowNames = FALSE)
   e. 将 CSV 数据（不含表头）从第 3 行第 1 列开始写入: writeData(wb, sh$sheet_name, x = df, startRow = 3, startCol = 1, colNames = FALSE, rowNames = FALSE)
5. 定义并应用以下样式（全部使用字体 'Cambria Math'，字号 11）：
   - defaultStyle: Cambria Math 11，默认白色背景。首先应用到整个已用范围。
   - annotStyle: 默认背景，草绿色字体 '#228B22'。应用到第 1 行（所有已用列）。
   - headerStyle: 深蓝色背景 '#1F4E79'，白色字体 '#FFFFFF'，加粗 textDecoration = 'bold'。应用到第 2 行（所有已用列）。
   - idStyle: 浅灰色背景 '#D9D9D9'，斜体 textDecoration = 'italic'，黑色字体 '#000000'。应用到第 1 列（A 列），第 3 行至最后一数据行。
   先应用 defaultStyle，再叠加 annotStyle / headerStyle / idStyle，使特定样式优先生效。
6. 冻结第 1 列和前两行（左上角单元格 = B3）。在 openxlsx 中: freezePane(wb, sh$sheet_name, firstRow = 3, firstCol = 2)
7. 设置工作表缩放为 90%: setZoom(wb, sh$sheet_name, zoom = 90)
8. 保存工作簿: saveWorkbook(wb, file.path('{OUT_DIR}', '{XLSX_FILE}'), overwrite = TRUE)
9. 输出进度信息，并优雅处理缺失文件（跳过并警告，不要停止）。
10. 重要：所有文本（XLSX 文件名、工作表名、注释、列标题）必须使用英文。

# 参考模板（根据需要调整）
library(openxlsx)
if (!require(openxlsx)) install.packages('openxlsx')
if (!require(jsonlite)) install.packages('jsonlite')
library(openxlsx)
library(jsonlite)

desc <- fromJSON('{DESC_PATH}', simplifyVector = TRUE)
out_dir <- '{OUT_DIR}'
xlsx_name <- '{XLSX_FILE}'

defaultStyle <- createStyle(fontName = 'Cambria Math', fontSize = 11)
annotStyle <- createStyle(fontName = 'Cambria Math', fontSize = 11, fontColour = '#228B22')
headerStyle <- createStyle(fontName = 'Cambria Math', fontSize = 11, fontColour = 'FFFFFF', fgFill = '#1F4E79', textDecoration = 'bold')
idStyle <- createStyle(fontName = 'Cambria Math', fontSize = 11, fgFill = '#D9D9D9', textDecoration = 'italic', fontColour = '000000')

wb <- createWorkbook()
for (j in seq_along(desc$sheets)) {
  sh <- desc$sheets[[j]]
  if (!file.exists(sh$csv)) { warning(paste('Missing CSV:', sh$csv)); next }
  df <- read.csv(sh$csv, stringsAsFactors = FALSE, check.names = FALSE)
  ncol <- ncol(df)
  lastRow <- nrow(df) + 2
  addWorksheet(wb, sheetName = sh$sheet_name)
  writeData(wb, sh$sheet_name, x = sh$annotation, startRow = 1, startCol = 1, colNames = FALSE, rowNames = FALSE)
  writeData(wb, sh$sheet_name, x = as.data.frame(t(colnames(df))), startRow = 2, startCol = 1, colNames = FALSE, rowNames = FALSE)
  writeData(wb, sh$sheet_name, x = df, startRow = 3, startCol = 1, colNames = FALSE, rowNames = FALSE)
  addStyle(wb, sh$sheet_name, defaultStyle, rows = 1:lastRow, cols = 1:ncol, gridExpand = TRUE)
  addStyle(wb, sh$sheet_name, annotStyle, rows = 1, cols = 1:ncol, gridExpand = TRUE)
  addStyle(wb, sh$sheet_name, headerStyle, rows = 2, cols = 1:ncol, gridExpand = TRUE)
  addStyle(wb, sh$sheet_name, idStyle, rows = 3:lastRow, cols = 1, gridExpand = TRUE)
  freezePane(wb, sh$sheet_name, firstRow = 3, firstCol = 2)
  setZoom(wb, sh$sheet_name, zoom = 90)
  cat(paste('Prepared sheet', sh$sheet_name, 'for', xlsx_name, '\n'))
}
saveWorkbook(wb, file.path(out_dir, xlsx_name), overwrite = TRUE)
cat(paste('Saved', xlsx_name, '\n'))

# 重要注意事项
- 使用绝对路径。
- 确保数值列保持数值类型（不要作为文本处理）。
- 脚本须可端到端运行，无需额外输入。

# 执行说明
- 使用 write_file 工具将 R 脚本写入工作区文件（如 'module_10_result_tables_{MODULE_INDEX}.R'）
- 使用 run_rscript 工具执行该 R 脚本
- 验证 XLSX 文件已在输出目录中成功生成
]]></root>.Value

        prompt = prompt.Replace("{DESC_PATH}", descPath) _
                       .Replace("{OUT_DIR}", outputDir) _
                       .Replace("{XLSX_FILE}", xlsxFileName) _
                       .Replace("{MODULE_INDEX}", mr.ModuleIndex.ToString()) _
                       .Replace("{MODULE_NAME}", mr.ModuleName) _
                       .Replace("{PLAN_GOAL}", plan.goal) _
                       .Replace("{STEP}", [step].GetJson) _
                       .Replace("{WORKSPACE}", Workspace.GetDirectoryFullPath)
        Return prompt
    End Function
End Class

Imports Microsoft.VisualBasic.MIME.application.json
Imports Microsoft.VisualBasic.MIME.application.json.Javascript
Imports Microsoft.VisualBasic.MIME.application.json.LenientJson
Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 13: 用户数据表格整理（/report 模式专用）
' ============================================================================

''' <summary>
''' 用户数据表格整理模块。
'''
''' 从用户通过 --dirs 参数指定的文件夹中递归扫描所有 CSV 文件，
''' 按文件夹分组后调用 LLM 理解数据内容、生成英文注释并整理为 xlsx 表格，
''' 最终构造 ModuleResult 对象供 ReportModule（Module14）撰写报告。
'''
''' 与 ResultTablesModule（/agent 模式）的区别：
''' - /agent 模式中，ModuleResults 由各分析模块在执行过程中自动生成，
'''   含 Goal 与 Conclusion；ResultTablesModule 仅遍历已有 ModuleResults
'''   并将 CSV 整理为 xlsx。
''' - /report 模式中，用户数据没有预定义的模块结构，本模块负责：
'''   1. 扫描用户文件夹 → 创建 ModuleResult
'''   2. LLM 推断数据目标（Goal） + 生成表注释 → 生成 xlsx
'''   3. LLM 生成数据总结（Conclusion） → 保存 conclusion.md
'''   4. 将各组 ModuleResult 添加到 _context.ModuleResults
'''
''' xlsx 表格样式要求（写入 LLM 提示词，与 Module13 一致）：
''' - 全局采用 Cambria Math 11 号字体
''' - 表格缩放 90%
''' - 背景色为默认的白色
''' - 第一列（id 列）：浅灰色背景色，斜体，黑色字体颜色
''' - 第一行（注释说明文本行）：默认背景色，草绿色字体颜色
''' - 第二行（列标题行）：深蓝色背景色，白色字体颜色，加粗字体
''' - 第一列 + 第二行进行 freeze panes 冻结
''' - 所有文本信息（文件名、注释、标题、列标题）均为英文
''' </summary>
Public Class UserDataTablesModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "User Data Tables Compilation"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 13

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "user_data_tables_"
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
        Return "为用户自行分析得到的结果数据设计表格整理计划，将用户提供的 CSV 结果表编译为结构化的 XLSX 文件，每个数据文件夹生成一个 XLSX 文件。
1. 读取 --dirs 文件中的用户数据文件夹列表
2. 递归扫描每个文件夹下的所有 CSV 文件
3. 跳过没有任何 CSV 文件的文件夹
4. 对每个文件夹生成一个 XLSX 文件，每个 CSV 对应一个工作表：
   - 第 1 行：描述/注释文本（草绿色字体），使用英文
   - 第 2 行：列标题（深蓝色背景，白色加粗字体）
   - 第 3 行起：数据
   - 第 1 列：浅灰色背景，斜体，黑色字体
   - 在 B3 处冻结窗格
5. 每个工作表第 1 行的注释文本须由 LLM 结合用户研究主题和知识库内容生成
6. 对每个文件夹，由 LLM 推断该组数据的研究目标（Goal）并生成阶段性总结（Conclusion）
7. XLSX 文件由 LLM 编写的 R 脚本（基于 openxlsx）生成，保存到工作区的 analysis/user_data_N/ 目录"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 用户数据表格整理的整体情况（扫描的文件夹数量、生成的 XLSX 文件数量、包含的工作表数量）
2. 每个用户数据文件夹的结果 xlsx 文件汇总情况（保存于 analysis/user_data_N/）
3. 表格样式规范的应用情况（字体、背景色、冻结窗格等）
4. 各工作表的英文注释说明内容（结合研究主题与知识库）
5. 各组数据的分析目标与阶段性总结
6. 与用户研究主题的关联性说明"
    End Function

    ''' <summary>调用 LLM 生成分析计划</summary>
    Protected Overrides Async Function GeneratePlanAsync(llm As LLMClient, cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Return Await Task.FromResult(New ModulePlan With {
            .execution_steps = GetFolderSteps.ToArray,
            .goal = "理解用户的结果数据，然后按照用户的研究背景研究目的对用户的结果数据做出科学性的总结，最后整理用户数据表格并生成xlsx文件",
            .module_name = ModuleName
        })
    End Function

    Private Iterator Function GetFolderSteps() As IEnumerable(Of [Step])
        LogInfo("Scanning user data folders and compiling result tables into XLSX files...")

        Dim dirsFile As String = _context.UserDataDirsFile

        If dirsFile.StringEmpty(, True) Then
            LogInfo("No user data dirs file specified. Skipping table compilation.")
            Return
        End If

        If Not dirsFile.FileExists Then
            LogInfo($"User data dirs file not found: {dirsFile}")
            Return
        End If

        ' 解析 dirs 文件，每行一个文件夹路径，跳过空行和 # 注释行
        Dim userFolders = ParseDirsFile(dirsFile).ToArray
        If userFolders.Length = 0 Then
            LogInfo("No valid folder paths found in dirs file.")
            Return
        End If

        LogInfo($"Found {userFolders.Length} folder(s) in dirs file")

        Dim index As Integer = 1

        For Each path As String In userFolders
            Yield New [Step] With {
                .rscript_path = index & ":" & path,
                .action = $"理解用户在文件夹{path}中的结果数据，然后按照用户的研究背景研究目的对用户的结果数据做出科学性的总结，最后整理用户数据表格并生成xlsx文件",
                .goal = "整理用户数据表格并生成xlsx文件"
            }
        Next
    End Function

    ''' <summary>生成总结，由基类在 GenerateConclusionAsync 中调用</summary>
    Protected Overrides Async Function GenerateConclusionAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Return Await Task.FromResult(GetConclusionItems)
    End Function

    ''' <summary>
    ''' 核心逻辑：扫描用户数据文件夹，为每组数据生成注释并创建 xlsx，
    ''' 同时构造 ModuleResult 对象填充 _context.ModuleResults。
    ''' </summary>
    Protected Overrides Async Function GenerateAndRunScriptAsync(llm As LLMClient, plan As ModulePlan, [step] As [Step], cancellationToken As CancellationToken) As Task
        ' 在循环外一次性读取 kb.json 知识库内容，复用于每个数据组的注释提示词
        Dim kbContent = ReadKnowledgeBaseContent()
        ' 读取研究主题
        Dim researchTopic As String = If(Not _context.ResearchTopic.StringEmpty(, True), _context.ResearchTopic, "(未提供)")
        Dim data = [step].rscript_path.GetTagValue(":")
        Dim groupIndex As Integer = Integer.Parse(data.Name)
        Dim folderPath As String = data.Value

        Try
            Await ProcessUserDataGroupAsync(folderPath, groupIndex, kbContent, researchTopic, plan, [step], cancellationToken)
        Catch ex As Exception
            ' 单个文件夹失败不影响其他文件夹
            LogInfo($"[警告] 用户数据文件夹 {groupIndex} ({folderPath}) 处理失败：{ex.Message}")
            LogInfo(ex.StackTrace)
        End Try
    End Function

    ''' <summary>处理单个用户数据文件夹组</summary>
    Private Async Function ProcessUserDataGroupAsync(folderPath As String, groupIndex As Integer, kbContent As String, researchTopic As String, plan As ModulePlan, [step] As [Step], cancellationToken As CancellationToken) As Task
        ' 1. 验证文件夹是否存在
        If Not Directory.Exists(folderPath) Then
            LogInfo($"[跳过] 文件夹不存在：{folderPath}")
            Return
        End If

        ' 2. 递归扫描该文件夹下的所有 CSV 文件
        Dim csvFiles = CollectUserCsvFiles(folderPath)
        If csvFiles.Count = 0 Then
            LogInfo($"[跳过] 文件夹 {folderPath} 中未发现 CSV 文件")
            Return
        End If

        Dim folderName As String = Path.GetFileName(folderPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar))
        If folderName.StringEmpty(, True) Then
            folderName = $"data_group_{groupIndex}"
        End If

        LogInfo($"正在处理用户数据组 {groupIndex} ({folderName})：发现 {csvFiles.Count} 个 CSV 文件")

        ' 3. 创建该组的输出目录并预构造 ModuleResult
        Dim outputDir As String = Path.Combine(_context.AnalysisDir, $"{groupIndex}_{folderPath.BaseName}")
        Call outputDir.MakeDir

        Dim xlsxFileName As String = $"{groupIndex}_{folderName.NormalizePathString(alphabetOnly:=False).Replace(" ", "_").ToLower}.xlsx"

        Dim moduleResult As New ModuleResult With {
            .ModuleName = folderName,
            .ModuleIndex = groupIndex,
            .Goal = "(待 LLM 生成)",
            .Conclusion = "",
            .OutputDir = outputDir,
            .Workdir = folderPath
        }

        ' 4. 第一次 LLM 调用：结合研究主题和知识库，生成该组数据的分析目标（Goal）和每张 sheet 的英文注释 JSON
        Dim goalJson As SheetAnnotations = Await GenerateGoalAndAnnotationsForGroupAsync(folderPath, csvFiles, xlsxFileName, researchTopic, kbContent, cancellationToken)

        ' 提取 Goal
        Dim goal As String = ExtractGoalFromJson(goalJson, folderName)
        moduleResult.Goal = goal

        ' 保存完整注释 JSON（含 goal 和 sheets）
        Dim descPath = Path.Combine(outputDir, "table_descriptions.json")
        Call goalJson.ToString.SaveTo(descPath)
        LogInfo($"组 {groupIndex} 目标与注释 JSON 已保存：{descPath}")

        ' 5. 第二次 LLM 调用：编写并执行生成 xlsx 的 R 脚本
        Dim prompt = BuildRScriptPrompt(descPath, outputDir, xlsxFileName, folderName, groupIndex, plan, [step])
        Using llmRscript As LLMClient = _config.CreateLLMClient(FolderBaseName & "-xlsx_group_" & groupIndex, _context.TmpDir)
            Call RegisterTools(llmRscript, True)
            Await llmRscript.Chat(prompt, cancellationToken)
        End Using
        LogInfo($"组 {groupIndex} ({folderName}) 的 xlsx 已生成：{Path.Combine(outputDir, xlsxFileName)}")

        ' 6. 第三次 LLM 调用：生成该组数据的阶段性中文总结
        Dim conclusion = Await GenerateConclusionForGroupAsync(folderName, csvFiles, goal, researchTopic, kbContent, cancellationToken)
        Dim conclusionPath = Path.Combine(outputDir, "conclusion.md")
        Call conclusion.SaveTo(conclusionPath)
        moduleResult.Conclusion = conclusion
        LogInfo($"组 {groupIndex} 总结已保存：{conclusionPath}")

        ' 7. 将 ModuleResult 添加到上下文
        _context.ModuleResults.Add(moduleResult)
        LogInfo($"组 {groupIndex} ({folderName}) 处理完成")
    End Function

    ''' <summary>解析 dirs 文件，返回有效文件夹路径列表</summary>
    Private Iterator Function ParseDirsFile(dirsFile As String) As IEnumerable(Of String)
        Try
            For Each line As String In File.ReadLines(dirsFile, Encoding.UTF8)
                Dim trimmed = line.Trim()
                ' 跳过空行和 # 注释行
                If trimmed.StringEmpty(, True) OrElse trimmed.StartsWith("#") Then
                    Continue For
                End If

                Yield trimmed.Trim(""""c)
            Next
        Catch ex As Exception
            LogInfo($"[错误] 读取 dirs 文件失败 ({dirsFile})：{ex.Message}")
        End Try
    End Function

    ''' <summary>递归收集指定文件夹下的所有 CSV 文件</summary>
    Private Function CollectUserCsvFiles(folderPath As String) As List(Of String)
        Dim result As New List(Of String)()
        Try
            result.AddRange(Directory.GetFiles(folderPath, "*.csv", SearchOption.AllDirectories))
        Catch ex As Exception
            LogInfo($"[警告] 扫描文件夹失败 ({folderPath})：{ex.Message}")
        End Try
        Return result
    End Function

    ''' <summary>
    ''' 读取 kb.json 知识库内容并截断至 30000 字符，返回字符串。
    ''' 与 Module13 的 ReadKnowledgeBaseContent 保持一致的逻辑。
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
    ''' 第一次 LLM 调用：结合研究主题和知识库内容，
    ''' 生成该组数据的分析目标（Goal）和每张 sheet 的英文注释说明。
    ''' 返回包含 goal 和 sheets 字段的 JSON 字符串。
    ''' </summary>
    Private Async Function GenerateGoalAndAnnotationsForGroupAsync(folderName As String, csvFiles As List(Of String), xlsxfile$, researchTopic As String, kbContent As String, cancellationToken As CancellationToken) As Task(Of SheetAnnotations)
        ' 构建骨架 JSON
        Dim sk As New SheetAnnotations With {
            .goal = "<write the goal at here>",
            .module_name = folderName.BaseName,
            .xlsx_file = xlsxfile,
            .sheets = csvFiles _
                .Select(Function(path)
                            Return New SheetAnnotations.Sheet With {
                                .annotation = "",
                                .csv = path,
                                .sheet_name = SanitizeSheetName(path)
                            }
                        End Function) _
                .ToArray
        }
        Dim skeleton = sk.ToString()

        ' 构建每个 sheet 的表头信息
        Dim headersInfo As New Text.StringBuilder()
        headersInfo.AppendLine($"## 用户数据文件夹: {folderName}")
        For Each csv In csvFiles
            Dim hdr = GetCsvHeader(csv)
            headersInfo.AppendLine($"- CSV文件: {Path.GetFileName(csv)} ({csv})")
            headersInfo.AppendLine($"  工作表名: {SanitizeSheetName(csv)}")
            headersInfo.AppendLine($"  列数 ({hdr.Count}): {String.Join(", ", hdr)}")
        Next

        Using llm As LLMClient = _config.CreateLLMClient(FolderBaseName & "-goal_comment_group", _context.TmpDir)
            Call RegisterFileTools(llm, allowWriteFile:=False, wsDir:=folderName)

            Dim prompt As String = <root><![CDATA[
你是一位生物信息学数据分析师。你的任务有两个：
1. 为用户提供的一组 CSV 结果数据推断分析目标（Goal）
2. 为每个工作表的第一行编写英文注释文本

# 用户研究主题
{RESEARCH_TOPIC}

# 知识库 (kb.json)
{KB_CONTENT}

# 用户数据文件夹
文件夹名: {FOLDER_NAME}

# 该文件夹中的 CSV 文件（每个文件对应一个工作表）
{HEADERS}

# 表格描述骨架 (JSON)
以下 JSON 列出了该文件夹中应包含的 CSV 文件（工作表）。'annotation' 字段当前为空。

{SKELETON}

# 你的任务
1. 填写 'goal' 字段（字符串）：基于研究主题和 CSV 数据内容，推测该组数据的研究分析目标，用中文描述（1-2 句话）。
2. 为每个工作表填写 'annotation' 字段（字符串）：内容为清晰的英文描述，将放置在该工作表的第一行。注释须：
   - 说明该表包含的数据/内容
   - 解释每一列的含义（使用上方提供的该 CSV 的列列表）
   - 将表格内容与用户研究主题关联，在适用时关联知识库中的相关生物学知识
   - 说明用户可从该表获得的生物学知识/见解
保持信息丰富但简洁（通常 2-5 句）。你还可以优化 'sheet_name' 为更清晰的英文名称（<=31 字符，不含 : \ / ? * [ ] 字符），但你必须保持 'csv' 绝对路径与给定值完全一致。

仅返回填写完成的 JSON（不要额外解释，不要 markdown 代码围栏）。
]]></root>.Value

            prompt = prompt.Replace("{RESEARCH_TOPIC}", researchTopic) _
                           .Replace("{KB_CONTENT}", kbContent) _
                           .Replace("{FOLDER_NAME}", folderName) _
                           .Replace("{HEADERS}", headersInfo.ToString()) _
                           .Replace("{SKELETON}", skeleton)

            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim json = resp.ExtractJsonFromResponse
            Dim result As SheetAnnotations = SheetAnnotations.ParseJSON(json)

            If Not result Is Nothing Then
                Return result
            End If
        End Using

        ' LLM 调用失败时回退到骨架
        Return sk
    End Function

    ''' <summary>从 LLM 返回的 JSON 中提取 goal 字段</summary>
    ''' <remarks>
    ''' 使用 LenientJsonParser 解析 JSON，兼容 LLM 返回的各种格式变体。
    ''' </remarks>
    Private Function ExtractGoalFromJson(json As SheetAnnotations, fallbackName As String) As String
        If Not json.goal.StringEmpty(, True) Then
            Return json.goal
        End If
        Return $"用户数据组: {fallbackName}"
    End Function

    ''' <summary>LLM 返回的 goal + annotations JSON 的轻量解析类</summary>
    Private Class GoalAnnotationBrief
        Public Property goal As String
    End Class

    ''' <summary>
    ''' 构建第二次 LLM 调用的提示词：要求 LLM 编写基于 openxlsx 的 R 脚本，
    ''' 按规定的样式读取 CSV 与注释 JSON，生成单个 xlsx 结果文件。
    ''' 样式与 Module13 完全一致。
    ''' </summary>
    Private Function BuildRScriptPrompt(descPath As String, outputDir As String, xlsxFileName As String, folderName As String, groupIndex As Integer, plan As ModulePlan, [step] As [Step]) As String
        Dim prompt As String = <root><![CDATA[
你是一位生物信息学 R 脚本专家。请编写一个完整的 R 脚本，使用 openxlsx 包将用户提供的 CSV 结果表编译为一个结构化、带样式的 XLSX 文件。

# 输入
- JSON 文件路径: {DESC_PATH}
  描述了要创建的 XLSX 文件、包含的 CSV 文件（工作表），以及每个工作表第一行的英文注释文本。
- XLSX 文件输出目录: {OUT_DIR}
- XLSX 文件名: {XLSX_FILE}

# 计划执行上下文
- 用户数据文件夹: {FOLDER_NAME}（组 {GROUP_INDEX}）
- 计划目标: {PLAN_GOAL}
- 当前执行步骤: {STEP}
- 所有脚本和生成的文件放置在指定临时工作区目录: {WORKSPACE}

# JSON 结构 (table_descriptions.json)
{
  'goal': '<分析目标字符串>',
  'folder_name': '<文件夹名称>',
  'xlsx_file': '<xlsx文件名>',
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
读取并修改这个R脚本：{R_TEMPLATE}/xlsxTable.R

# 重要注意事项
- 使用绝对路径。
- 确保数值列保持数值类型（不要作为文本处理）。
- 脚本须可端到端运行，无需额外输入。

# 执行说明
- 使用 write_file 工具将 R 脚本写入工作区文件（如 'user_data_tables_group_{GROUP_INDEX}.R'）
- 使用 run_rscript 工具执行该 R 脚本
- 验证 XLSX 文件已在输出目录中成功生成
]]></root>.Value

        prompt = prompt.Replace("{DESC_PATH}", descPath) _
                       .Replace("{OUT_DIR}", outputDir) _
                       .Replace("{XLSX_FILE}", xlsxFileName) _
                       .Replace("{FOLDER_NAME}", folderName) _
                       .Replace("{GROUP_INDEX}", groupIndex.ToString()) _
                       .Replace("{PLAN_GOAL}", plan.goal) _
                       .Replace("{STEP}", JsonContract.GetJson([step])) _
                       .Replace("{WORKSPACE}", Workspace.GetDirectoryFullPath) _
                       .Replace("{R_TEMPLATE}", AgentConfig.RScriptsDir)
        Return prompt
    End Function

    ''' <summary>
    ''' 第三次 LLM 调用：结合分析目标和 CSV 数据内容，
    ''' 生成该用户数据组的阶段性中文总结，保存为 conclusion.md。
    ''' </summary>
    Private Async Function GenerateConclusionForGroupAsync(folderName As String, csvFiles As List(Of String), goal As String, researchTopic As String, kbContent As String, cancellationToken As CancellationToken) As Task(Of String)
        ' 构建 CSV 概览信息（文件名 + 行数 + 表头）
        Dim csvOverview As New Text.StringBuilder()
        csvOverview.AppendLine($"## 用户数据文件夹: {folderName}")
        For Each csv In csvFiles
            Dim filename = Path.GetFileName(csv)
            Dim hdr = GetCsvHeader(csv)
            Dim rowCount As String = "未知"
            Try
                ' 只统计行数，不加载全部数据
                rowCount = (File.ReadLines(csv).Count() - 1).ToString()
            Catch
            End Try
            csvOverview.AppendLine($"- {filename}：{rowCount} 行数据，列 ({hdr.Count}): {String.Join(", ", hdr)}")
        Next

        Using llm As LLMClient = _config.CreateLLMClient(FolderBaseName & "-conclusion_group", _context.TmpDir)
            Call RegisterTools(llm, False)

            Dim prompt As String = <root><![CDATA[
你是一位生物医学研究专家。请基于以下用户自行分析得到的结果数据，撰写中文阶段性总结。

# 用户研究主题
{RESEARCH_TOPIC}

# 该组数据的分析目标
{GOAL}

# 知识库 (kb.json)
{KB_CONTENT}

# 该组数据的 CSV 文件概览
{CSV_OVERVIEW}

# 你的任务
使用 list_tree、peek_csv 等工具查看 CSV 文件的实际内容，然后撰写中文总结，涵盖以下内容：
1. 该组数据包含了哪些类型的结果数据
2. 数据的主要特征和关键发现（如有）
3. 该组数据与用户研究主题的关联性
4. 从该组数据可以得出哪些生物学见解

不要写入任何文件，仅以 Markdown 格式生成总结文本并返回。总结应为 400-800 字中文。内容须具体严谨，不得编造数据。
]]></root>.Value

            prompt = prompt.Replace("{RESEARCH_TOPIC}", researchTopic) _
                           .Replace("{GOAL}", goal) _
                           .Replace("{KB_CONTENT}", kbContent) _
                           .Replace("{CSV_OVERVIEW}", csvOverview.ToString())

            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Return resp.output
        End Using
    End Function

End Class

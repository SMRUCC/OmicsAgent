Imports Microsoft.VisualBasic.MIME.application.json
Imports Microsoft.VisualBasic.MIME.application.json.Javascript
Imports Ollama
Imports Researcher

' ============================================================================
' 知识库构建模块 - 文献检索与生物学知识提取
' ============================================================================

''' <summary>
''' 知识库构建器，负责根据用户研究主题检索相关文献，
''' 并从文献中提取生物学知识信息，生成结构化的 kb.json 知识库文件。
''' 
''' 工作流程：
''' 1. 若用户已提供参考文献文件夹，则直接读取其中的 txt 文件
''' 2. 若未提供参考文献，但 INI 配置了自动检索，则根据检索策略：
'''    - mysql：从本地 MySQL PubMed 镜像检索
'''    - ncbi：通过 Python 脚本从 NCBI 在线检索
''' 3. 将检索到的文献保存为 txt 文件到 research_kb/ 目录
''' 4. 调用 LLM 从文献中提取生物学知识，生成 kb.json
''' </summary>
Public Class KnowledgeBaseBuilder

    Private ReadOnly _config As AgentConfig
    Private ReadOnly _context As AnalysisContext
    Private ReadOnly _logger As Action(Of String)
    Private ReadOnly _llmFactory As Func(Of LLMClient)

    Public Sub New(config As AgentConfig, context As AnalysisContext, llmFactory As Func(Of LLMClient), Optional logger As Action(Of String) = Nothing)
        _config = config
        _context = context
        _llmFactory = llmFactory
        _logger = If(logger, AddressOf Console.WriteLine)
    End Sub

    ''' <summary>
    ''' 执行知识库构建流程
    ''' </summary>
    Public Async Function BuildAsync(cancellationToken As CancellationToken) As Task
        LogInfo("========== 知识库构建 ==========")

        ' 1. 确保知识库目录存在
        _context.KnowledgeDir.MakeDir

        ' 2. 处理参考文献
        Dim referenceFiles = CollectReferenceFiles()
        If referenceFiles.Count = 0 AndAlso _config.Literature.AutoSearchLiterature Then
            LogInfo("未提供参考文献，根据 INI 配置自动检索文献...")
            referenceFiles = Await SearchLiteratureAsync(_context.ResearchTopic, cancellationToken)
        End If

        LogInfo($"共收集到 {referenceFiles.Count} 篇参考文献")

        ' 3. 调用 LLM 提取生物学知识
        If referenceFiles.Count > 0 Then
            Await ExtractKnowledgeAsync(referenceFiles, cancellationToken)
        Else
            LogInfo("无参考文献可用，将使用 LLM 自身训练知识生成 kb.json")
            Await GenerateKnowledgeFromLLMAsync(cancellationToken)
        End If

        LogInfo($"知识库已生成：{_context.KnowledgeBaseFile}")
    End Function

    ''' <summary>收集用户提供的参考文献 txt 文件</summary>
    Private Function CollectReferenceFiles() As List(Of String)
        Dim result As New List(Of String)()
        If String.IsNullOrEmpty(_context.ReferenceDir) OrElse Not Directory.Exists(_context.ReferenceDir) Then
            Return result
        End If

        For Each f In Directory.GetFiles(_context.ReferenceDir, "*.txt")
            ' 复制到 research_kb 目录
            Dim dst = Path.Combine(_context.KnowledgeDir, Path.GetFileName(f))
            If Not File.Exists(dst) Then
                File.Copy(f, dst, True)
            End If
            result.Add(dst)
        Next

        Return result
    End Function

    ''' <summary>根据检索策略搜索文献</summary>
    Private Async Function SearchLiteratureAsync(researchTopic As String, cancellationToken As CancellationToken) As Task(Of List(Of String))
        Select Case _config.Literature.LiteratureSearchStrategy.ToLower()
            Case "none"
                ' 显式不自动检索文献：直接使用用户提供的参考文献（若有）或 LLM 自身知识
                LogInfo("文献检索策略为 none，跳过自动检索")
                Return New List(Of String)()
            Case "mysql"
                Return SearchFromMySql(researchTopic)
            Case "ncbi"
                Return Await SearchFromNcbiAsync(researchTopic, cancellationToken)
            Case Else
                ' 未知策略属于配置错误，应报错终止而非静默回退到 none
                Throw New InvalidOperationException($"未知的文献检索策略：{_config.Literature.LiteratureSearchStrategy}。合法值为 mysql / ncbi / none，请检查 config.ini 的 [literature] strategy 配置。")
        End Select
    End Function

    ''' <summary>从本地 MySQL PubMed 镜像检索文献</summary>
    Private Function SearchFromMySql(researchTopic As String) As List(Of String)
        Dim result As New List(Of String)()
        Try
            Dim pubmedTool As New PubMedQueryTool(_config.GetMySqlConnectionString())
            ' 调用 LLM 提取搜索关键词
            Dim keywords = ExtractSearchKeywords(researchTopic).Result
            LogInfo($"提取的搜索关键词：{String.Join(", ", keywords)}")

            For Each kw In keywords
                Dim json = pubmedTool.search_papers(kw, max_results:=_config.Literature.MaxLiteratureCount \ keywords.Count)
                Dim papers = ParseSearchResults(json)
                For Each paper In papers
                    Dim fileName = $"ref_{result.Count + 1}_{SafeFileName(paper("title"))}.txt"
                    Dim filePath = Path.Combine(_context.KnowledgeDir, fileName)
                    File.WriteAllText(filePath, FormatPaperText(paper), Encoding.UTF8)
                    result.Add(filePath)
                Next
                If result.Count >= _config.Literature.MaxLiteratureCount Then Exit For
            Next
        Catch ex As Exception
            LogInfo($"[警告] MySQL 文献检索失败：{ex.Message}")
        End Try
        Return result
    End Function

    ''' <summary>通过 Python 脚本从 NCBI 在线检索文献</summary>
    Private Async Function SearchFromNcbiAsync(researchTopic As String, cancellationToken As CancellationToken) As Task(Of List(Of String))
        Dim result As New List(Of String)()
        Try
            Dim keywords = Await ExtractSearchKeywords(researchTopic)
            LogInfo($"提取的搜索关键词：{String.Join(", ", keywords)}")

            ' 生成 Python 检索脚本
            Dim pyScript = Path.Combine(_context.ScriptsDir, "search_pubmed.py")
            File.WriteAllText(pyScript, GenerateNcbiSearchScript(keywords, _config.Literature.MaxLiteratureCount, _context.KnowledgeDir), Encoding.UTF8)

            ' 执行 Python 脚本
            Dim shell As New ShellTool(_config, _context.WorkspaceDir, _logger)
            Dim runResult = shell.run_python("scripts/search_pubmed.py", timeout_seconds:=300)
            LogInfo($"Python 检索脚本执行结果：{runResult.Substring(0, Math.Min(200, runResult.Length))}...")

            ' 读取生成的 txt 文件
            For Each f In Directory.GetFiles(_context.KnowledgeDir, "ref_*.txt")
                result.Add(f)
            Next

            ' 补充获取存在 PMC 全文记录的文献全文（agent_glm.txt 第 34 行要求检索 PMC 全文）
            FetchPmcFullText()
        Catch ex As Exception
            LogInfo($"[警告] NCBI 在线文献检索失败：{ex.Message}")
        End Try
        Return result
    End Function

    ''' <summary>
    ''' 在 NCBI 摘要检索之后，补充获取存在 PubMed Central 全文记录的文献全文内容。
    ''' 需求（agent_glm.txt 第 34 行）：NCBI 检索应获取标题、引用、摘要以及 PMC 全文（若可用）。
    ''' </summary>
    Private Sub FetchPmcFullText()
        Try
            Dim scriptPath = Path.Combine(_context.ScriptsDir, "fetch_pmc.py")
            File.WriteAllText(scriptPath, GeneratePmcFetchScript(_context.KnowledgeDir), Encoding.UTF8)

            Dim shell As New ShellTool(_config, _context.WorkspaceDir, _logger)
            Dim runResult = shell.run_python("scripts/fetch_pmc.py", timeout_seconds:=300)
            LogInfo($"PMC 全文获取脚本执行结果：{runResult.Substring(0, Math.Min(200, runResult.Length))}...")
        Catch ex As Exception
            ' PMC 全文获取失败不应中断已检索到的摘要的使用
            LogInfo($"[警告] PMC 全文获取失败（不影响已检索到的摘要）：{ex.Message}")
        End Try
    End Sub

    ''' <summary>
    ''' 读取 PMC 全文获取 Python 模板脚本，替换 {KNOWLEDGE_DIR} 占位符后返回最终脚本内容。
    ''' 模板文件位于 agent/python/pmc_fetch_template.py，基于 Bio.Entrez 将 pubmed PMID 关联至 pmc，
    ''' 若存在 PMC 全文记录则 efetch 全文并追加到对应的 ref_*.txt 文件末尾。
    ''' </summary>
    Private Function GeneratePmcFetchScript(outputDir As String) As String
        Dim templatePath = Path.Combine(AgentConfig.PythonScriptsDir, "pmc_fetch_template.py")
        If Not File.Exists(templatePath) Then
            Throw New FileNotFoundException($"未找到 PMC 全文获取 Python 模板脚本：{templatePath}。请确认 agent/python 目录下存在 pmc_fetch_template.py。")
        End If
        Dim template = templatePath.ReadAllText
        Return template.Replace("{KNOWLEDGE_DIR}", outputDir)
    End Function

    ''' <summary>调用 LLM 提取搜索关键词</summary>
    Private Async Function ExtractSearchKeywords(researchTopic As String) As Task(Of List(Of String))
        Dim keywords As New List(Of String)()
        Try
            Using llm = _llmFactory()
                Dim prompt = $"You are a biomedical research assistant. Based on the following research topic description, extract 3-5 English search keywords that would be most effective for finding relevant scientific literature in PubMed. 
Return ONLY the keywords, one per line, without numbering or other text." & vbCrLf & vbCrLf &
$"Research topic:{vbCrLf}{researchTopic}"

                Dim resp = Await llm.Chat(prompt)
                For Each line In resp.output.Split({vbCrLf, vbLf}, StringSplitOptions.RemoveEmptyEntries)
                    Dim kw = line.Trim().Trim("-"c, "*"c, " "c)
                    If kw.Length > 0 Then keywords.Add(kw)
                Next
            End Using
        Catch ex As Exception
            LogInfo($"[警告] LLM 关键词提取失败：{ex.Message}")
            ' 回退：直接按空格切分研究主题
            keywords = researchTopic.Split({" "c, ","c, vbCrLf, vbLf}, StringSplitOptions.RemoveEmptyEntries).
                                      Where(Function(s) s.Trim().Length > 1).
                                      Take(5).ToList()
        End Try
        Return keywords
    End Function

    ''' <summary>
    ''' 调用 LLM 从文献中提取生物学知识，生成 kb.json。
    ''' 采用两阶段流水线：
    '''   阶段一 - 逐篇提取：每篇文献单独调用 LLM 提取知识点，保存为 per_doc_N.json
    '''   阶段二 - 全局汇总：读取所有单篇提取结果，交由 LLM 整合为最终 kb.json
    ''' </summary>
    Private Async Function ExtractKnowledgeAsync(referenceFiles As List(Of String), cancellationToken As CancellationToken) As Task
        LogInfo("正在从文献中提取生物学知识（逐篇处理）...")

        ' ========== 第一阶段：逐篇提取知识 ==========
        Dim perDocFiles As New List(Of String)()
        For i As Integer = 0 To referenceFiles.Count - 1
            Dim f = referenceFiles(i)
            Dim fileName = Path.GetFileName(f)
            LogInfo($"  [{i + 1}/{referenceFiles.Count}] 正在分析文献：{fileName}")

            Try
                Dim content = File.ReadAllText(f, Encoding.UTF8)
                Using llm = _llmFactory()
                    Dim prompt = BuildPerDocumentExtractionPrompt(_context.ResearchTopic, content, fileName)
                    Dim resp = Await llm.Chat(prompt, cancellationToken)
                    Dim perDocJson = resp.ExtractJsonFromResponse
                    If String.IsNullOrEmpty(perDocJson) Then
                        ' 如果提取不到结构化的 JSON，将原始输出包装为 JSON
                        perDocJson = $"{{""source_file"": ""{EscapeJson(fileName)}"", ""raw_output"": ""{EscapeJson(resp.output)}""}}"
                    End If
                    ' 保存单篇提取结果
                    Dim perDocPath = Path.Combine(_context.KnowledgeDir, $"per_doc_{i + 1}.json")
                    File.WriteAllText(perDocPath, perDocJson, Encoding.UTF8)
                    perDocFiles.Add(perDocPath)
                    LogInfo($"    已保存单篇提取结果：{perDocPath}")
                End Using
            Catch ex As Exception
                LogInfo($"[警告] 文献 {fileName} 知识提取失败：{ex.Message}")
                ' 继续处理下一篇文献
            End Try
        Next

        If perDocFiles.Count = 0 Then
            LogInfo("[警告] 所有文献逐篇提取均失败，回退到 LLM 自身训练知识生成 kb.json")
            Await GenerateKnowledgeFromLLMAsync(cancellationToken)
            Return
        End If

        ' ========== 第二阶段：全局汇总 ==========
        LogInfo($"逐篇提取完成，共 {perDocFiles.Count} 篇有效结果，正在汇总...")

        ' 读取所有单篇提取结果
        Dim allExtractions As New StringBuilder()
        For Each f In perDocFiles
            Dim extractionContent = File.ReadAllText(f, Encoding.UTF8)
            allExtractions.AppendLine(extractionContent)
            allExtractions.AppendLine()
        Next
        Dim combinedExtractions = allExtractions.ToString()

        Try
            Using llm = _llmFactory()
                Dim prompt = BuildSummaryPrompt(_context.ResearchTopic, combinedExtractions)
                Dim resp = Await llm.Chat(prompt, cancellationToken)
                Dim kbJson = resp.ExtractJsonFromResponse
                If Not String.IsNullOrEmpty(kbJson) Then
                    File.WriteAllText(_context.KnowledgeBaseFile, kbJson, Encoding.UTF8)
                Else
                    ' 回退：直接保存 LLM 输出文本
                    Dim fallback = $"{{""research_topic"": ""{EscapeJson(_context.ResearchTopic)}"", ""summary"": ""{EscapeJson(resp.output)}"", ""references"": []}}"
                    File.WriteAllText(_context.KnowledgeBaseFile, fallback, Encoding.UTF8)
                End If
            End Using
        Catch ex As Exception
            LogInfo($"[警告] 知识汇总失败：{ex.Message}")
            ' 回退：已逐篇提取了知识点，汇总失败不影响中间文件
            Dim fallback = $"{{""research_topic"": ""{EscapeJson(_context.ResearchTopic)}"", ""summary"": ""Error during summarization: {EscapeJson(ex.Message)}. Individual extraction files are available in research_kb/per_doc_*.json."", ""references"": []}}"
            File.WriteAllText(_context.KnowledgeBaseFile, fallback, Encoding.UTF8)
        End Try
    End Function

    ''' <summary>无参考文献时，使用 LLM 自身训练知识生成 kb.json</summary>
    Private Async Function GenerateKnowledgeFromLLMAsync(cancellationToken As CancellationToken) As Task
        LogInfo("使用 LLM 自身训练知识生成知识库...")
        Try
            Using llm = _llmFactory()
                Dim prompt = BuildKnowledgeFromLLMPrompt(_context.ResearchTopic)
                Dim resp = Await llm.Chat(prompt, cancellationToken)
                Dim kbJson = resp.ExtractJsonFromResponse
                If String.IsNullOrEmpty(kbJson) Then
                    kbJson = $"{{""research_topic"": ""{EscapeJson(_context.ResearchTopic)}"", ""summary"": ""{EscapeJson(resp.output)}"", ""references"": []}}"
                End If
                File.WriteAllText(_context.KnowledgeBaseFile, kbJson, Encoding.UTF8)
            End Using
        Catch ex As Exception
            LogInfo($"[警告] LLM 知识生成失败：{ex.Message}")
            Dim fallback = $"{{""research_topic"": ""{EscapeJson(_context.ResearchTopic)}"", ""error"": ""{EscapeJson(ex.Message)}"", ""references"": []}}"
            File.WriteAllText(_context.KnowledgeBaseFile, fallback, Encoding.UTF8)
        End Try
    End Function

    ''' <summary>构建知识提取提示词</summary>
    Public Shared Function BuildKnowledgeExtractionPrompt(researchTopic As String, literatureContent As String) As String
        Dim sb As New StringBuilder()
        sb.AppendLine("You are a biomedical research assistant. Based on the following research topic and reference literature, extract structured biological knowledge and return it as a JSON object.")
        sb.AppendLine()
        sb.AppendLine("Research topic:")
        sb.AppendLine(researchTopic)
        sb.AppendLine()
        sb.AppendLine("Reference literature content:")
        sb.AppendLine(literatureContent)
        sb.AppendLine()
        sb.AppendLine("Please extract the following information and return as JSON:")
        sb.AppendLine("{")
        sb.AppendLine("  ""research_topic"": ""<brief summary of the research topic>"",")
        sb.AppendLine("  ""disease_or_phenotype"": ""<disease or biological phenotype being studied>"",")
        sb.AppendLine("  ""organism"": ""<organism/species information>"",")
        sb.AppendLine("  ""tissue"": ""<tissue or sample source>"",")
        sb.AppendLine("  ""key_genes_proteins"": [""<gene/protein 1>"", ""<gene/protein 2>"", ...],")
        sb.AppendLine("  ""key_pathways"": [""<pathway 1>"", ""<pathway 2>"", ...],")
        sb.AppendLine("  ""key_metabolites"": [""<metabolite 1>"", ""<metabolite 2>"", ...],")
        sb.AppendLine("  ""biological_mechanisms"": [")
        sb.AppendLine("    {""mechanism"": ""<description>"", ""evidence"": ""<supporting evidence from literature>""},")
        sb.AppendLine("    ...")
        sb.AppendLine("  ],")
        sb.AppendLine("  ""comparison_design_suggestions"": [")
        sb.AppendLine("    {""comparison"": ""<group A vs group B>"", ""purpose"": ""<biological purpose>""},")
        sb.AppendLine("    ...")
        sb.AppendLine("  ],")
        sb.AppendLine("  ""expected_findings"": [""<expected finding 1>"", ...],")
        sb.AppendLine("  ""references"": [")
        sb.AppendLine("    {""title"": ""<paper title>"", ""key_finding"": ""<key finding from this paper>""},")
        sb.AppendLine("    ...")
        sb.AppendLine("  ]")
        sb.AppendLine("}")
        sb.AppendLine()
        sb.AppendLine("Return ONLY the JSON object, no other text.")
        Return sb.ToString()
    End Function

    ''' <summary>构建无参考文献时的知识生成提示词</summary>
    Private Shared Function BuildKnowledgeFromLLMPrompt(researchTopic As String) As String
        Dim sb As New StringBuilder()
        sb.AppendLine("You are a biomedical research assistant. Based on the following research topic, use your training knowledge to generate a structured biological knowledge base. Return it as a JSON object.")
        sb.AppendLine()
        sb.AppendLine("Research topic:")
        sb.AppendLine(researchTopic)
        sb.AppendLine()
        sb.AppendLine("IMPORTANT: Only include biological knowledge that you are confident about. Do NOT fabricate information. If you are unsure about something, omit it.")
        sb.AppendLine()
        sb.AppendLine("Please return the following JSON structure:")
        sb.AppendLine("{")
        sb.AppendLine("  ""research_topic"": ""<brief summary>"",")
        sb.AppendLine("  ""disease_or_phenotype"": ""<disease or phenotype>"",")
        sb.AppendLine("  ""organism"": ""<organism>"",")
        sb.AppendLine("  ""tissue"": ""<tissue>"",")
        sb.AppendLine("  ""key_genes_proteins"": [""<gene 1>"", ...],")
        sb.AppendLine("  ""key_pathways"": [""<pathway 1>"", ...],")
        sb.AppendLine("  ""key_metabolites"": [""<metabolite 1>"", ...],")
        sb.AppendLine("  ""biological_mechanisms"": [")
        sb.AppendLine("    {""mechanism"": ""<description>"", ""evidence"": ""<general biological knowledge>""},")
        sb.AppendLine("    ...")
        sb.AppendLine("  ],")
        sb.AppendLine("  ""comparison_design_suggestions"": [")
        sb.AppendLine("    {""comparison"": ""<group A vs group B>"", ""purpose"": ""<purpose>""},")
        sb.AppendLine("    ...")
        sb.AppendLine("  ],")
        sb.AppendLine("  ""expected_findings"": [""<finding 1>"", ...],")
        sb.AppendLine("  ""references"": []")
        sb.AppendLine("}")
        sb.AppendLine()
        sb.AppendLine("Return ONLY the JSON object, no other text.")
        Return sb.ToString()
    End Function

    ''' <summary>构建单篇文献知识点提取提示词</summary>
    Private Function BuildPerDocumentExtractionPrompt(researchTopic As String, docContent As String, fileName As String) As String
        Dim sb As New StringBuilder()
        sb.AppendLine("You are a biomedical research assistant. Based on the following research topic and a single reference paper, extract all relevant biological knowledge from this paper. Return it as a JSON object.")
        sb.AppendLine()
        sb.AppendLine("Research topic:")
        sb.AppendLine(researchTopic)
        sb.AppendLine()
        sb.AppendLine($"Paper file: {fileName}")
        sb.AppendLine()
        sb.AppendLine("Paper content:")
        sb.AppendLine(docContent)
        sb.AppendLine()
        sb.AppendLine("Please extract the following biological knowledge specifically from this paper:")
        sb.AppendLine("{")
        sb.AppendLine("  ""source_file"": ""<the file name of this paper>"",")
        sb.AppendLine("  ""key_genes_proteins"": [""<gene/protein mentioned in this paper>"", ...],")
        sb.AppendLine("  ""key_pathways"": [""<pathway mentioned in this paper>"", ...],")
        sb.AppendLine("  ""key_metabolites"": [""<metabolite mentioned in this paper>"", ...],")
        sb.AppendLine("  ""biological_mechanisms"": [")
        sb.AppendLine("    {""mechanism"": ""<description>"", ""evidence"": ""<supporting evidence from this paper>""},")
        sb.AppendLine("    ...")
        sb.AppendLine("  ],")
        sb.AppendLine("  ""key_findings"": [""<key finding 1 from this paper>"", ...],")
        sb.AppendLine("  ""relevance_to_research_topic"": ""<how this paper relates to the research topic>""")
        sb.AppendLine("}")
        sb.AppendLine()
        sb.AppendLine("IMPORTANT:")
        sb.AppendLine("- Only include information that actually appears in this paper. Do NOT fabricate.")
        sb.AppendLine("- If a field has no relevant information in this paper, use an empty array [] or empty string.")
        sb.AppendLine("- Be specific and thorough - extract as much relevant biological detail as possible.")
        sb.AppendLine("- Return ONLY the JSON object, no other text.")
        Return sb.ToString()
    End Function

    ''' <summary>构建所有单篇提取结果的全局汇总提示词</summary>
    Private Function BuildSummaryPrompt(researchTopic As String, allExtractions As String) As String
        Dim sb As New StringBuilder()
        sb.AppendLine("You are a biomedical research assistant. Below are knowledge extraction results from multiple reference papers on the same research topic. Please synthesize, deduplicate, and consolidate ALL this information into a single comprehensive knowledge base JSON.")
        sb.AppendLine()
        sb.AppendLine("Research topic:")
        sb.AppendLine(researchTopic)
        sb.AppendLine()
        sb.AppendLine("Knowledge extracted from individual papers:")
        sb.AppendLine(allExtractions)
        sb.AppendLine()
        sb.AppendLine("Please consolidate all the above into the following JSON structure:")
        sb.AppendLine("{")
        sb.AppendLine("  ""research_topic"": ""<brief summary of the research topic>"",")
        sb.AppendLine("  ""disease_or_phenotype"": ""<disease or biological phenotype being studied>"",")
        sb.AppendLine("  ""organism"": ""<organism/species information>"",")
        sb.AppendLine("  ""tissue"": ""<tissue or sample source>"",")
        sb.AppendLine("  ""key_genes_proteins"": [""<gene/protein 1>"", ""<gene/protein 2>"", ...],")
        sb.AppendLine("  ""key_pathways"": [""<pathway 1>"", ""<pathway 2>"", ...],")
        sb.AppendLine("  ""key_metabolites"": [""<metabolite 1>"", ""<metabolite 2>"", ...],")
        sb.AppendLine("  ""biological_mechanisms"": [")
        sb.AppendLine("    {""mechanism"": ""<description>"", ""evidence"": ""<supporting evidence>""},")
        sb.AppendLine("    ...")
        sb.AppendLine("  ],")
        sb.AppendLine("  ""comparison_design_suggestions"": [")
        sb.AppendLine("    {""comparison"": ""<group A vs group B>"", ""purpose"": ""<biological purpose>""},")
        sb.AppendLine("    ...")
        sb.AppendLine("  ],")
        sb.AppendLine("  ""expected_findings"": [""<expected finding 1>"", ...],")
        sb.AppendLine("  ""references"": [")
        sb.AppendLine("    {""title"": ""<paper title>"", ""key_finding"": ""<key finding from this paper>""},")
        sb.AppendLine("    ...")
        sb.AppendLine("  ]")
        sb.AppendLine("}")
        sb.AppendLine()
        sb.AppendLine("GUIDELINES:")
        sb.AppendLine("- Merge and deduplicate genes, pathways, metabolites, and mechanisms from all papers.")
        sb.AppendLine("- Prioritize information supported by multiple papers.")
        sb.AppendLine("- If there are conflicting findings, note the conflict and include both perspectives.")
        sb.AppendLine("- Return ONLY the JSON object, no other text.")
        Return sb.ToString()
    End Function

    ''' <summary>解析 PubMed 搜索结果 JSON</summary>
    Private Function ParseSearchResults(json As String) As List(Of Dictionary(Of String, String))
        Dim result As New List(Of Dictionary(Of String, String))()
        Try
            Dim jobj As JsonObject = JsonObject.ParseJSON(json)
            Dim papers As JsonArray = jobj("papers")
            If papers IsNot Nothing Then
                For Each p In papers
                    result.Add(p.CreateObject(Of Dictionary(Of String, String))(decodeMetachar:=True))
                Next
            End If
        Catch
        End Try
        Return result
    End Function

    ''' <summary>将文献信息格式化为文本</summary>
    Private Function FormatPaperText(paper As Dictionary(Of String, String)) As String
        Dim sb As New StringBuilder()
        sb.AppendLine($"PMID: {paper("pmid")}")
        sb.AppendLine($"Title: {paper("title")}")
        sb.AppendLine($"Authors: {paper("authors")}")
        sb.AppendLine($"Journal: {paper("journal")}")
        sb.AppendLine($"Year: {paper("year")}")
        sb.AppendLine($"DOI: {paper("doi")}")
        sb.AppendLine($"MeSH Terms: {paper("mesh_terms")}")
        sb.AppendLine()
        sb.AppendLine("Abstract:")
        sb.AppendLine(paper("abstract"))
        Return sb.ToString()
    End Function

    ''' <summary>生成 NCBI 在线检索的 Python 脚本</summary>
    Private Function GenerateNcbiSearchScript(keywords As List(Of String), maxCount As Integer, outputDir As String) As String
        Dim kwList = String.Join(", ", keywords.Select(Function(k) $"""{k}"""))
        Dim templatePath = Path.Combine(AgentConfig.PythonScriptsDir, "ncbi_search_template.py")
        If Not File.Exists(templatePath) Then
            Throw New FileNotFoundException($"未找到 NCBI 检索 Python 模板脚本：{templatePath}。请确认 agent/python 目录下存在 ncbi_search_template.py。")
        End If
        Dim template = templatePath.ReadAllText
        Return template _
            .Replace("{KEYWORDS}", kwList) _
            .Replace("{MAX_RESULTS}", maxCount.ToString()) _
            .Replace("{OUTPUT_DIR}", outputDir)
    End Function

    Private Function SafeFileName(text As String) As String
        If String.IsNullOrEmpty(text) Then Return "untitled"
        Dim invalid = Path.GetInvalidFileNameChars()
        Dim sb As New StringBuilder()
        For Each c In text
            If Not invalid.Contains(c) AndAlso c <> " "c Then
                sb.Append(c)
            ElseIf c = " "c Then
                sb.Append("_"c)
            End If
        Next
        Dim result = sb.ToString()
        If result.Length > 50 Then result = result.Substring(0, 50)
        Return result
    End Function

    Private Sub LogInfo(msg As String)
        _logger?.Invoke(msg)
    End Sub

    Private Shared Function EscapeJson(input As String) As String
        If String.IsNullOrEmpty(input) Then Return ""
        Return input.Replace("\", "\\").Replace("""", "\""").Replace(vbCr, "\r").Replace(vbLf, "\n").Replace(vbTab, "\t")
    End Function

End Class

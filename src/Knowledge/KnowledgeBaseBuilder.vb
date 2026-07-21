' ============================================================================
' 知识库构建模块
' ============================================================================
Imports System.IO
Imports System.Text
Imports Ollama
Imports OmicsAgent.Config

Namespace Knowledge

    ''' <summary>
    ''' 知识库构建器：从参考文献中提取生物学知识，生成 kb.json
    ''' </summary>
    Public Class KnowledgeBaseBuilder

        Private ReadOnly _config As AppConfig
        Private ReadOnly _kbDir As String
        Private ReadOnly _referencesDir As String

        Public Sub New(config As AppConfig, kbDir As String, referencesDir As String)
            _config = config
            _kbDir = kbDir
            _referencesDir = referencesDir
        End Sub

        ''' <summary>
        ''' 构建知识库主流程
        ''' </summary>
        Public Async Function BuildAsync(researchTopic As String, llmClientFactory As Func(Of LLMClient), logger As Logger) As Task(Of String)
            logger.Phase("Knowledge Base Construction")
            IO.WorkspaceManager.EnsureDir(_kbDir)

            ' 1. 收集参考文献 txt 文件
            Dim refFiles = CollectReferenceFiles()
            logger.Info($"Found {refFiles.Count} reference text files.")

            ' 2. 如果没有参考文献，根据配置自动检索
            If refFiles.Count = 0 AndAlso _config.LiteratureSearchMode <> "none" Then
                logger.Info($"No references provided, auto-searching via mode: {_config.LiteratureSearchMode}")
                refFiles = Await AutoSearchReferencesAsync(researchTopic, llmClientFactory, logger)
            End If

            ' 3. 使用 LLM 从文献中提取生物学知识
            Dim kbPath = Path.Combine(_kbDir, "kb.json")
            If refFiles.Count = 0 Then
                logger.Warn("No reference files available. Creating empty knowledge base.")
                File.WriteAllText(kbPath, "{""topic"":""" & researchTopic.Replace("""", "\""") & """,""entries"":[]}", Encoding.UTF8)
                Return kbPath
            End If

            logger.Info("Extracting biological knowledge from references using LLM...")
            Dim kbContent = Await ExtractKnowledgeAsync(researchTopic, refFiles, llmClientFactory, logger)
            File.WriteAllText(kbPath, kbContent, Encoding.UTF8)
            logger.Info($"Knowledge base saved to: {kbPath}")
            Return kbPath
        End Function

        Private Function CollectReferenceFiles() As List(Of String)
            Dim list As New List(Of String)()
            If String.IsNullOrEmpty(_referencesDir) OrElse Not Directory.Exists(_referencesDir) Then Return list
            For Each f In Directory.GetFiles(_referencesDir, "*.txt")
                list.Add(f)
            Next
            ' 同时也复制到 kbDir 下
            For Each f In list
                Dim dest = Path.Combine(_kbDir, Path.GetFileName(f))
                Try
                    File.Copy(f, dest, True)
                Catch
                End Try
            Next
            Return list
        End Function

        Private Async Function AutoSearchReferencesAsync(topic As String, llmClientFactory As Func(Of LLMClient), logger As Logger) As Task(Of List(Of String))
            Dim refFiles As New List(Of String)()
            Select Case _config.LiteratureSearchMode.ToLower()
                Case "local_mysql"
                    Dim searcher As New PubMedLocalSearcher(_config.MysqlConnectionString, _kbDir)
                    refFiles = Await searcher.SearchAndSaveAsync(topic, llmClientFactory, logger)
                Case "ncbi_online"
                    Dim searcher As New NcbiOnlineSearcher(_config.PythonPath, _kbDir)
                    refFiles = Await searcher.SearchAndSaveAsync(topic, llmClientFactory, logger)
                Case Else
                    logger.Warn($"Unknown literature search mode: {_config.LiteratureSearchMode}")
            End Select
            Return refFiles
        End Function

        Private Async Function ExtractKnowledgeAsync(topic As String, refFiles As List(Of String), llmClientFactory As Func(Of LLMClient), logger As Logger) As Task(Of String)
            Dim llm = llmClientFactory()
            Dim sb As New StringBuilder()
            For Each f In refFiles
                Try
                    Dim content = File.ReadAllText(f)
                    If content.Length > 8000 Then content = content.Substring(0, 8000) & "...[truncated]"
                    sb.AppendLine($"=== Reference: {Path.GetFileName(f)} ===")
                    sb.AppendLine(content)
                    sb.AppendLine()
                Catch
                End Try
            Next

            Dim prompt = <string><![CDATA[
You are a biological knowledge extraction assistant. Below are reference literature texts related to the research topic.

Research topic: <%= topic %>

Your task:
1. Read all reference texts carefully.
2. Extract key biological knowledge including:
   - Disease / phenotype mechanisms
   - Key molecules (genes, proteins, metabolites) and their roles
   - Biological pathways involved
   - Known experimental designs and comparison groups
   - Key findings and conclusions
3. Output a JSON object with the following structure:
{
  "topic": "<research topic>",
  "disease": "<main disease or phenotype>",
  "species": "<species if mentioned>",
  "key_molecules": [{"name": "...", "type": "gene/protein/metabolite", "role": "...", "direction": "up/down"}],
  "pathways": [{"name": "...", "kegg_id": "...", "relevance": "..."}],
  "experimental_designs": [{"comparison": "control vs treatment", "rationale": "..."}],
  "key_findings": ["finding 1", "finding 2"],
  "summary": "<overall summary>"
}

Output ONLY the JSON object, no other text.

Reference texts:
<%= references %>
]]></string>.Value

            prompt = prompt.Replace("<%= topic %>", topic).Replace("<%= references %>", sb.ToString())
            Dim resp = Await llm.Chat(prompt)
            Dim json = resp.output.Trim()
            ' 简单清理 markdown 包裹
            If json.StartsWith("```") Then
                json = json.Substring(json.IndexOf(vbLf) + 1)
                If json.EndsWith("```") Then json = json.Substring(0, json.Length - 3)
                json = json.Trim()
            End If
            Try
                ' 验证 JSON
                Dim parsed = Newtonsoft.Json.Linq.JObject.Parse(json)
                Return parsed.ToString()
            Catch
                logger.Warn("LLM output is not valid JSON, wrapping as raw.")
                Return $"{{""topic"":""{topic.Replace("""", "\""")}"",""raw_extraction"":{Newtonsoft.Json.JsonConvert.ToString(json)},""entries"":[]}}"
            End Try
        End Function

    End Class

End Namespace

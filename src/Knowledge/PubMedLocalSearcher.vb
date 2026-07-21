' ============================================================================
' PubMed 本地 MySQL 镜像检索
' ============================================================================
Imports System.IO
Imports System.Text
Imports System.Threading
Imports OmicsAgent.Config
Imports OmicsAgent.Utils
Imports OmicsAgent.Tools

Namespace Knowledge

    ''' <summary>
    ''' 从本地 PubMed MySQL 镜像检索文献，保存为 txt 文件
    ''' </summary>
    Public Class PubMedLocalSearcher

        Private ReadOnly _connectionString As String
        Private ReadOnly _outputDir As String

        Public Sub New(connectionString As String, outputDir As String)
            _connectionString = connectionString
            _outputDir = outputDir
        End Sub

        Public Async Function SearchAndSaveAsync(topic As String, llmClientFactory As Func(Of LLMClient), logger As Logger) As Task(Of List(Of String))
            IO.WorkspaceManager.EnsureDir(_outputDir)
            Dim savedFiles As New List(Of String)()

            ' 1. 用 LLM 提取搜索关键词
            Dim keywords = Await ExtractSearchKeywordsAsync(topic, llmClientFactory, logger)
            logger.Info($"Extracted search keywords: {String.Join(", ", keywords)}")

            ' 2. 创建 PubMedQueryTool 实例并注册到 LLM
            Dim pubmedTool As New PubMedQueryTool(_connectionString)
            Dim llm = llmClientFactory()

            ' 注册 PubMed 工具
            llm.AddFunction(pubmedTool, "search_papers")
            llm.AddFunction(pubmedTool, "get_full_text")
            llm.AddFunction(pubmedTool, "get_database_stats")

            ' 3. 让 LLM 自主检索文献
            Dim prompt = <string><![CDATA[
You are a literature search agent. Your task is to search the local PubMed MySQL mirror database for papers relevant to the research topic, then save the most relevant papers.

Research topic: <%= topic %>

Suggested search keywords: <%= String.Join(", ", keywords) %>

Instructions:
1. Use the search_papers function to find relevant papers. Try multiple keyword combinations if needed.
2. For the top 5-10 most relevant papers, use get_full_text to retrieve their full text.
3. After collecting the papers, summarize what you found.

Please proceed with the search now.
]]></string>.Value.Replace("<%= topic %>", topic).Replace("<%= String.Join("", keywords) %>", String.Join(", ", keywords))

            Dim resp = Await llm.Chat(prompt)
            logger.Info("LLM literature search completed.")

            ' 4. 直接执行 SQL 检索（作为备份，确保有结果）
            Try
                Dim kwStr = String.Join(" ", keywords)
                Dim jsonResult = pubmedTool.search_papers(kwStr, max_results:=20)
                savedFiles = SaveSearchResultsAsTxt(jsonResult, "auto_search")
                logger.Info($"Saved {savedFiles.Count} papers from direct SQL search.")
            Catch ex As Exception
                logger.Warn($"Direct SQL search failed: {ex.Message}")
            End Try

            Return savedFiles
        End Function

        Private Async Function ExtractSearchKeywordsAsync(topic As String, llmClientFactory As Func(Of LLMClient), logger As Logger) As Task(Of List(Of String))
            Dim llm = llmClientFactory()
            Dim prompt = <string><![CDATA[
You are a literature search expert. Given the following research topic, extract 3-6 search keywords that would be most effective for finding relevant papers in PubMed.

Research topic:
<%= topic %>

Output format: a JSON array of strings, e.g. ["keyword1", "keyword2", "keyword3"]
Output ONLY the JSON array, no other text.
]]></string>.Value.Replace("<%= topic %>", topic)

            Dim resp = Await llm.Chat(prompt)
            Dim text = resp.output.Trim()
            If text.StartsWith("```") Then
                text = text.Substring(text.IndexOf(vbLf) + 1)
                If text.EndsWith("```") Then text = text.Substring(0, text.Length - 3)
                text = text.Trim()
            End If
            Try
                Dim arr = Newtonsoft.Json.Linq.JArray.Parse(text)
                Return arr.Select(Function(t) t.ToString()).ToList()
            Catch
                logger.Warn("Failed to parse keywords JSON, using simple split.")
                Return topic.Split({" "c, ","c, "."c}, StringSplitOptions.RemoveEmptyEntries).
                    Where(Function(w) w.Length > 3).
                    Take(5).ToList()
            End Try
        End Function

        Private Function SaveSearchResultsAsTxt(jsonResult As String, prefix As String) As List(Of String)
            Dim files As New List(Of String)()
            Try
                Dim obj = Newtonsoft.Json.Linq.JObject.Parse(jsonResult)
                Dim papers = obj("papers")
                If papers Is Nothing Then Return files
                Dim i = 1
                For Each p In papers
                    Try
                        Dim sb As New StringBuilder()
                        sb.AppendLine($"Title: {p("title")}")
                        sb.AppendLine($"PMID: {p("pmid")}")
                        sb.AppendLine($"Authors: {p("authors")}")
                        sb.AppendLine($"Journal: {p("journal")}")
                        sb.AppendLine($"Year: {p("year")}")
                        sb.AppendLine($"DOI: {p("doi")}")
                        sb.AppendLine($"MeSH Terms: {p("mesh_terms")}")
                        sb.AppendLine()
                        sb.AppendLine("Abstract:")
                        sb.AppendLine(p("abstract")?.ToString())
                        If p("full_text") IsNot Nothing AndAlso Not String.IsNullOrEmpty(p("full_text").ToString()) Then
                            sb.AppendLine()
                            sb.AppendLine("Full Text:")
                            sb.AppendLine(p("full_text").ToString())
                        End If
                        Dim path = Path.Combine(_outputDir, $"{prefix}_{i:00}_{p("pmid")}.txt")
                        File.WriteAllText(path, sb.ToString(), Encoding.UTF8)
                        files.Add(path)
                        i += 1
                    Catch
                    End Try
                Next
            Catch
            End Try
            Return files
        End Function

    End Class

End Namespace

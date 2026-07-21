' ============================================================================
' 知识库构建模块 - 文献检索与生物学知识提取
' ============================================================================
Imports System.ComponentModel
Imports System.IO
Imports System.Text
Imports System.Threading
Imports System.Threading.Tasks
Imports Microsoft.VisualBasic.CommandLine.Reflection
Imports MySql.Data.MySqlClient
Imports Newtonsoft.Json
Imports Newtonsoft.Json.Linq

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
        PathUtils.EnsureDirectory(_context.KnowledgeDir)

        ' 2. 处理参考文献
        Dim referenceFiles = CollectReferenceFiles()
        If referenceFiles.Count = 0 AndAlso _config.AutoSearchLiterature Then
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
        Select Case _config.LiteratureSearchStrategy.ToLower()
            Case "mysql"
                Return SearchFromMySql(researchTopic)
            Case "ncbi"
                Return Await SearchFromNcbiAsync(researchTopic, cancellationToken)
            Case Else
                LogInfo($"未知的文献检索策略：{_config.LiteratureSearchStrategy}，跳过自动检索")
                Return New List(Of String)()
        End Select
    End Function

    ''' <summary>从本地 MySQL PubMed 镜像检索文献</summary>
    Private Function SearchFromMySql(researchTopic As String) As List(Of String)
        Dim result As New List(Of String)()
        Try
            Dim pubmedTool As New PubMedQueryTool(_config.MySqlConnectionString)
            ' 调用 LLM 提取搜索关键词
            Dim keywords = ExtractSearchKeywords(researchTopic).Result
            LogInfo($"提取的搜索关键词：{String.Join(", ", keywords)}")

            For Each kw In keywords
                Dim json = pubmedTool.search_papers(kw, max_results:=_config.MaxLiteratureCount \ keywords.Count)
                Dim papers = ParseSearchResults(json)
                For Each paper In papers
                    Dim fileName = $"ref_{result.Count + 1}_{SafeFileName(paper("title"))}.txt"
                    Dim filePath = Path.Combine(_context.KnowledgeDir, fileName)
                    File.WriteAllText(filePath, FormatPaperText(paper), Encoding.UTF8)
                    result.Add(filePath)
                Next
                If result.Count >= _config.MaxLiteratureCount Then Exit For
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
            File.WriteAllText(pyScript, GenerateNcbiSearchScript(keywords, _config.MaxLiteratureCount, _context.KnowledgeDir), Encoding.UTF8)

            ' 执行 Python 脚本
            Dim shell As New ShellTool(_config, _context.WorkspaceDir, _logger)
            Dim runResult = shell.run_python("scripts/search_pubmed.py", timeout_seconds:=300)
            LogInfo($"Python 检索脚本执行结果：{runResult.Substring(0, Math.Min(200, runResult.Length))}...")

            ' 读取生成的 txt 文件
            For Each f In Directory.GetFiles(_context.KnowledgeDir, "ref_*.txt")
                result.Add(f)
            Next
        Catch ex As Exception
            LogInfo($"[警告] NCBI 在线文献检索失败：{ex.Message}")
        End Try
        Return result
    End Function

    ''' <summary>调用 LLM 提取搜索关键词</summary>
    Private Async Function ExtractSearchKeywords(researchTopic As String) As Task(Of List(Of String))
        Dim keywords As New List(Of String)()
        Try
            Using llm = _llmFactory()
                Dim prompt = $"You are a biomedical research assistant. Based on the following research topic description, extract 3-5 English search keywords that would be most effective for finding relevant scientific literature in PubMed. Return ONLY the keywords, one per line, without numbering or other text." & vbCrLf & vbCrLf & $"Research topic:{vbCrLf}{researchTopic}"
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

    ''' <summary>调用 LLM 从文献中提取生物学知识，生成 kb.json</summary>
    Private Async Function ExtractKnowledgeAsync(referenceFiles As List(Of String), cancellationToken As CancellationToken)
        LogInfo("正在从文献中提取生物学知识...")

        Dim knowledgeEntries As New List(Of JObject)()

        ' 合并所有文献内容（截断以避免超出 token 限制）
        Dim allContent As New StringBuilder()
        For Each f In referenceFiles
            Dim content = File.ReadAllText(f, Encoding.UTF8)
            allContent.AppendLine($"=== {Path.GetFileName(f)} ===")
            allContent.AppendLine(content)
            allContent.AppendLine()
        Next

        Dim combinedText = allContent.ToString()
        If combinedText.Length > 30000 Then
            combinedText = combinedText.Substring(0, 30000) & "...[truncated]"
        End If

        Try
            Using llm = _llmFactory()
                Dim prompt = BuildKnowledgeExtractionPrompt(_context.ResearchTopic, combinedText)
                Dim resp = Await llm.Chat(prompt, cancellationToken)
                Dim kbJson = ExtractJsonFromResponse(resp.output)
                If Not String.IsNullOrEmpty(kbJson) Then
                    File.WriteAllText(_context.KnowledgeBaseFile, kbJson, Encoding.UTF8)
                Else
                    ' 回退：直接保存 LLM 输出文本
                    Dim fallback = $"{{""research_topic"": ""{EscapeJson(_context.ResearchTopic)}"", ""summary"": ""{EscapeJson(resp.output)}"", ""references"": []}}"
                    File.WriteAllText(_context.KnowledgeBaseFile, fallback, Encoding.UTF8)
                End If
            End Using
        Catch ex As Exception
            LogInfo($"[警告] LLM 知识提取失败：{ex.Message}")
            Dim fallback = $"{{""research_topic"": ""{EscapeJson(_context.ResearchTopic)}"", ""error"": ""{EscapeJson(ex.Message)}"", ""references"": []}}"
            File.WriteAllText(_context.KnowledgeBaseFile, fallback, Encoding.UTF8)
        End Try
    End Function

    ''' <summary>无参考文献时，使用 LLM 自身训练知识生成 kb.json</summary>
    Private Async Function GenerateKnowledgeFromLLMAsync(cancellationToken As CancellationToken)
        LogInfo("使用 LLM 自身训练知识生成知识库...")
        Try
            Using llm = _llmFactory()
                Dim prompt = BuildKnowledgeFromLLMPrompt(_context.ResearchTopic)
                Dim resp = Await llm.Chat(prompt, cancellationToken)
                Dim kbJson = ExtractJsonFromResponse(resp.output)
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
    Private Function BuildKnowledgeExtractionPrompt(researchTopic As String, literatureContent As String) As String
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
    Private Function BuildKnowledgeFromLLMPrompt(researchTopic As String) As String
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

    ''' <summary>从 LLM 响应中提取 JSON 内容</summary>
    Private Function ExtractJsonFromResponse(text As String) As String
        If String.IsNullOrEmpty(text) Then Return ""

        ' 尝试提取 ```json ... ``` 代码块
        Dim codeBlockMatch = System.Text.RegularExpressions.Regex.Match(text, "```(?:json)?\s*([\s\S]*?)```")
        If codeBlockMatch.Success Then
            Return codeBlockMatch.Groups(1).Value.Trim()
        End If

        ' 尝试直接查找 { ... } 块
        Dim startIdx = text.IndexOf("{"c)
        Dim endIdx = text.LastIndexOf("}"c)
        If startIdx >= 0 AndAlso endIdx > startIdx Then
            Return text.Substring(startIdx, endIdx - startIdx + 1)
        End If

        Return ""
    End Function

    ''' <summary>解析 PubMed 搜索结果 JSON</summary>
    Private Function ParseSearchResults(json As String) As List(Of Dictionary(Of String, String))
        Dim result As New List(Of Dictionary(Of String, String))()
        Try
            Dim jobj = JObject.Parse(json)
            Dim papers = jobj("papers")
            If papers IsNot Nothing Then
                For Each p In papers
                    Dim dict As New Dictionary(Of String, String)()
                    For Each prop In p.Children(Of JProperty)()
                        dict(prop.Name) = prop.Value?.ToString()
                    Next
                    result.Add(dict)
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
        Return $@"
import os
import sys
import time
import urllib.request
import urllib.parse
import json
import xml.etree.ElementTree as ET

# NCBI PubMed search script
# Searches PubMed for the given keywords and saves results as txt files

KEYWORDS = [{kwList}]
MAX_RESULTS = {maxCount}
OUTPUT_DIR = r""{outputDir}""

def search_pubmed(keyword, max_results):
    base_url = ""https://eutils.ncbi.nlm.nih.gov/entrez/eutils""
    # Step 1: ESearch to get PMIDs
    search_params = urllib.parse.urlencode({{
        'db': 'pubmed',
        'term': keyword,
        'retmax': max_results,
        'retmode': 'json',
        'sort': 'date'
    }})
    search_url = f""{{base_url}}/esearch.fcgi?{{search_params}}""
    try:
        with urllib.request.urlopen(search_url, timeout=30) as resp:
            data = json.loads(resp.read().decode('utf-8'))
        pmids = data.get('esearchresult', {{}}).get('idlist', [])
    except Exception as e:
        print(f""ESearch failed for keyword '{{keyword}}': {{e}}"")
        return []
    
    # Step 2: EFetch to get full records
    if not pmids:
        return []
    
    fetch_params = urllib.parse.urlencode({{
        'db': 'pubmed',
        'id': ','.join(pmids),
        'retmode': 'xml'
    }})
    fetch_url = f""{{base_url}}/efetch.fcgi?{{fetch_params}}""
    try:
        with urllib.request.urlopen(fetch_url, timeout=60) as resp:
            xml_data = resp.read().decode('utf-8')
    except Exception as e:
        print(f""EFetch failed: {{e}}"")
        return []
    
    # Parse XML
    papers = []
    try:
        root = ET.fromstring(xml_data)
        for article in root.findall('.//PubmedArticle'):
            paper = {{}}
            pmid_elem = article.find('.//PMID')
            paper['pmid'] = pmid_elem.text if pmid_elem is not None else ''
            title_elem = article.find('.//ArticleTitle')
            paper['title'] = title_elem.text if title_elem is not None else ''
            journal_elem = article.find('.//Journal/Title')
            paper['journal'] = journal_elem.text if journal_elem is not None else ''
            year_elem = article.find('.//PubDate/Year')
            paper['year'] = year_elem.text if year_elem is not None else ''
            doi_elem = article.find('.//ArticleId[@IdType=""doi""]')
            paper['doi'] = doi_elem.text if doi_elem is not None else ''
            
            # Authors
            authors = []
            for author in article.findall('.//Author'):
                last = author.find('LastName')
                init = author.find('Initials')
                if last is not None:
                    name = last.text
                    if init is not None:
                        name += ' ' + init.text
                    authors.append(name)
            paper['authors'] = '; '.join(authors)
            
            # Abstract
            abstract_parts = []
            for abs in article.findall('.//Abstract/AbstractText'):
                if abs.text:
                    abstract_parts.append(abs.text)
            paper['abstract'] = ' '.join(abstract_parts)
            
            # MeSH terms
            mesh_terms = []
            for mesh in article.findall('.//MeshHeading/DescriptorName'):
                if mesh.text:
                    mesh_terms.append(mesh.text)
            paper['mesh_terms'] = '; '.join(mesh_terms)
            
            papers.append(paper)
    except Exception as e:
        print(f""XML parse failed: {{e}}"")
    
    return papers

def save_paper(paper, idx, output_dir):
    safe_title = ''.join(c if c.isalnum() or c in ' -_' else '_' for c in paper.get('title', '')[:50])
    filename = f""ref_{{idx}}_{{safe_title}}.txt""
    filepath = os.path.join(output_dir, filename)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(f""PMID: {{paper.get('pmid', '')}}\n"")
        f.write(f""Title: {{paper.get('title', '')}}\n"")
        f.write(f""Authors: {{paper.get('authors', '')}}\n"")
        f.write(f""Journal: {{paper.get('journal', '')}}\n"")
        f.write(f""Year: {{paper.get('year', '')}}\n"")
        f.write(f""DOI: {{paper.get('doi', '')}}\n"")
        f.write(f""MeSH Terms: {{paper.get('mesh_terms', '')}}\n"")
        f.write('\nAbstract:\n')
        f.write(paper.get('abstract', ''))
    return filepath

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    all_papers = []
    per_keyword = max(1, MAX_RESULTS // len(KEYWORDS)) if KEYWORDS else 0
    for kw in KEYWORDS:
        print(f""Searching PubMed for: {{kw}}"")
        papers = search_pubmed(kw, per_keyword)
        all_papers.extend(papers)
        time.sleep(1)  # respect NCBI rate limit
    
    print(f""Total papers found: {{len(all_papers)}}"")
    for i, paper in enumerate(all_papers, 1):
        try:
            save_paper(paper, i, OUTPUT_DIR)
        except Exception as e:
            print(f""Failed to save paper {{i}}: {{e}}"")
    
    print(""Done"")

if __name__ == '__main__':
    main()
"
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

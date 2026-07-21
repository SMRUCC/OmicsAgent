' ============================================================================
' NCBI PubMed 在线检索（通过 Python 脚本）
' ============================================================================
Imports System.Diagnostics
Imports System.IO
Imports System.Text
Imports OmicsAgent.Config
Imports OmicsAgent.Utils

Namespace Knowledge

    ''' <summary>
    ''' 通过 Python 脚本调用 NCBI E-utilities 在线检索 PubMed 文献
    ''' </summary>
    Public Class NcbiOnlineSearcher

        Private ReadOnly _pythonPath As String
        Private ReadOnly _outputDir As String

        Public Sub New(pythonPath As String, outputDir As String)
            _pythonPath = pythonPath
            _outputDir = outputDir
        End Sub

        Public Async Function SearchAndSaveAsync(topic As String, llmClientFactory As Func(Of LLMClient), logger As Logger) As Task(Of List(Of String))
            IO.WorkspaceManager.EnsureDir(_outputDir)

            ' 1. 用 LLM 提取搜索关键词
            Dim keywords = Await ExtractSearchKeywordsAsync(topic, llmClientFactory, logger)
            logger.Info($"Extracted search keywords: {String.Join(", ", keywords)}")

            ' 2. 生成 Python 检索脚本
            Dim pyScript = Path.Combine(_outputDir, "ncbi_search.py")
            File.WriteAllText(pyScript, BuildPythonScript(keywords, _outputDir), Encoding.UTF8)

            ' 3. 执行 Python 脚本
            Dim files As New List(Of String)()
            Try
                Dim psi As New ProcessStartInfo With {
                    .FileName = _pythonPath,
                    .Arguments = $"""{pyScript}""",
                    .UseShellExecute = False,
                    .RedirectStandardOutput = True,
                    .RedirectStandardError = True,
                    .CreateNoWindow = True,
                    .WorkingDirectory = _outputDir
                }
                Using p As New Process()
                    p.StartInfo = psi
                    p.Start()
                    Dim stdout = Await p.StandardOutput.ReadToEndAsync()
                    Dim stderr = Await p.StandardError.ReadToEndAsync()
                    p.WaitForExit(120000)
                    logger.Info($"Python NCBI search stdout: {stdout}")
                    If Not String.IsNullOrEmpty(stderr) Then logger.Warn($"Python NCBI search stderr: {stderr}")
                End Using

                ' 收集生成的 txt 文件
                files = Directory.GetFiles(_outputDir, "ncbi_paper_*.txt").ToList()
                logger.Info($"NCBI online search saved {files.Count} papers.")
            Catch ex As Exception
                logger.Error($"NCBI online search failed: {ex.Message}")
            End Try

            Return files
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
                Return topic.Split({" "c, ","c, "."c}, StringSplitOptions.RemoveEmptyEntries).
                    Where(Function(w) w.Length > 3).
                    Take(5).ToList()
            End Try
        End Function

        Private Function BuildPythonScript(keywords As List(Of String), outputDir As String) As String
            Dim kwJson = Newtonsoft.Json.JsonConvert.SerializeObject(keywords)
            Return $@"#!/usr/bin/env python3
# Auto-generated NCBI PubMed search script
import sys
import os
import json
import time
import urllib.request
import urllib.parse

KEYWORDS = {kwJson}
OUTPUT_DIR = r'{outputDir}'
MAX_RESULTS = 20

def esearch(keywords, retmax=20):
    base = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi'
    query = ' AND '.join(keywords)
    params = urllib.parse.urlencode({{
        'db': 'pubmed',
        'term': query,
        'retmax': retmax,
        'retmode': 'json',
        'sort': 'relevance'
    }})
    url = base + '?' + params
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            return data.get('esearchresult', {{}}).get('idlist', [])
    except Exception as e:
        print(f'esearch error: {{e}}', file=sys.stderr)
        return []

def efetch(pmids):
    if not pmids:
        return []
    base = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi'
    params = urllib.parse.urlencode({{
        'db': 'pubmed',
        'id': ','.join(pmids),
        'retmode': 'xml',
        'rettype': 'abstract'
    }})
    url = base + '?' + params
    try:
        with urllib.request.urlopen(url, timeout=60) as resp:
            return resp.read().decode('utf-8')
    except Exception as e:
        print(f'efetch error: {{e}}', file=sys.stderr)
        return ''

def parse_papers(xml_text):
    import re
    papers = []
    # Simple regex-based parsing (avoid xml dependency)
    articles = re.split(r'<PubmedArticle>', xml_text)[1:]
    for art in articles:
        def find_first(pattern):
            m = re.search(pattern, art, re.DOTALL)
            return m.group(1).strip() if m else ''
        pmid = find_first(r'<PMID[^>]*>(\d+)</PMID>')
        title = find_first(r'<ArticleTitle>(.*?)</ArticleTitle>')
        abstract_parts = re.findall(r'<AbstractText[^>]*>(.*?)</AbstractText>', art, re.DOTALL)
        abstract = ' '.join(abstract_parts)
        journal = find_first(r'<Title>(.*?)</Title>')
        year = find_first(r'<PubDate>.*?<Year>(\d+)</PubDate>.*?</PubDate>', ) or find_first(r'<Year>(\d+)</Year>')
        doi = find_first(r'<ArticleId IdType=""doi"">(.*?)</ArticleId>')
        authors = []
        for au in re.findall(r'<Author.*?>(.*?)</Author>', art, re.DOTALL):
            last = find_first_in(r'<LastName>(.*?)</LastName>', au)
            init = find_first_in(r'<Initials>(.*?)</Initials>', au)
            if last:
                authors.append(f'{{last}} {{init}}'.strip())
        papers.append({{
            'pmid': pmid,
            'title': re.sub(r'<[^>]+>', '', title),
            'abstract': re.sub(r'<[^>]+>', '', abstract),
            'journal': re.sub(r'<[^>]+>', '', journal),
            'year': year,
            'doi': doi,
            'authors': '; '.join(authors)
        }})
    return papers

def find_first_in(pattern, text):
    import re
    m = re.search(pattern, text, re.DOTALL)
    return m.group(1).strip() if m else ''

def main():
    print(f'Searching PubMed for: {{KEYWORDS}}')
    pmids = esearch(KEYWORDS, MAX_RESULTS)
    print(f'Found {{len(pmids)}} PMIDs')
    if not pmids:
        return
    time.sleep(0.5)
    xml_text = efetch(pmids)
    if not xml_text:
        return
    papers = parse_papers(xml_text)
    print(f'Parsed {{len(papers)}} papers')
    for i, p in enumerate(papers, 1):
        fname = os.path.join(OUTPUT_DIR, f'ncbi_paper_{{i:02d}}_{{p[""pmid""]}}.txt')
        with open(fname, 'w', encoding='utf-8') as f:
            f.write(f'Title: {{p[""title""]}}\n')
            f.write(f'PMID: {{p[""pmid""]}}\n')
            f.write(f'Authors: {{p[""authors""]}}\n')
            f.write(f'Journal: {{p[""journal""]}}\n')
            f.write(f'Year: {{p[""year""]}}\n')
            f.write(f'DOI: {{p[""doi""]}}\n\n')
            f.write('Abstract:\n')
            f.write(p['abstract'])
            f.write('\n')
        print(f'Saved: {{fname}}')

if __name__ == '__main__':
    main()
"
        End Function

    End Class

End Namespace

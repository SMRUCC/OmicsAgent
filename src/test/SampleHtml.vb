Imports System.IO
Imports System.Reflection
Imports Microsoft.VisualBasic.MIME.application.json
Imports Microsoft.VisualBasic.MIME.application.json.LenientJson
Imports Ollama
Imports OmicsAgent
Imports OmicsAgent.ReportData

Module SampleHtml
    Sub Generate()
        Dim txtPath = "G:\OmicsWorks\test\metabolism\demo\tmp\11_paper_draft_report\report.txt"
        If Not File.Exists(txtPath) Then
            Console.WriteLine("demo report.txt not found")
            Return
        End If

        Dim respo As New LLMsResponse With {.output = txtPath.ReadAllText}
        Dim json As String = respo.ExtractJsonFromResponse
        Dim content As ReportContent = LenientJsonParser.ParseJSON(json).CreateObject(Of ReportContent)

        If content Is Nothing Then
            Console.WriteLine("failed to parse ReportContent")
            Return
        End If

        ' 通过反射构造 Friend 的 ReportResource / ResourceFile（用于验证 HTML 结构）
        Dim asm = GetType(ReportContent).Assembly
        Dim resType = asm.GetType("OmicsAgent.HtmlReport+ReportResource")
        Dim rfType = asm.GetType("OmicsAgent.HtmlReport+ResourceFile")
        Dim res = Activator.CreateInstance(resType)
        Dim emptyFig = Array.CreateInstance(rfType, 0)
        Dim emptyTbl = Array.CreateInstance(rfType, 0)
        resType.GetField("figures").SetValue(res, emptyFig)
        resType.GetField("tables").SetValue(res, emptyTbl)

        ' 通过反射调用 Friend 扩展方法 BuildHtmlReport
        Dim htmlType = asm.GetType("OmicsAgent.HtmlReport")
        Dim method = htmlType.GetMethod("BuildHtmlReport", BindingFlags.NonPublic Or BindingFlags.Static)
        Dim log As Action(Of String) = Sub(s) Console.WriteLine("[log] " & s)
        Dim html As String = CStr(method.Invoke(Nothing, New Object() {content, res, log}))

        Dim outPath = "G:\OmicsWorks\test\metabolism\demo\tmp\11_paper_draft_report\report_sample.html"
        File.WriteAllText(outPath, html)
        Console.WriteLine("Saved sample HTML to: " & outPath)
        Console.WriteLine("HTML length: " & html.Length)
        Console.WriteLine("Has cover: " & html.Contains("<div class='cover'>"))
        Console.WriteLine("Has toc: " & html.Contains("<div class='toc'>"))
        Console.WriteLine("Has results: " & html.Contains("id='sec-results'"))
        Console.WriteLine("Has abstract: " & html.Contains("<div class='abstract'>"))
        Console.WriteLine("Double <br><br>: " & html.Contains("<br><br>"))
    End Sub
End Module

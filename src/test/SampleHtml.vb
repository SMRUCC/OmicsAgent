Imports System.IO
Imports System.Reflection
Imports Microsoft.VisualBasic.MIME.application.json
Imports Microsoft.VisualBasic.MIME.application.json.LenientJson
Imports Ollama
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

        ' 通过反射构造 Friend 的 ReportResource / ResourceFile / ReportCounters
        Dim asm = GetType(ReportContent).Assembly
        Dim resType = asm.GetType("OmicsAgent.HtmlReport+ReportResource")
        Dim rfType = asm.GetType("OmicsAgent.HtmlReport+ResourceFile")
        Dim countersType = asm.GetType("OmicsAgent.HtmlReport+ReportCounters")
        Dim res = Activator.CreateInstance(resType)
        Dim emptyFig = Array.CreateInstance(rfType, 0)
        Dim emptyTbl = Array.CreateInstance(rfType, 0)
        resType.GetField("figures").SetValue(res, emptyFig)
        resType.GetField("tables").SetValue(res, emptyTbl)
        Dim counters = Activator.CreateInstance(countersType)

        ' 通过反射调用 Friend 扩展方法 BuildHtmlReport
        Dim htmlType = asm.GetType("OmicsAgent.HtmlReport")
        Dim method = htmlType.GetMethod("BuildHtmlReport", BindingFlags.NonPublic Or BindingFlags.Static)
        Dim log As Action(Of String) = Sub(s) Console.WriteLine("[log] " & s)
        Dim html As String = CStr(method.Invoke(Nothing, New Object() {content, res, log}))

        Dim outDir = "G:\OmicsWorks\test\metabolism\demo\tmp\11_paper_draft_report"
        Dim outPath = outDir & "\report_sample.html"
        File.WriteAllText(outPath, html)
        Console.WriteLine("Saved sample HTML to: " & outPath)
        Console.WriteLine("HTML length: " & html.Length)
        Console.WriteLine("Has cover: " & html.Contains("<div class='cover'>"))
        Console.WriteLine("Has toc: " & html.Contains("<div class='toc'>"))
        Console.WriteLine("Has results: " & html.Contains("id='sec-results'"))
        Console.WriteLine("Has abstract: " & html.Contains("<div class='abstract'>"))
        Console.WriteLine("Double <br><br>: " & html.Contains("<br><br>"))

        ' ---- 直接验证 BuildFigure / BuildTable 渲染 ----
        Dim pngBytes = Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
        Dim pngPath = outDir & "\test_fig.png"
        File.WriteAllBytes(pngPath, pngBytes)
        Dim csvPath = outDir & "\test_table.csv"
        File.WriteAllText(csvPath, "metabolite,group,value" & vbCrLf & "A,NC,1.2" & vbCrLf & "B,CD,3.4" & vbCrLf & "C,FE,5.6" & vbCrLf & "D,NC,0.9")

        Dim tfcType = asm.GetType("OmicsAgent.ReportData.TableFigureCaption")
        Dim figCap = Activator.CreateInstance(tfcType)
        tfcType.GetProperty("file").SetValue(figCap, "test_fig.png")
        tfcType.GetProperty("caption_cn").SetValue(figCap, "测试图中文说明")
        tfcType.GetProperty("caption_en").SetValue(figCap, "Test figure caption")
        Dim figRes = Activator.CreateInstance(rfType, 0, pngPath)

        Dim tblCap = Activator.CreateInstance(tfcType)
        tblCap.GetType().GetProperty("file").SetValue(tblCap, "test_table.csv")
        tblCap.GetType().GetProperty("caption_cn").SetValue(tblCap, "测试表中文说明")
        tblCap.GetType().GetProperty("caption_en").SetValue(tblCap, "Test table caption")
        Dim tblRes = Activator.CreateInstance(rfType, 0, csvPath)

        Dim buildFigure = htmlType.GetMethod("BuildFigure", BindingFlags.NonPublic Or BindingFlags.Static)
        Dim buildTable = htmlType.GetMethod("BuildTable", BindingFlags.NonPublic Or BindingFlags.Static)

        Dim figHtml = CStr(buildFigure.Invoke(Nothing, New Object() {figCap, figRes, counters}))
        Dim tblHtml = CStr(buildTable.Invoke(Nothing, New Object() {tblCap, tblRes, counters, log}))

        Dim snippet = "<!DOCTYPE html><html><head><meta charset='UTF-8'><style>" &
            File.ReadAllText("G:\OmicsWorks\src\test\bin\Debug\docs\report.css") &
            "</style></head><body>" & figHtml & tblHtml & "</body></html>"
        Dim snippetPath = outDir & "\report_figtable.html"
        File.WriteAllText(snippetPath, snippet)
        Console.WriteLine("Saved fig/table snippet to: " & snippetPath)
        Console.WriteLine("Figure has <figure>: " & figHtml.Contains("<figure>"))
        Console.WriteLine("Figure has 图 1： " & figHtml.Contains("图 1："))
        Console.WriteLine("Figure has data uri: " & figHtml.Contains("data:image/png;base64,"))
        Console.WriteLine("Table has <table>: " & tblHtml.Contains("<table>"))
        Console.WriteLine("Table has 表 1： " & tblHtml.Contains("表 1："))
        Console.WriteLine("Table rows: " & (tblHtml.Split(New String() {"<tr>"}, StringSplitOptions.None).Length - 1))
    End Sub
End Module

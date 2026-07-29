Imports Microsoft.VisualBasic.MIME.application.json
Imports Ollama
Imports OmicsAgent.ReportData

Module Program

    Sub Main(args As String())
        Call test_reportjson()
        Pause()
    End Sub

    ''' <summary>
    ''' 测试从大语言模型返回结果之中解析出报告 json 对象
    ''' </summary>
    Private Sub test_reportjson()
        Dim respo As New LLMsResponse With {.output = "G:\OmicsWorks\test\metabolism\demo\tmp\11_paper_draft_report\report.txt".ReadAllText}
        Dim json As String = respo.ExtractJsonFromResponse()
        Dim plan As ReportData.ReportContent = LenientJsonParser.ParseJSON(json).CreateObject(Of ReportData.ReportContent)

        Call plan.GetJson.JsonFragment(indent:=True).SaveTo("G:\OmicsWorks\test\metabolism\demo\tmp\11_paper_draft_report\result.json")
    End Sub

End Module

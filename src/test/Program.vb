Imports System
Imports Microsoft.VisualBasic.MIME.application.json
Imports Microsoft.VisualBasic.MIME.application.json.LenientJson
Imports Ollama
Imports OmicsAgent

Module Program
    Sub Main(args As String())
        test_rscriptSyntaxError()
        Pause()
    End Sub

    Sub test_rscriptSyntaxError()
        ' 模拟 LLM 生成的包含错误的 R 脚本
        Dim rScript As String = "for (i in1:min(length(match_idx),3)) {" & Environment.NewLine &
                                "  print(i)" & Environment.NewLine &
                                "}" & Environment.NewLine &
                                "# 正常的循环不应被影响" & Environment.NewLine &
                                "for (j in 1:10) { print(j) }" & vbCrLf & vbCrLf & vbCrLf & "for(i in1   :   2) {" & Environment.NewLine &
                                "  print(i)" & Environment.NewLine &
                                "}" & Environment.NewLine

        Console.WriteLine("--- 原始的错误脚本 ---")
        Console.WriteLine(rScript)
        Console.WriteLine()
        Console.WriteLine()
        Console.WriteLine()
        Console.WriteLine("--- 直接修正整个脚本的结果 ---")
        Console.WriteLine(RScriptFixer.FixEntireRScript(rScript))
    End Sub

    Sub test_planjson()
        Dim respo As New LLMsResponse With {.output = "G:\OmicsWorks\test\plan_response.txt".ReadAllText}
        Dim json As String = respo.ExtractJsonFromResponse
        Dim plan As ModulePlan = LenientJsonParser.ParseJSON(json).CreateObject(Of ModulePlan)

        Pause()
    End Sub
End Module

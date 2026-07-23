Imports System
Imports Microsoft.VisualBasic.MIME.application.json
Imports Microsoft.VisualBasic.MIME.application.json.LenientJson
Imports Ollama
Imports OmicsAgent

Module Program
    Sub Main(args As String())
        Dim respo As New LLMsResponse With {.output = "G:\OmicsWorks\test\plan_response.txt".ReadAllText}
        Dim json As String = respo.ExtractJsonFromResponse
        Dim plan As ModulePlan = LenientJsonParser.ParseJSON(json).CreateObject(Of ModulePlan)
        Pause()
    End Sub
End Module

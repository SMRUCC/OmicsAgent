Imports System
Imports Ollama

Module Program
    Sub Main(args As String())
        Dim respo As New LLMsResponse With {.output = "G:\OmicsWorks\test\plan_response.txt".ReadAllText}
        Dim json As String = respo.ExtractJsonFromResponse

        Pause()
    End Sub
End Module

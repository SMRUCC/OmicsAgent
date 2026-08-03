Imports Microsoft.VisualBasic.ComponentModel.Ranges.Unit
Imports Microsoft.VisualBasic.ComponentModel.Settings.Inf

Namespace Settings

    <ClassName("LLMs")>
    Public Class llm

        Public Property endpoint As String = "openai://api.deepseek.com"
        Public Property apiKey As String
        Public Property model As String = "deepseek-v4-flash"
        Public Property temperature As Double = 0.1
        Public Property maxTokens As Long = 1 * ByteSize.MB

    End Class
End Namespace
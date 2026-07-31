Imports Microsoft.VisualBasic.ComponentModel.DataSourceModel.SchemaMaps
Imports Microsoft.VisualBasic.ComponentModel.Settings.Inf

Namespace Settings

    Public Class AppConfig

        <Field("LLMs")> Public Property llm As llm

        Shared ReadOnly Property defaultFile As String = App.ProductProgramData & "/omics-works-config.ini"

        Public Shared Function Load() As AppConfig
            Dim config As AppConfig = IOProvider.LoadProfile(Of AppConfig)(defaultFile)

            If config Is Nothing Then
                config = New AppConfig With {.llm = New llm}
                config.WriteProfile(defaultFile)
            End If

            If config.llm Is Nothing Then config.llm = New llm

            Return config
        End Function

        Public Function Save() As Boolean
            Return Me.WriteProfile(defaultFile)
        End Function
    End Class
End Namespace
Imports Microsoft.VisualBasic.ApplicationServices
Imports Microsoft.VisualBasic.ComponentModel.Settings.Inf
Imports OmicsWorks.Settings

Public Class FormOmicsAgent

    Public Property workspace As String

    Private Sub FormOmicsAgent_Load(sender As Object, e As EventArgs) Handles Me.Load
        Dim config As AppConfig = Workbench.config
        Dim temp As String = TempFileSystem.GetAppSysTempFile(".ini", sessionID:=App.NextTempName, prefix:="omics-agent-runtime_")

        Call config.WriteProfile(temp)

        TabText = $"Agent [{workspace.BaseName} - {workspace.ParentPath}]"
        WebViewConsole1.StartProcess(App.HOME & "/research.exe", $"--config {temp.CLIPath}")
    End Sub
End Class
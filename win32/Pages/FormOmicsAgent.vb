Imports Microsoft.VisualBasic.ApplicationServices
Imports Microsoft.VisualBasic.ComponentModel.Ranges.Unit
Imports Microsoft.VisualBasic.ComponentModel.Settings.Inf
Imports OmicsWorks.Settings

Public Class FormOmicsAgent

    Public Property workspace As String

    Private Sub FormOmicsAgent_Load(sender As Object, e As EventArgs) Handles Me.Load
        Dim config As AppConfig = Workbench.config
        Dim temp As String = TempFileSystem.GetAppSysTempFile(".ini", sessionID:=App.NextTempName, prefix:="omics-agent-runtime_")
        Dim kbfile As String = $"{workspace}/research_kb/kb.json"
        Dim datafile As String = $"{workspace}/tmp/dataset.json"
        Dim backgroundfile As String = $"{workspace}/research.txt"
        Dim args As New List(Of String)

        Call args.Add("/agent")
        Call args.Add($"--research={backgroundfile.CLIPath}")
        Call args.Add($"--dataset={datafile.CLIPath}")
        Call args.Add($"--reference={kbfile.ParentPath.CLIPath}")
        Call args.Add($"--config {temp.CLIPath}")
        Call args.Add($"--workspace {workspace.CLIPath}")

        If kbfile.FileLength > 1 * ByteSize.KB Then
            Call args.Add("--skip-literature")
            Call args.Add("--skip-kb")
        End If

        Call config.WriteProfile(temp)

        TabText = $"Agent [{workspace.BaseName} - {workspace.ParentPath}]"
        WebViewConsole1.StartProcess(App.HOME & "/research.exe", args.JoinBy(" "))
    End Sub
End Class
Imports Galaxy.Workbench
Imports Galaxy.Workbench.CommonDialogs
Imports Microsoft.VisualStudio.WinForms.Docking
Imports Ollama
Imports OmicsAgent.AppRuntime.Ini
Imports OmicsWorks.RibbonLib.Controls
Imports WebView2UI

Module RibbonMenu

    Public ReadOnly Property Ribbon As RibbonItems

    Public Sub Hook(ribbon As RibbonItems)
        RibbonMenu._Ribbon = ribbon

        AddHandler ribbon.ButtonOpenResearch.ExecuteEvent, Sub() Call OpenResearch()
        AddHandler ribbon.ButtonOpenFolder.ExecuteEvent, Sub() Call OpenFolder()
        AddHandler ribbon.ButtonExit.ExecuteEvent, Sub() Call DirectCast(CommonRuntime.AppHost, Form).Close()
        AddHandler ribbon.ButtonOpenConsole.ExecuteEvent, Sub() Call OpenConsole()
        AddHandler ribbon.ButtonLicense.ExecuteEvent, Sub() Call OpenLicenseDialog()
        AddHandler ribbon.ButtonVennTool.ExecuteEvent, Sub() Call OpenJVennTool()
        AddHandler ribbon.ButtonLLMTool.ExecuteEvent, Sub() Call OpenLLmTool()
    End Sub

    Public Function OpenLLmTool() As FormLLMWindow
        Dim llm As FormLLMWindow = CommonRuntime.TryGetToolWindow("llm_window")

        If llm Is Nothing Then
            Dim config As LLMConfig = Workbench.config.LLM
            Dim agent As New LLMClient(LLMUrl.Create(config.LLMServiceUrl, config.LLMApiKey), config.LLMModelName)

            llm = New FormLLMWindow With {
                .Name = "llm_window"
            }

            Call agent.AddFunction(New FileTool(), "read_file")
            Call llm.WebView2llmui1.SetHost(agent)

            CommonRuntime.RegisterToolWindow(llm, DockState.DockRight)
        End If

        Return llm
    End Function

    Public Sub OpenJVennTool()
        Call CommonRuntime.ShowDocument(New FormHtmlViewer With {.URL = $"http://127.0.0.1:{Workbench.port}/jvenn.html", .TabText = "jVenn"})
    End Sub

    Public Sub OpenLicenseDialog()
        Call InputDialog.ShowDialog(Of FormLicenseDialog)()
    End Sub

    Public Sub OpenConsole()
        Call CommonRuntime.RegisterToolWindow(New FormConsole, DockState.DockBottom)
    End Sub

    Public Sub OpenFolder()
        Using dir As New FolderBrowserDialog
            If dir.ShowDialog = DialogResult.OK Then
                Call OpenFolder(dir.SelectedPath)
            End If
        End Using
    End Sub

    Public Sub OpenFolder(folder As String)
        Dim ws As FormFolderWorkspace = CommonRuntime.TryGetToolWindow("agent_folder")

        If ws Is Nothing Then
            ws = New FormFolderWorkspace With {.Folder = folder, .Name = "agent_folder"}
        End If

        Call CommonRuntime.RegisterToolWindow(ws, DockState.DockRight)
        Call ws.LoadFolder(folder)
    End Sub

    Public Sub OpenResearch()
        Using dir As New FolderBrowserDialog With {.ShowNewFolderButton = True}
            If dir.ShowDialog = DialogResult.OK Then
                If License.CheckLicense Then
                    Call CommonRuntime.ShowDocument(New FormResearchWork With {.Workspace = dir.SelectedPath})
                Else
                    Call CommonRuntime.Warning("Unlicensed software, please apply a valid license file and then start your research work.")
                End If
            End If
        End Using
    End Sub

    Public Sub OpenStartupPage()
        Call CommonRuntime.ShowSingleDocument(Of FormStartupPage)()
    End Sub

    Public Sub OpenKbPage(dir As String, base As FormResearchWork)
        Call CommonRuntime.ShowDocument(New FormKnowledgeBase With {
            .kb_dir = dir,
            .base = base
        })
    End Sub
End Module

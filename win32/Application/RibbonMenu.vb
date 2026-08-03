Imports Galaxy.Workbench
Imports Galaxy.Workbench.CommonDialogs
Imports Microsoft.VisualStudio.WinForms.Docking
Imports OmicsWorks.RibbonLib.Controls

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
    End Sub

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
                Call CommonRuntime.RegisterToolWindow(New FormFolderWorkspace With {.Folder = dir.SelectedPath}, DockState.DockRight)
            End If
        End Using
    End Sub

    Public Sub OpenResearch()
        Using dir As New FolderBrowserDialog With {.ShowNewFolderButton = True}
            If dir.ShowDialog = DialogResult.OK Then
                Dim page As New FormResearchWork With {.Workspace = dir.SelectedPath}

                Call CommonRuntime.ShowDocument(page)
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

Imports Galaxy.Workbench
Imports OmicsWorks.RibbonLib.Controls

Module RibbonMenu

    Public ReadOnly Property Ribbon As RibbonItems

    Public Sub Hook(ribbon As RibbonItems)
        RibbonMenu._Ribbon = ribbon

        AddHandler ribbon.ButtonOpenResearch.ExecuteEvent, Sub() Call OpenResearch()
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

    Public Sub OpenKbPage(dir As String)
        Dim page As New FormKnowledgeBase With {.kb_dir = dir}
        Call CommonRuntime.ShowDocument(page)
    End Sub
End Module

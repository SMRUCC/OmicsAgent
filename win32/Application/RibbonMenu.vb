Imports Galaxy.Workbench

Module RibbonMenu

    Public Sub OpenStartupPage()
        Call CommonRuntime.ShowSingleDocument(Of FormStartupPage)()
    End Sub
End Module

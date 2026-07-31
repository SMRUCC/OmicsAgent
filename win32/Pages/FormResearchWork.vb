Imports RibbonLib.Interop

Public Class FormResearchWork

    Shared ReadOnly btnOpenKb As RibbonEventBinding

    Shared Sub New()
        btnOpenKb = New RibbonEventBinding(Ribbon.ButtonOpenKb)
    End Sub

    Public Property Workspace As String

    Private Sub OpenKBPage()
        Call RibbonMenu.OpenKbPage(dir:=$"{Workspace}/research_kb/")
    End Sub

    Private Sub ActiveRibbonMenu()
        Ribbon.MenuResearchWork.ContextAvailable = ContextAvailability.Available

        Call btnOpenKb.Addhandler(AddressOf OpenKBPage)
    End Sub

    Private Sub FormResearchWork_Load(sender As Object, e As EventArgs) Handles Me.Load
        Call ActiveRibbonMenu()
    End Sub
End Class
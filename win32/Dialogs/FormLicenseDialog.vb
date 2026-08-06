Public Class FormLicenseDialog

    Private Sub LinkLabel1_LinkClicked(sender As Object, e As LinkLabelLinkClickedEventArgs) Handles LinkLabel1.LinkClicked
        Call License.CheckLicense()
    End Sub
End Class
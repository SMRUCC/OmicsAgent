Public Class FormTextEdit

    Public Property TextFile As String

    Private Sub FormTextEdit_Load(sender As Object, e As EventArgs) Handles Me.Load
        TextBox1.Text = TextFile.ReadAllText(throwEx:=False)
    End Sub

    Protected Overrides Sub SaveDocument()
        Call TextBox1.Text.SaveTo(TextFile)
    End Sub

    Private Sub FormTextEdit_FormClosing(sender As Object, e As FormClosingEventArgs) Handles Me.FormClosing
        Call TextBox1.Text.SaveTo(TextFile)
    End Sub
End Class
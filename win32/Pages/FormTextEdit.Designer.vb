Imports Galaxy.Workbench.DockDocument

<Global.Microsoft.VisualBasic.CompilerServices.DesignerGenerated()>
Partial Class FormTextEdit
    Inherits DocumentWindow

    'Form overrides dispose to clean up the component list.
    <System.Diagnostics.DebuggerNonUserCode()> _
    Protected Overrides Sub Dispose(ByVal disposing As Boolean)
        Try
            If disposing AndAlso components IsNot Nothing Then
                components.Dispose()
            End If
        Finally
            MyBase.Dispose(disposing)
        End Try
    End Sub

    'Required by the Windows Form Designer
    Private components As System.ComponentModel.IContainer

    'NOTE: The following procedure is required by the Windows Form Designer
    'It can be modified using the Windows Form Designer.  
    'Do not modify it using the code editor.
    <System.Diagnostics.DebuggerStepThrough()> _
    Private Sub InitializeComponent()
        TextBox1 = New TextBox()
        SuspendLayout()
        ' 
        ' TextBox1
        ' 
        TextBox1.Dock = DockStyle.Fill
        TextBox1.Location = New Point(0, 0)
        TextBox1.Multiline = True
        TextBox1.Name = "TextBox1"
        TextBox1.ScrollBars = ScrollBars.Both
        TextBox1.Size = New Size(800, 450)
        TextBox1.TabIndex = 0
        ' 
        ' FormTextEdit
        ' 
        AutoScaleDimensions = New SizeF(7F, 15F)
        AutoScaleMode = AutoScaleMode.Font
        ClientSize = New Size(800, 450)
        Controls.Add(TextBox1)
        Name = "FormTextEdit"
        Text = "Text Edit"
        ResumeLayout(False)
        PerformLayout()
    End Sub

    Friend WithEvents TextBox1 As TextBox
End Class

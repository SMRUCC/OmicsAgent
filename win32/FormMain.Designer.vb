Imports RibbonLib

<Global.Microsoft.VisualBasic.CompilerServices.DesignerGenerated()>
Partial Class FormMain
    Inherits System.Windows.Forms.Form

    'Form overrides dispose to clean up the component list.
    <System.Diagnostics.DebuggerNonUserCode()>
    Protected Overrides Sub Dispose(disposing As Boolean)
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
    <System.Diagnostics.DebuggerStepThrough()>
    Private Sub InitializeComponent()
        components = New ComponentModel.Container()
        VS2015LightTheme1 = New ThemeVS2015.VS2015LightTheme()
        DockPanel1 = New Microsoft.VisualStudio.WinForms.Docking.DockPanel()
        VisualStudioToolStripExtender1 = New Microsoft.VisualStudio.WinForms.Docking.VisualStudioToolStripExtender(components)
        StatusStrip1 = New StatusStrip()
        ToolStripStatusLabel1 = New ToolStripStatusLabel()
        Ribbon1 = New Ribbon()
        StatusStrip1.SuspendLayout()
        SuspendLayout()
        ' 
        ' DockPanel1
        ' 
        DockPanel1.Dock = DockStyle.Fill
        DockPanel1.Location = New Point(0, 116)
        DockPanel1.Name = "DockPanel1"
        DockPanel1.Size = New Size(1279, 644)
        DockPanel1.TabIndex = 0
        ' 
        ' VisualStudioToolStripExtender1
        ' 
        VisualStudioToolStripExtender1.DefaultRenderer = Nothing
        ' 
        ' StatusStrip1
        ' 
        StatusStrip1.Items.AddRange(New ToolStripItem() {ToolStripStatusLabel1})
        StatusStrip1.Location = New Point(0, 760)
        StatusStrip1.Name = "StatusStrip1"
        StatusStrip1.Size = New Size(1279, 22)
        StatusStrip1.TabIndex = 1
        StatusStrip1.Text = "StatusStrip1"
        ' 
        ' ToolStripStatusLabel1
        ' 
        ToolStripStatusLabel1.Name = "ToolStripStatusLabel1"
        ToolStripStatusLabel1.Size = New Size(42, 17)
        ToolStripStatusLabel1.Text = "Ready!"
        ' 
        ' Ribbon1
        ' 
        Ribbon1.Location = New Point(0, 0)
        Ribbon1.Name = "Ribbon1"
        Ribbon1.ResourceIdentifier = Nothing
        Ribbon1.ResourceName = "OmicsWorks.RibbonMarkup.ribbon"
        Ribbon1.ShortcutTableResourceName = Nothing
        Ribbon1.Size = New Size(1279, 116)
        Ribbon1.TabIndex = 2
        ' 
        ' FormMain
        ' 
        AutoScaleDimensions = New SizeF(7F, 15F)
        AutoScaleMode = AutoScaleMode.Font
        ClientSize = New Size(1279, 782)
        Controls.Add(DockPanel1)
        Controls.Add(StatusStrip1)
        Controls.Add(Ribbon1)
        Name = "FormMain"
        Text = "Omics Works"
        StatusStrip1.ResumeLayout(False)
        StatusStrip1.PerformLayout()
        ResumeLayout(False)
        PerformLayout()
    End Sub

    Friend WithEvents VS2015LightTheme1 As ThemeVS2015.VS2015LightTheme
    Friend WithEvents DockPanel1 As Microsoft.VisualStudio.WinForms.Docking.DockPanel
    Friend WithEvents VisualStudioToolStripExtender1 As Microsoft.VisualStudio.WinForms.Docking.VisualStudioToolStripExtender
    Friend WithEvents StatusStrip1 As StatusStrip
    Friend WithEvents ToolStripStatusLabel1 As ToolStripStatusLabel
    Friend WithEvents Ribbon1 As Ribbon

End Class

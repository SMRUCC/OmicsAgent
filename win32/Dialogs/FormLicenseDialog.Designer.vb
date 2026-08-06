Imports Galaxy.Workbench.CommonDialogs

<Global.Microsoft.VisualBasic.CompilerServices.DesignerGenerated()>
Partial Class FormLicenseDialog
    Inherits InputDialog

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
        Dim resources As System.ComponentModel.ComponentResourceManager = New System.ComponentModel.ComponentResourceManager(GetType(FormLicenseDialog))
        LinkLabel1 = New LinkLabel()
        Panel1 = New Panel()
        Label1 = New Label()
        Label2 = New Label()
        RichTextBox1 = New RichTextBox()
        Panel1.SuspendLayout()
        SuspendLayout()
        ' 
        ' LinkLabel1
        ' 
        LinkLabel1.AutoSize = True
        LinkLabel1.ForeColor = Color.White
        LinkLabel1.LinkColor = Color.CornflowerBlue
        LinkLabel1.Location = New Point(25, 34)
        LinkLabel1.Name = "LinkLabel1"
        LinkLabel1.Size = New Size(91, 15)
        LinkLabel1.TabIndex = 0
        LinkLabel1.TabStop = True
        LinkLabel1.Text = "Register License"
        ' 
        ' Panel1
        ' 
        Panel1.BackColor = Color.WhiteSmoke
        Panel1.Controls.Add(LinkLabel1)
        Panel1.Dock = DockStyle.Bottom
        Panel1.Location = New Point(0, 563)
        Panel1.Name = "Panel1"
        Panel1.Size = New Size(538, 68)
        Panel1.TabIndex = 1
        ' 
        ' Label1
        ' 
        Label1.AutoSize = True
        Label1.Font = New Font("Segoe UI Black", 26.25F, FontStyle.Bold, GraphicsUnit.Point, CByte(0))
        Label1.ForeColor = Color.Turquoise
        Label1.Location = New Point(12, 20)
        Label1.Name = "Label1"
        Label1.Size = New Size(339, 47)
        Label1.TabIndex = 2
        Label1.Text = "Omics Flow Works"
        ' 
        ' Label2
        ' 
        Label2.AutoSize = True
        Label2.Location = New Point(25, 67)
        Label2.Name = "Label2"
        Label2.Size = New Size(268, 15)
        Label2.TabIndex = 3
        Label2.Text = "A LLM based omics data analysis agent workshop"
        ' 
        ' RichTextBox1
        ' 
        RichTextBox1.BackColor = Color.White
        RichTextBox1.BorderStyle = BorderStyle.None
        RichTextBox1.Location = New Point(12, 96)
        RichTextBox1.Name = "RichTextBox1"
        RichTextBox1.ReadOnly = True
        RichTextBox1.Size = New Size(514, 426)
        RichTextBox1.TabIndex = 4
        RichTextBox1.Text = ""
        ' 
        ' FormLicenseDialog
        ' 
        AutoScaleDimensions = New SizeF(7F, 15F)
        AutoScaleMode = AutoScaleMode.Font
        BackColor = Color.AliceBlue
        ClientSize = New Size(538, 631)
        Controls.Add(RichTextBox1)
        Controls.Add(Label2)
        Controls.Add(Label1)
        Controls.Add(Panel1)
        Icon = CType(resources.GetObject("$this.Icon"), Icon)
        Name = "FormLicenseDialog"
        Text = "License"
        Panel1.ResumeLayout(False)
        Panel1.PerformLayout()
        ResumeLayout(False)
        PerformLayout()
    End Sub

    Friend WithEvents LinkLabel1 As LinkLabel
    Friend WithEvents Panel1 As Panel
    Friend WithEvents Label1 As Label
    Friend WithEvents Label2 As Label
    Friend WithEvents RichTextBox1 As RichTextBox
End Class

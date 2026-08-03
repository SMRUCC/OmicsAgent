Imports Galaxy.Workbench
Imports Microsoft.VisualBasic.ApplicationServices
Imports Microsoft.VisualBasic.FileIO

Public Class FormFolderWorkspace

    Public Property Folder As String

    Private Sub RefreshTree() Handles ToolStripButton1.Click
        Dim dir As Directory = Directory.FromLocalFileSystem(Folder)
        Dim tree As FileSystemTree = FileSystemTree.BuildTree(dir.GetAllFiles)

        Call TreeView1.LoadFileSystemTree(tree, 1, 2)
    End Sub

    Private Sub FormFolderWorkspace_Load(sender As Object, e As EventArgs) Handles Me.Load
        Call RefreshTree()
    End Sub
End Class
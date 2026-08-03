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

    Private Sub TreeView1_AfterSelect(sender As Object, e As TreeViewEventArgs) Handles TreeView1.AfterSelect
        Dim node As TreeNode = e.Node

        ' skip of root node and dir node
        If node.Parent Is Nothing OrElse DirectCast(node.Tag, FileSystemTree).IsDirectory Then
            Return
        Else
            ' file display
            Dim fsNode As FileSystemTree = DirectCast(node.Tag, FileSystemTree)

            Select Case fsNode.FullName.ExtensionSuffix
                Case "csv", "tsv"

                Case "xlsx"
                Case "bmp", "jpg", "jpeg", "png", "gif", "tiff"
                Case "svg"
                Case "pdf"
                Case "txt", "log"
                Case "json", "jsonl"
                Case "xml"
                Case "html"
                Case "md"
                Case Else
                    Call CommonRuntime.Warning($"Sorry, the file type(*.{fsNode.FullName.ExtensionSuffix}) is not yet supported")
            End Select
        End If
    End Sub
End Class
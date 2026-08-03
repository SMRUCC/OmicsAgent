Imports Fluteway
Imports Galaxy.Workbench
Imports Microsoft.VisualBasic.ApplicationServices
Imports Microsoft.VisualBasic.FileIO

Public Class FormFolderWorkspace

    Public Property Folder As String

    Public ReadOnly Property Port As Integer
        Get
            If http Is Nothing Then
                Return -1
            End If

            Return http.port
        End Get
    End Property

    Dim WithEvents http As HttpServices
    Dim viewer As FormFileViewer

    Private Sub RefreshTree() Handles ToolStripButton1.Click
        Dim dir As Directory = Directory.FromLocalFileSystem(Folder)
        Dim dirname As String = Folder.GetDirectoryFullPath.Replace("\", "/")
        Dim tree As FileSystemTree = FileSystemTree.BuildTree(
            files:=dir _
                .GetAllFiles _
                .Select(Function(path)
                            Return path.Replace("\", "/").Replace(dirname, "")
                        End Function))
        Dim root As TreeNode = TreeView1.LoadFileSystemTree(tree, 1, 2)

        If Not root Is Nothing Then
            root.Text = Folder.BaseName
        End If
    End Sub

    Private Sub FormFolderWorkspace_Load(sender As Object, e As EventArgs) Handles Me.Load
        http = New HttpServices(Folder)
        http.StartHttp()

        Call RefreshTree()
    End Sub

    Private Async Sub TreeView1_AfterSelect(sender As Object, e As TreeViewEventArgs) Handles TreeView1.AfterSelect
        Dim node As TreeNode = e.Node

        ' skip of root node and dir node
        If node.Parent Is Nothing OrElse DirectCast(node.Tag, FileSystemTree).IsDirectory Then
            Return
        Else
            ' file display
            Dim fsNode As FileSystemTree = DirectCast(node.Tag, FileSystemTree)

            Select Case fsNode.FullName.ExtensionSuffix
                Case "csv", "tsv", "bmp", "jpg", "jpeg", "png", "gif", "tiff", "svg", "pdf", "txt", "log", "json", "jsonl", "xml", "html", "md"
                    If viewer Is Nothing Then
                        viewer = New FormFileViewer With {
                            .port = Port
                        }
                        Call CommonRuntime.ShowDocument(viewer)
                    End If

                    Await viewer.ViewFile(fsNode.FullName)

                Case "xlsx"
                    ' Handle Excel files
                Case Else
                    Call CommonRuntime.Warning($"Sorry, the file type(*.{fsNode.FullName.ExtensionSuffix}) is not yet supported")
            End Select
        End If
    End Sub
End Class
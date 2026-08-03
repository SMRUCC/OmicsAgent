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
    Dim WithEvents viewer As FormFileViewer

    ' 当前被勾选（需要显示）的文件扩展名集合，小写含点，例如 ".csv"
    ' 集合为空时表示不过滤，显示所有类型文件
    Private selectedExtensions As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)

    Private Sub RefreshTree() Handles ToolStripButton1.Click
        ' 手动刷新时重新收集扩展名并重建过滤下拉项
        Call BuildFilterDropDown()
        Call RefreshTree(selectedExtensions)
    End Sub

    Private Sub RefreshTree(filterSet As IEnumerable(Of String))
        Dim dir As Directory = Directory.FromLocalFileSystem(Folder)
        Dim dirname As String = Folder.GetDirectoryFullPath.Replace("\", "/")

        Dim files = dir.GetAllFiles

        ' 当 filterSet 为空（全部未勾选）时不过滤，显示所有文件
        If filterSet IsNot Nothing AndAlso filterSet.Any() Then
            files = files _
                .Where(Function(path)
                           Return filterSet.Contains(IO.Path.GetExtension(path).ToLowerInvariant())
                       End Function)
        End If

        Dim tree As FileSystemTree = FileSystemTree.BuildTree(
            files:=files _
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

        Call BuildFilterDropDown()
        Call RefreshTree(selectedExtensions)
        Call ApplyVsTheme(ContextMenuStrip1, ToolStrip1)
    End Sub

    ' 收集当前文件夹下所有文件扩展名，动态生成带 Check 状态的下拉菜单项
    Private Sub BuildFilterDropDown()
        Dim dir As Directory = Directory.FromLocalFileSystem(Folder)

        Dim extensions = dir _
            .GetAllFiles _
            .Select(Function(path) IO.Path.GetExtension(path).ToLowerInvariant()) _
            .Where(Function(ext) Not String.IsNullOrEmpty(ext)) _
            .Distinct(StringComparer.OrdinalIgnoreCase) _
            .OrderBy(Function(ext) ext) _
            .ToArray()

        ToolStripDropDownButton1.DropDownItems.Clear()

        For Each ext As String In extensions
            Dim item As New ToolStripMenuItem(ext) With {
                .CheckOnClick = True,
                .Checked = False
            }

            ' 初始全部不勾选：默认显示所有文件
            AddHandler item.Click, AddressOf OnFilterItemClick

            ToolStripDropDownButton1.DropDownItems.Add(item)
        Next
    End Sub

    ' 勾选/取消勾选扩展名时实时更新集合并重建 TreeView
    Private Sub OnFilterItemClick(sender As Object, e As EventArgs)
        Dim item As ToolStripMenuItem = DirectCast(sender, ToolStripMenuItem)
        Dim ext As String = item.Text.ToLowerInvariant()

        If item.Checked Then
            Call selectedExtensions.Add(ext)
        Else
            Call selectedExtensions.Remove(ext)
        End If

        ' 实时刷新：集合为空（全部未勾选）时显示所有文件
        Call RefreshTree(selectedExtensions)
    End Sub

    Private Async Sub TreeView1_AfterSelect(sender As Object, e As TreeViewEventArgs) Handles TreeView1.AfterSelect
        Dim node As TreeNode = e.Node

        ' skip of root node and dir node
        If node.Parent Is Nothing OrElse DirectCast(node.Tag, FileSystemTree).IsDirectory Then
            Return
        Else
            ' file display
            Dim fsNode As FileSystemTree = DirectCast(node.Tag, FileSystemTree)
            Dim filetype As String = fsNode.FullName.ExtensionSuffix

            Select Case filetype
                Case "csv", "tsv", "bmp", "jpg", "jpeg", "png", "gif", "tiff", "svg", "pdf", "txt", "log", "json", "jsonl", "xml", "html", "md"
                    If viewer Is Nothing OrElse viewer.Pinned Then
                        viewer = New FormFileViewer With {
                            .port = Port
                        }
                        Call CommonRuntime.ShowDocument(viewer)
                    End If

                    Await viewer.CheckReady
                    Await viewer.ViewFile(fsNode.FullName)

                Case "xlsx"
                    ' Handle Excel files
                Case Else
                    Call CommonRuntime.Warning($"Sorry, the file type(*.{filetype}) is not yet supported")
            End Select

            Select Case filetype
                Case "csv", "tsv", "txt", "log", "json", "jsonl", "xml", "html", "md"
                    Dim llm = RibbonMenu.OpenLLmTool.WebView2llmui1

                    Await llm.ClearFileReference
                    Await llm.SetFileReference(Folder & "/" & fsNode.FullName)
            End Select
        End If
    End Sub

    Private Async Sub ToolStripButton2_Click(sender As Object, e As EventArgs) Handles ToolStripButton2.Click
        If Not viewer Is Nothing Then
            Await viewer.CheckReady
            Await viewer.WebView21.ExecuteScriptAsync("toggleTheme();")
        End If
    End Sub

    Private Sub viewer_FormClosing(sender As Object, e As FormClosingEventArgs) Handles viewer.FormClosing
        viewer = Nothing
    End Sub

    Private Sub PinToolStripMenuItem_Click(sender As Object, e As EventArgs) Handles PinToolStripMenuItem.Click
        If Not viewer Is Nothing Then
            viewer.Pinned = True
        End If
    End Sub
End Class
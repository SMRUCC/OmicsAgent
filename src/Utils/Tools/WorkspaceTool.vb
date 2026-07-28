Public MustInherit Class WorkspaceTool

    Protected ReadOnly _workspaceRoot As String
    Protected ReadOnly _logger As Action(Of String)

    Public Sub New(workspaceRoot As String, Optional logger As Action(Of String) = Nothing)
        _workspaceRoot = workspaceRoot
        _logger = If(logger, AddressOf Console.WriteLine)
    End Sub

    Protected Overridable Function ResolvePath(relativePath As String) As String
        If String.IsNullOrWhiteSpace(relativePath) Then Return ""
        If Path.IsPathRooted(relativePath) Then Return relativePath
        Return Path.GetFullPath(Path.Combine(_workspaceRoot, relativePath))
    End Function

    Protected Shared Function EscapeJson(input As String) As String
        If String.IsNullOrEmpty(input) Then Return ""
        Return input.Replace("\", "\\").Replace("""", "\""").Replace(vbCr, "\r").Replace(vbLf, "\n").Replace(vbTab, "\t")
    End Function
End Class

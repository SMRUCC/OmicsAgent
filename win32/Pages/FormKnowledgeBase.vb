Imports Galaxy.Workbench

Public Class FormKnowledgeBase

    Private Async Sub FormKnowledgeBase_Load(sender As Object, e As EventArgs) Handles Me.Load
        Await WebViewLoader.Init(WebView21)
    End Sub
End Class
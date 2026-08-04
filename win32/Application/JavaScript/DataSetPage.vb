Namespace JavaScript

    Public Class DataSetPage : Inherits BasePage

        Public Async Function OpenFile() As Task(Of String)
            Using file As New OpenFileDialog With {.Filter = "Excel Table(*.csv)|*.csv"}
                If file.ShowDialog = DialogResult.OK Then
                    Return Await Task.FromResult(file.FileName)
                End If
            End Using

            Return Nothing
        End Function

    End Class
End Namespace
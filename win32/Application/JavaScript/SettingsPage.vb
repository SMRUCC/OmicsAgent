Imports System.Runtime.InteropServices

Namespace JavaScript

    <ClassInterface(ClassInterfaceType.AutoDual)>
    <ComVisible(True)>
    Public Class SettingsPage : Inherits BasePage

        Public Sub New(owner As Form)
            MyBase.New(owner)
        End Sub

        Public Async Function Save(config_json As String) As Task
            Await DirectCast(_owner, FormSettings).SaveSettings(config_json)
        End Function
    End Class
End Namespace
---
name: FormFolderWorkspace文件类型过滤
overview: 在 FormFolderWorkspace 的工具栏 ToolStripDropDownButton1 中动态生成扩展名过滤按钮（可勾选），根据勾选状态实时过滤 TreeView 文件显示；空目录隐藏；全部未勾选时显示所有文件。
todos:
  - id: add-filter-fields
    content: 在 FormFolderWorkspace.vb 增加 selectedExtensions 字段与重载 RefreshTree 过滤参数
    status: completed
  - id: build-dropdown
    content: 实现 BuildFilterDropDown 方法，收集扩展名并动态生成勾选菜单项
    status: completed
    dependencies:
      - add-filter-fields
  - id: wire-click
    content: 实现 OnFilterItemClick，更新集合并实时重建 TreeView
    status: completed
    dependencies:
      - build-dropdown
  - id: hook-load-refresh
    content: 在 Load 与 Refresh 时调用 BuildFilterDropDown 完成初始填充
    status: completed
    dependencies:
      - build-dropdown
---

## 用户需求

在 `Tools\FormFolderWorkspace.vb` 文件夹浏览器 WinForm 工具栏中增加文件类型过滤功能。

## 产品概述

为文件夹工作区窗口的工具栏"Filter Files"下拉按钮动态加载当前文件夹内所有文件扩展名列表，用户可勾选/取消勾选扩展名，实时过滤 TreeView 中显示的文件。

## 核心功能

- 加载文件树时收集当前文件夹下所有文件的扩展名（去重、排序），动态生成带 Check 状态的菜单项加入 `ToolStripDropDownButton1`。
- 动态生成的菜单项默认全部不勾选；勾选状态实时生效。
- 仅显示被勾选扩展名的文件；未被勾选的扩展名文件不在 TreeView 展示。
- 当所有动态菜单项均未勾选时，显示所有类型文件（等价于不过滤）。
- 过滤时隐藏不包含任何通过过滤文件/子目录的空目录节点。
- 每次勾选状态变化后立即重建 TreeView 应用过滤。

## 技术栈

- 语言/框架：VB.NET + Windows Forms（.NET 10, net10.0-windows），沿用现有项目技术栈。
- 依赖类型（外部引用，来自 Fluteway/Galaxy.Workbench）：`Directory.FromLocalFileSystem`、`FileSystemTree.BuildTree`、`TreeView.LoadFileSystemTree`、`FileSystemTree.FullName.ExtensionSuffix`。

## 实现方案

### 总体策略

通过在 `BuildTree` 之前对文件路径集合做扩展名过滤来实现，而非修改 `FileSystemTree` 内部结构与 `LoadFileSystemTree` 调用。`BuildTree` 依据传入路径集合构建层级，未出现在过滤集合中的路径所对应目录若整体无子节点则自然不会被构建——从而自动达成"隐藏空目录"需求，无需额外递归裁剪。

### 关键技术决策

1. **扩展名提取**：遍历 `dir.GetAllFiles` 返回的路径，使用 `IO.Path.GetExtension(path).ToLowerInvariant()` 取得含点扩展名（如 `.csv`），去重后排序，作为下拉项文本（可展示为 `*`.csv `或 `.csv`）。
2. **过滤集合**：维护实例级 `Private selectedExtensions As New HashSet(Of String)`（小写含点）。`RefreshTree` 接收可选参数 `Optional filterSet As IEnumerable(Of String) = Nothing`；当 `filterSet` 为空（Nothing 或 Count=0）时不做过滤。
3. **动态菜单项**：在 `FormFolderWorkspace_Load`（首屏）及 `ToolStripButton1`（Refresh）触发重新收集时，清空并重建 `ToolStripDropDownButton1.DropDownItems`，为每个扩展名 `Add(New ToolStripMenuItem(ext, Nothing, AddressOf OnFilterItemClick))` 并设置 `CheckOnClick = True`、`Checked = False`。
4. **实时刷新**：`OnFilterItemClick(sender, e)` 中读取 `DirectCast(sender, ToolStripMenuItem).Checked` 与对应扩展名更新 `selectedExtensions`，随后立即调用 `RefreshTree(selectedExtensions)` 重建树。
5. **空目录隐藏**：由于过滤发生在 `BuildTree` 前，空目录路径不会进入构建集合，自动隐藏。

### 性能与可靠性

- `GetAllFiles`、扩展名去重使用 `Distinct()` + `OrderBy()`，复杂度 O(n log n)，与现有 TreeView 构建同量级，无额外瓶颈。
- 下拉项重建仅在窗口加载与手动 Refresh 时发生，勾选变化不重建下拉项（仅更新 `selectedExtensions` 并重建树），避免菜单闪烁。
- 下拉项文本与 `Path.GetExtension` 统一使用小写含点，确保集合匹配一致。

## 实现要点（执行细节）

- 复用现有 `RefreshTree()` 结构，新增重载/可选参数传入过滤扩展名集合；在 `.Select(...)` 投影前用 `.Where` 过滤路径（当 filterSet 非空时 `Where(Function(p) filterSet.Contains(IO.Path.GetExtension(p).ToLowerInvariant()))`）。
- 不要在 Designer.resx 中手动添加菜单项；全部在代码中动态生成，保持 Designer 文件最小改动（已存在 `ToolStripDropDownButton1` 声明，无需修改 Designer.vb）。
- 勾选项文本使用 `.csv` 形式（与 `ExtensionSuffix` 区分：后者不含点，统一以 `Path.GetExtension` 为准做匹配）。

## 架构设计

维持现有单窗体结构，仅在 `FormFolderWorkspace` 类内新增：一个扩展名集合字段、下拉项构建私有方法、勾选事件处理方法，以及 `RefreshTree` 的过滤参数。不引入新类或新模块，符合 YAGNI/SoC。

## 目录结构

```
win32/Tools/
├── FormFolderWorkspace.vb          # [MODIFY] 增加 selectedExtensions 字段；扩展 RefreshTree 支持过滤参数；
│                                   #           新增 BuildFilterDropDown() 与 OnFilterItemClick()；
│                                   #           在 Load 与 Refresh 时收集扩展名并填充 ToolStripDropDownButton1。
├── FormFolderWorkspace.Designer.vb # [无需修改] ToolStripDropDownButton1 已声明并初始化。
└── FormFolderWorkspace.resx        # [无需修改] Filter Files 图标已存在。
```
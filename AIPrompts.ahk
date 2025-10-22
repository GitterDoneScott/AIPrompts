#Requires AutoHotkey v2.0
#SingleInstance Force

; ===================== Configuration =====================
; Add as many folders as you like:
ROOT_DIRS := [
    A_ScriptDir
    ; , "D:\AnotherPromptFolder"
    ; , "E:\Team\Prompts"
]

; File types to include in the picker (without the dot), case-insensitive.
INCLUDE_EXTS := ["txt", "md"]

; File names to exclude (WITH extension), case-insensitive, matched on filename only (not path).
; Example: ["readme.md", "license.md", "contributing.md"]
EXCLUDE_FILES := ["readme.md"]

PROMPT_HOTKEY := "#p"  ; Win+P to open the picker
; =========================================================

; Register hotkey & tray menu items
Hotkey(PROMPT_HOTKEY, ShowPromptMenu)
A_TrayMenu.Add("Insert AI Prompt", ShowPromptMenu)
A_TrayMenu.Add()  ; separator
A_TrayMenu.Add("Reload Script", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())

ShowPromptMenu(*) {
    global ROOT_DIRS, INCLUDE_EXTS, EXCLUDE_FILES

    items := []              ; each item: {name, ext, path, dir, rel, rootLabel}
    nameCounts := Map()      ; base name (no ext) -> count across all roots
    nameLocCounts := Map()   ; base name + location -> count (for .txt/.md disambiguation)

    ; Collect files from all configured roots
    for _, root in ROOT_DIRS {
        if !DirExist(root)
            continue
        rootTrim   := RTrim(root, "\/")
        rootLabel  := GetLastSegment(rootTrim)

        for _, ext in INCLUDE_EXTS {
            Loop Files, rootTrim "\*." ext, "R" {
                if IsExcludedFile(A_LoopFilePath)
                    continue
                AddItem(A_LoopFilePath, rootTrim, rootLabel, items, nameCounts, nameLocCounts)
            }
        }
    }

    if items.Length = 0 {
        MsgBox("No matching files found in the configured folders.", "AI Prompt Picker", "Icon!")
        return
    }

    ; Sort by base filename (case-insensitive), then by root/rel, then by extension
    SortItemsByName(items)

    ; Build and show the popup menu
    m := Menu()
    for _, it in items {
        ; Menu label WITHOUT extension
        label := it.name

        ; If duplicates exist for the same base name, show a location hint.
        if (nameCounts[it.name] > 1) {
            pathLabel := it.rootLabel
            if (it.rel != "")
                pathLabel .= "\" it.rel
            label .= " — " pathLabel

            ; If the same name appears in the same location (e.g., name.txt & name.md),
            ; add the extension in parentheses to keep menu items distinct.
            locKey := it.name "|" it.rootLabel "|" it.rel
            if nameLocCounts.Has(locKey) && nameLocCounts[locKey] > 1
                label .= " (." it.ext ")"
        }

        m.Add(label, InsertPrompt.Bind(it.path))
    }
    m.Show()  ; show at mouse
}

; --- Helpers ---------------------------------------------------------------

IsExcludedFile(fullPath) {
    global EXCLUDE_FILES
    local fname
    SplitPath(fullPath, &fname)  ; fname includes extension
    lname := StrLower(fname)
    for _, ex in EXCLUDE_FILES {
        if (lname = StrLower(ex))
            return true
    }
    return false
}

AddItem(fullPath, rootTrim, rootLabel, items, nameCounts, nameLocCounts) {
    local name, dir, ext, nameNoExt
    SplitPath(fullPath, &name, &dir, &ext, &nameNoExt)
    rel := GetRelativeDir(dir, rootTrim)

    items.Push({ name: nameNoExt
               , ext:  ext
               , path: fullPath
               , dir:  dir
               , rel:  rel
               , rootLabel: rootLabel })

    ; Count by base name
    nameCounts[nameNoExt] := nameCounts.Has(nameNoExt) ? nameCounts[nameNoExt] + 1 : 1

    ; Count by base name within the same location (rootLabel + rel)
    locKey := nameNoExt "|" rootLabel "|" rel
    nameLocCounts[locKey] := nameLocCounts.Has(locKey) ? nameLocCounts[locKey] + 1 : 1
}

GetRelativeDir(absDir, rootTrim) {
    if (absDir = rootTrim)
        return ""  ; directly in root
    if SubStr(absDir, 1, StrLen(rootTrim) + 1) = rootTrim "\"
        return SubStr(absDir, StrLen(rootTrim) + 2)
    return absDir  ; fallback (outside root)
}

GetLastSegment(path) {
    local leaf
    SplitPath(path, &leaf)
    return leaf
}

; Sort the array of item-objects IN PLACE by:
;   1) name (case-insensitive)  2) rootLabel  3) rel  4) ext
; Uses Sort(String) to avoid relying on a non-existent Array.Sort().
SortItemsByName(items) {
    if items.Length < 2
        return
    lines := ""
    for i, it in items {
        lines .= StrLower(it.name) "|" StrLower(it.rootLabel) "|" StrLower(it.rel) "|" StrLower(it.ext) "|" i "`n"
    }
    lines  := RTrim(lines, "`n")
    sorted := Sort(lines)  ; ascending
    new := []
    for _, line in StrSplit(sorted, "`n") {
        parts := StrSplit(line, "|")
        idx := parts[5] + 0
        new.Push(items[idx])
    }
    items.Length := 0
    for _, it in new
        items.Push(it)
}

; --- Action ----------------------------------------------------------------

; Read the selected file and paste its content at the caret.
InsertPrompt(filePath, *) {
    try {
        content := FileRead(filePath, "UTF-8")
    } catch Error as err {
        MsgBox(Format("Couldn't read:`n{1}`n`n{2}", filePath, err.Message)
             , "AI Prompt Picker", "Iconx")
        return
    }

    clipSaved := ClipboardAll()  ; save all clipboard formats
    try {
        A_Clipboard := content
        Send("^v")
        Sleep(50)                ; brief settle time
    } finally {
        A_Clipboard := clipSaved ; restore original clipboard
    }
}

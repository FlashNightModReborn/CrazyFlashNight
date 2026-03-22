#Requires AutoHotkey v2.0
; Flash Player 快捷键拦截脚本
; 只在 Flash Player 窗口激活时拦截 Ctrl+W 和 Ctrl+R

#HotIf WinActive("ahk_exe flashplayer.exe") or WinActive("ahk_exe Adobe Flash Player 20.exe")
    ; 拦截 Ctrl+W (关闭)
    ^w::
    {
        ; 什么都不做，只是吞掉这个快捷键
        return
    }

    ; 拦截 Ctrl+R (刷新)
    ^r::
    {
        ; 什么都不做，只是吞掉这个快捷键
        return
    }
#HotIf
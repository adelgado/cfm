-- Configuration File for 'cfm'

-- terminal : name of terminal emulator program

terminal = "urxvtc"

-- OpenProg : table mapping file extensions to their display commands

OpenProg = {
             avi     = "mplayer #",
             bmp     = "display #",
             doc     = "libreoffice #",
             docx    = "libreoffice #",
             dvi     = "xdvi #",
             htm     = "iceweasel #",
             html    = "iceweasel #",
             jpg     = "display #",
             jpeg    = "display #",                          -- needed ?
             mov     = "mplayer #",                          -- needed ?
             ods     = "libreoffice #",
             odt     = "libreoffice #",
             ogg     = "pkill ogg123; sleep 1; ogg123 -q #",
             ppt     = "libreoffice #",
             pptx    = "libreoffice #",
             pdf     = "zathura # 1>/dev/null 2>&1",
             png     = "display #",
             ps      = "zathura # 1>/dev/null 2>&1",
             rtf     = "libreoffice #",
             sxc     = "libreoffice #",
             sxi     = "libreoffice #",
             sxw     = "libreoffice #",
             wmv     = "mplayer #",                          -- needed ?
             xls     = "libreoffice #",
             xlsx    = "libreoffice #",
             xlt     = "libreoffice #",
             [ "*" ] = "elvis # >/dev/null"
           }

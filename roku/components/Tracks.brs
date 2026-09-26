' Track helpers shared by MainScene and OptionsPanel (no init — include only).
' The server's track lists (/api/movies/{id} -> files[].audio_tracks /
' subtitle_tracks) are in file order, the same order Roku lists them.

' Roku can't bitstream lossless Dolby/DTS (silence or a freeze on the Denon),
' so those stay in the picker but greyed — they play in the ELKO app.
function rokuAudioOk(t as object) as boolean
    u = UCase(strOf(t.title) + " " + strOf(t.desc))
    if Instr(1, u, "TRUEHD") > 0 or Instr(1, u, "TRUE-HD") > 0 then return false
    if Instr(1, u, "DTS-HD") > 0 or Instr(1, u, "DTS:X") > 0 or Instr(1, u, "DTS-X") > 0 then return false
    return true
end function

' Roku renders text subtitles (SRT, ASS, WebVTT); image ones (PGS, VobSub) don't
' show at all.
function rokuSubOk(s as object) as boolean
    u = UCase(strOf(s.desc))
    if Instr(1, u, "PGS") > 0 or Instr(1, u, "VOBSUB") > 0 or Instr(1, u, "DVB") > 0 then return false
    return true
end function

function trackText(t as object) as string
    s = strOf(t.title)
    d = strOf(t.desc)
    if d <> "" and d <> s then
        if s <> "" then
            s = s + " · " + d
        else
            s = d
        end if
    end if
    if s = "" then s = "Track " + strOf(t.id)
    return s
end function

function strOf(v as dynamic) as string
    if v = invalid then return ""
    if type(v) = "roString" or type(v) = "String" then return v
    return v.toStr()
end function

' 5415 -> "1:30:15", 610 -> "10:10".
function fmtTime(sec as dynamic) as string
    s = Int(sec)
    h = Int(s / 3600)
    mnt = Int((s mod 3600) / 60)
    r = s mod 60
    ss = r.toStr()
    if r < 10 then ss = "0" + ss
    if h > 0 then
        mm = mnt.toStr()
        if mnt < 10 then mm = "0" + mm
        return h.toStr() + ":" + mm + ":" + ss
    end if
    return mnt.toStr() + ":" + ss
end function

' "4K HDR" / "1080p" from a file's width/height/hdr (16:9-equivalent lines, so
' a cropped 1920x800 scope encode still reads as 1080p).
function qualityOfFile(f as dynamic) as string
    if f = invalid then return ""
    w = 0
    h = 0
    if f.width <> invalid then w = f.width
    if f.height <> invalid then h = f.height
    lines = h
    if Int(w * 9 / 16) > lines then lines = Int(w * 9 / 16)
    tag = ""
    if lines >= 2000 then
        tag = "4K"
    else if lines >= 1000 then
        tag = "1080p"
    else if lines >= 700 then
        tag = "720p"
    end if
    if f.hdr = true then
        if tag <> "" then
            tag = tag + " HDR"
        else
            tag = "HDR"
        end if
    end if
    return tag
end function

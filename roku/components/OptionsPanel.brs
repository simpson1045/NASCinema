' Options panel (the * key). Builds a flat list of rows — section headers,
' radio options, and the "Flag a problem" action — and shows a window of it.
' Tracks the Roku can't play stay listed but greyed and skipped by the cursor.

sub init()
    m.rowsGroup = m.top.findNode("rows")
    m.more = m.top.findNode("more")
    m.rowH = 58
    m.slots = 15
    m.items = []
    m.cursor = 0
    m.first = 0
    m.md = {}
    m.sel = { file: 0, audio: 0, subKey: "off" }
    m.pool = []
    for i = 0 to m.slots - 1
        g = m.rowsGroup.createChild("Group")
        g.translation = [0, i * m.rowH]
        bg = g.createChild("Rectangle")
        bg.width = 640
        bg.height = m.rowH - 6
        bg.color = "0x00000000"
        dot = g.createChild("Rectangle")
        dot.translation = [22, Int((m.rowH - 6) / 2) - 7]
        dot.width = 14
        dot.height = 14
        dot.visible = false
        lbl = g.createChild("Label")
        lbl.translation = [52, 0]
        lbl.width = 570
        lbl.height = m.rowH - 6
        lbl.vertAlign = "center"
        lbl.font = "font:SmallSystemFont"
        m.pool.push({ g: g, bg: bg, dot: dot, lbl: lbl })
    end for
end sub

sub onModel()
    md = m.top.model
    if md = invalid then return
    m.md = md
    if m.md.externals = invalid then m.md.externals = []
    m.sel = { file: intOf(md.fileIdx), audio: intOf(md.audio), subKey: strOf(md.subKey) }
    if m.sel.subKey = "" then m.sel.subKey = "off"
    build()
    m.first = 0
    m.cursor = nextSelectable(-1, 1)
    render()
end sub

sub onExternals()
    ext = m.top.externals
    if ext = invalid then ext = []
    m.md.externals = ext
    build()
    if m.cursor >= m.items.count() then m.cursor = nextSelectable(-1, 1)
    render()
end sub

function intOf(v as dynamic) as integer
    if v = invalid then return 0
    return Int(v)
end function

sub addRow(kind as string, section as string, value as dynamic, text as string, enabled as boolean)
    m.items.push({ kind: kind, section: section, value: value, text: text, enabled: enabled })
end sub

sub build()
    m.items = []
    files = m.md.files
    if files = invalid then files = []
    if m.md.allowVersion = true and files.count() > 1 then
        addRow("header", "", invalid, "VERSION", false)
        for i = 0 to files.count() - 1
            f = files[i]
            t = strOf(f.label)
            q = strOf(f.quality)
            if t = "" then t = q
            if q <> "" and q <> t then t = t + " · " + q
            addRow("opt", "file", i, t, true)
        end for
    end if

    f = invalid
    if files.count() > 0 then
        if m.sel.file < 0 or m.sel.file >= files.count() then m.sel.file = 0
        f = files[m.sel.file]
    end if
    if f <> invalid then
        addRow("header", "", invalid, "AUDIO", false)
        addRow("opt", "audio", 0, "Auto (best for this TV)", true)
        if f.audio_tracks <> invalid then
            for each t in f.audio_tracks
                ok = rokuAudioOk(t)
                txt = trackText(t)
                if not ok then txt = txt + "  (ELKO app)"
                addRow("opt", "audio", intOf(t.id), txt, ok)
            end for
        end if

        addRow("header", "", invalid, "SUBTITLES", false)
        addRow("opt", "sub", "off", "Off", true)
        if f.subtitle_tracks <> invalid then
            for each s in f.subtitle_tracks
                ok = rokuSubOk(s)
                txt = trackText(s)
                if not ok then txt = txt + "  (ELKO app)"
                addRow("opt", "sub", "e:" + strOf(s.id), txt, ok)
            end for
        end if
        for each x in m.md.externals
            addRow("opt", "sub", "x:" + strOf(x.url), strOf(x.label) + " · Downloaded", true)
        end for
    end if

    if m.md.flag = true then
        addRow("header", "", invalid, "", false)
        addRow("action", "flag", invalid, "Flag a problem", true)
    end if
end sub

function nextSelectable(from as integer, dir as integer) as integer
    i = from + dir
    while i >= 0 and i < m.items.count()
        it = m.items[i]
        if it.kind <> "header" and it.enabled then return i
        i = i + dir
    end while
    if from < 0 then return 0
    return from
end function

function isSelected(it as object) as boolean
    if it.kind <> "opt" then return false
    if it.section = "file" then return it.value = m.sel.file
    if it.section = "audio" then return it.value = m.sel.audio
    if it.section = "sub" then return it.value = m.sel.subKey
    return false
end function

sub render()
    n = m.items.count()
    if m.cursor < m.first then m.first = m.cursor
    if m.cursor >= m.first + m.slots then m.first = m.cursor - m.slots + 1
    ' Keep a section's header in view when the cursor sits on its first row.
    if m.first > 0 and m.cursor = m.first then
        if m.items[m.first - 1].kind = "header" then m.first = m.first - 1
    end if
    if m.first < 0 then m.first = 0

    for i = 0 to m.slots - 1
        p = m.pool[i]
        idx = m.first + i
        if idx >= n then
            p.g.visible = false
        else
            it = m.items[idx]
            p.g.visible = true
            p.lbl.text = it.text
            if it.kind = "header" then
                p.bg.color = "0x00000000"
                p.dot.visible = false
                p.lbl.color = "0xFFB020FF"
                p.lbl.font = "font:SmallBoldSystemFont"
            else
                focused = (idx = m.cursor)
                p.lbl.font = "font:SmallSystemFont"
                if focused then
                    p.bg.color = "0xFFFFFFFF"
                    p.lbl.color = "0x0A0E27FF"
                    p.dot.color = "0x0A0E27FF"
                else
                    p.bg.color = "0x00000000"
                    p.dot.color = "0xFFB020FF"
                    if it.enabled then
                        p.lbl.color = "0xEEF1FFFF"
                    else
                        p.lbl.color = "0x5A6288FF"
                    end if
                end if
                p.dot.visible = isSelected(it)
            end if
        end if
    end for

    if m.first + m.slots < n then
        m.more.text = "More below"
    else
        m.more.text = ""
    end if
end sub

sub choose()
    if m.cursor < 0 or m.cursor >= m.items.count() then return
    it = m.items[m.cursor]
    if not it.enabled then return
    if it.kind = "action" then
        m.top.flag = true
        return
    end if
    if it.section = "file" then
        if it.value = m.sel.file then return
        ' Another version has its own tracks: back to Auto audio, subtitles off.
        m.sel.file = it.value
        m.sel.audio = 0
        m.sel.subKey = "off"
        m.md.externals = []
        build()
    else if it.section = "audio" then
        m.sel.audio = it.value
    else if it.section = "sub" then
        m.sel.subKey = it.value
    end if
    render()
    m.top.changed = { fileIdx: m.sel.file, audio: m.sel.audio, subKey: m.sel.subKey }
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return true
    if key = "up" then
        m.cursor = nextSelectable(m.cursor, -1)
        render()
    else if key = "down" then
        m.cursor = nextSelectable(m.cursor, 1)
        render()
    else if key = "OK" then
        choose()
    else if key = "back" or key = "options" then
        m.top.closed = true
    end if
    return true   ' the panel owns the remote while it's open
end function

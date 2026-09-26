' Movie page logic. Loads /api/movies/{id}, then the chosen version's saved
' progress (/api/progress/{file}) and downloaded subtitles (/api/subtitles/{file}).
' Left/Right pick a button, OK presses it, * asks MainScene for the options
' panel, Back closes.

sub init()
    m.backdrop = m.top.findNode("backdrop")
    m.logo = m.top.findNode("logo")
    m.logoSub = m.top.findNode("logoSub")
    m.title = m.top.findNode("title")
    m.meta = m.top.findNode("meta")
    m.overview = m.top.findNode("overview")
    m.summary = m.top.findNode("summary")
    m.buttons = m.top.findNode("buttons")
    m.status = m.top.findNode("status")
    m.meta.itemSpacings = [18]   ' array field -> set in code, not XML
    m.tasks = []
    m.detail = invalid
    m.btns = []
    m.focus = 0
    m.resume = 0
    m.fileIdx = -1
end sub

sub onMovieId()
    id = m.top.movieId
    if id = invalid or id <= 0 then return
    m.detail = invalid
    m.resume = 0
    m.fileIdx = -1
    m.focus = 0
    m.backdrop.uri = ""
    m.logo.uri = ""
    m.logo.visible = false
    m.logoSub.visible = false
    m.title.visible = false
    m.overview.text = ""
    m.summary.text = ""
    clearGroup(m.meta)
    clearGroup(m.buttons)
    m.btns = []
    m.top.externals = []
    m.top.subSaved = ""
    m.status.text = "Loading…"
    m.status.visible = true
    m.detailTask = http("GET", "/api/movies/" + id.toStr(), "")
    m.detailTask.observeField("response", "onDetail")
end sub

function http(method as string, path as string, body as string) as object
    t = createObject("roSGNode", "HttpTask")
    t.url = m.top.base + path
    t.method = method
    t.body = body
    t.control = "RUN"
    m.tasks.push(t)   ' keep a reference so it isn't collected mid-flight
    if m.tasks.count() > 20 then m.tasks.shift()
    return t
end function

sub clearGroup(g as object)
    while g.getChildCount() > 0
        g.removeChildIndex(0)
    end while
end sub

sub onDetail()
    json = ParseJson(m.detailTask.response)
    if json = invalid then
        m.status.text = "Couldn't load this movie"
        return
    end if
    ' A late reply for a movie we've already left.
    if json.id <> m.top.movieId then return
    if json.files = invalid then json.files = []
    m.detail = json
    m.top.detail = json
    m.status.visible = false

    bp = json.backdrop_path
    if bp <> invalid and bp <> "" then m.backdrop.uri = "https://image.tmdb.org/t/p/w1280" + bp
    lg = json.logo
    if lg <> invalid and lg <> "" then
        m.logo.uri = lg
        m.logo.visible = true
        sb = strOf(json.logo_subtitle)
        m.logoSub.text = sb
        m.logoSub.visible = sb <> ""
    else
        m.title.text = strOf(json.title)
        m.title.visible = true
    end if
    m.overview.text = strOf(json.overview)

    m.top.choice = { fileIdx: 0, audio: 0, subKey: "off" }   ' -> onChoice
end sub

' The picks changed (first load, or the options panel). A different version
' has its own progress and downloaded subtitles, so re-read those.
sub onChoice()
    if m.detail = invalid then return
    c = m.top.choice
    if c = invalid then return
    idx = Int(c.fileIdx)
    f = fileAt(idx)
    metaBuild(m.meta, m.detail, qualityOfFile(f))
    layoutInfo()
    if idx <> m.fileIdx then
        m.fileIdx = idx
        m.resume = 0
        m.top.externals = []
        m.top.subSaved = ""
        if f <> invalid then loadFileSide(f.id)
    end if
    buildButtons()
    updateSummary()
end sub

function fileAt(idx as integer) as dynamic
    if m.detail = invalid then return invalid
    files = m.detail.files
    if files = invalid or files.count() = 0 then return invalid
    if idx < 0 or idx >= files.count() then return files[0]
    return files[idx]
end function

sub loadFileSide(fileId as integer)
    m.progTask = http("GET", "/api/progress/" + fileId.toStr(), "")
    m.progTask.observeField("response", "onProgress")
    m.subsTask = http("GET", "/api/subtitles/" + fileId.toStr(), "")
    m.subsTask.observeField("response", "onSubs")
end sub

sub onRefresh()
    f = fileAt(m.fileIdx)
    if f = invalid then return
    m.progTask = http("GET", "/api/progress/" + f.id.toStr(), "")
    m.progTask.observeField("response", "onProgress")
end sub

sub onProgress()
    json = ParseJson(m.progTask.response)
    if json = invalid then return
    pos = 0
    if json.position <> invalid then pos = Int(json.position)
    m.resume = pos
    m.top.subSaved = strOf(json.subtitle)
    m.focus = 0   ' land on Resume/Play after a (re)load
    buildButtons()
end sub

sub onSubs()
    json = ParseJson(m.subsTask.response)
    if json = invalid or json.subtitles = invalid then return
    m.top.externals = json.subtitles
    updateSummary()
end sub

' Center the logo (and its sequel line) over the rating row — the house rule
' for any logo over a line of text. Neither moves left of the usual edge.
sub layoutInfo()
    w = metaWidth(m.meta, 18)
    b = 520
    if w > b then b = w
    metaY = 428
    if m.logoSub.visible then metaY = 470
    if m.logo.visible then
        m.logo.translation = [90 + Int((b - 520) / 2), 250]
        m.logoSub.width = b
        m.logoSub.translation = [90, 408]
        m.meta.translation = [92 + Int((b - w) / 2), metaY]
    else
        m.meta.translation = [92, 470]
    end if
end sub

sub buildButtons()
    specs = []
    if m.detail <> invalid then
        if m.detail.files.count() > 0 then
            if m.resume >= 60 then
                specs.push({ id: "resume", text: "Resume " + fmtTime(m.resume) })
                specs.push({ id: "start", text: "Play from start" })
            else
                specs.push({ id: "play", text: "Play" })
            end if
            specs.push({ id: "options", text: "Audio & Subtitles" })
        end if
        if m.detail.in_watchlist = true then
            specs.push({ id: "mylist", text: "On My List" })
        else
            specs.push({ id: "mylist", text: "+ My List" })
        end if
    end if

    clearGroup(m.buttons)
    m.btns = []
    x = 0
    for each s in specs
        g = m.buttons.createChild("Group")
        g.translation = [x, 0]
        bg = g.createChild("Rectangle")
        bg.height = 72
        lbl = g.createChild("Label")
        lbl.translation = [34, 0]
        lbl.height = 72
        lbl.vertAlign = "center"
        lbl.font = "font:MediumBoldSystemFont"
        lbl.text = s.text
        w = Int(lbl.boundingRect().width) + 68
        if w < 180 then w = 180
        bg.width = w
        m.btns.push({ id: s.id, bg: bg, lbl: lbl })
        x = x + w + 22
    end for
    if m.focus >= m.btns.count() then m.focus = 0
    paintButtons()
end sub

sub paintButtons()
    for i = 0 to m.btns.count() - 1
        b = m.btns[i]
        if i = m.focus then
            b.bg.color = "0xFFFFFFFF"
            b.lbl.color = "0x0A0E27FF"
        else
            b.bg.color = "0xFFFFFF30"
            b.lbl.color = "0xFFFFFFFF"
        end if
    end for
end sub

' "4K HDR · Remux     Audio: Auto     Subtitles: Off"
sub updateSummary()
    c = m.top.choice
    f = fileAt(m.fileIdx)
    if f = invalid or c = invalid then
        m.summary.text = ""
        return
    end if
    v = qualityOfFile(f)
    if m.detail.files.count() > 1 then
        lb = strOf(f.label)
        if lb <> "" and lb <> v then v = lb + " · " + v
    end if

    a = "Auto"
    if Int(c.audio) > 0 and f.audio_tracks <> invalid then
        for each t in f.audio_tracks
            if t.id = Int(c.audio) then a = trackText(t)
        end for
    end if

    s = "Off"
    key = strOf(c.subKey)
    if Left(key, 2) = "e:" and f.subtitle_tracks <> invalid then
        n = Mid(key, 3).toInt()
        for each st in f.subtitle_tracks
            if st.id = n then s = trackText(st)
        end for
    else if Left(key, 2) = "x:" then
        s = "Downloaded"
        ext = m.top.externals
        if ext <> invalid then
            for each x in ext
                if "x:" + strOf(x.url) = key then s = strOf(x.label) + " · Downloaded"
            end for
        end if
    end if

    txt = "Audio: " + a + "      Subtitles: " + s
    if v <> "" then txt = v + "      " + txt
    m.summary.text = txt
end sub

sub pressButton()
    if m.focus < 0 or m.focus >= m.btns.count() then return
    id = m.btns[m.focus].id
    if id = "resume" then
        m.top.play = { position: m.resume }
    else if id = "start" or id = "play" then
        m.top.play = { position: 0 }
    else if id = "options" then
        m.top.wantOptions = true
    else if id = "mylist" then
        toggleMyList()
    end if
end sub

sub toggleMyList()
    d = m.detail
    if d = invalid then return
    if d.in_watchlist = true then
        http("DELETE", "/api/watchlist/" + d.id.toStr(), "")
        d.in_watchlist = false
    else
        http("PUT", "/api/watchlist/" + d.id.toStr(), "")
        d.in_watchlist = true
    end if
    m.detail = d
    keep = m.focus
    buildButtons()
    m.focus = keep
    paintButtons()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "left" then
        if m.focus > 0 then m.focus = m.focus - 1
        paintButtons()
        return true
    else if key = "right" then
        if m.focus < m.btns.count() - 1 then m.focus = m.focus + 1
        paintButtons()
        return true
    else if key = "OK" then
        pressButton()
        return true
    else if key = "options" then
        m.top.wantOptions = true
        return true
    else if key = "back" then
        m.top.closed = true
        return true
    else if key = "up" or key = "down" then
        return true
    end if
    return false
end function

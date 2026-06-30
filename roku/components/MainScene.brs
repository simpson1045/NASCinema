' NASCinema main scene: load the server-composed home (carousel rails) and play
' on select. The backend decides what rails exist (Continue Watching, Popular,
' Recently Added, Top Rated, genres) — the TV just renders them.

sub init()
    ' Backend base URL — the NASCinema server on the LAN (ALPINE).
    m.base = "http://192.168.0.150:8400"
    m.logTasks = []

    m.brand = m.top.findNode("brand")
    m.status = m.top.findNode("status")
    m.rows = m.top.findNode("rows")
    m.video = m.top.findNode("video")

    ' RowList sizing (per Roku's working sample): rowItemSize = each tile's size;
    ' itemSize = the RowList's overall visible width x per-row height. WITHOUT
    ' itemSize the list collapses to ~44px wide and renders zero tiles. These are
    ' set in code so the array types are unambiguous.
    m.rows.rowItemSize = [[200, 350]]
    m.rows.itemSize = [1740, 410]
    m.rows.itemSpacing = [26, 40]
    m.rows.showRowLabel = [true]

    m.rows.observeField("rowItemSelected", "onItemSelected")
    m.video.observeField("state", "onVideoState")

    logmsg("channel init; base=" + m.base)
    loadHome()
end sub

' Ship a debug line back to the backend's /cast/log so we can read it remotely
' (no telnet needed). Fire-and-forget.
sub logmsg(s as string)
    print "[NASCinema] "; s
    t = createObject("roSGNode", "HttpTask")
    t.url = m.base + "/cast/log"
    t.method = "POST"
    t.body = FormatJson({ msg: "[roku] " + s })
    t.control = "RUN"
    m.logTasks.push(t)   ' keep a reference so it isn't collected mid-flight
end sub

sub loadHome()
    m.status.text = "Loading your library…"
    m.status.visible = true
    m.homeTask = createObject("roSGNode", "HttpTask")
    m.homeTask.url = m.base + "/api/home"
    m.homeTask.observeField("response", "onHomeLoaded")
    m.homeTask.control = "RUN"
end sub

sub onHomeLoaded()
    resp = m.homeTask.response
    if resp = invalid or resp = "" then
        m.status.text = "Couldn't reach the server at " + m.base
        logmsg("home fetch FAILED (empty response)")
        return
    end if

    json = ParseJson(resp)
    if json = invalid then
        m.status.text = "Bad response from the server"
        logmsg("home parse FAILED")
        return
    end if
    if json.rails = invalid or json.rails.count() = 0 then
        m.status.text = "No movies found — run a scan"
        logmsg("home has 0 rails")
        return
    end if

    root = createObject("roSGNode", "ContentNode")
    total = 0
    for each rail in json.rails
        row = root.createChild("ContentNode")
        if rail.title <> invalid then row.title = rail.title
        if rail.movies <> invalid then
            for each mv in rail.movies
                appendMovie(row, mv)
                total = total + 1
            end for
        end if
    end for

    logmsg("home: " + json.rails.count().toStr() + " rails, " + total.toStr() + " tiles")

    m.rows.content = root
    m.status.visible = false
    m.rows.visible = true
    m.rows.setFocus(true)
end sub

function firstStr(v as dynamic) as string
    if v = invalid then return "(none)"
    return v.toStr()
end function

sub appendMovie(row as object, mv as object)
    item = row.createChild("ContentNode")
    item.title = mv.title
    if mv.poster_path <> invalid then
        if mv.poster_path <> "" then
            item.HDPOSTERURL = "https://image.tmdb.org/t/p/w500" + mv.poster_path
        end if
    end if
    item.addFields({ movieId: mv.id })
end sub

sub onItemSelected()
    sel = m.rows.rowItemSelected   ' [rowIndex, itemIndex]
    if sel = invalid or sel.count() < 2 then return
    row = m.rows.content.getChild(sel[0])
    if row = invalid then return
    item = row.getChild(sel[1])
    if item = invalid then return

    m.status.text = "Loading…"
    m.status.visible = true
    m.detailTask = createObject("roSGNode", "HttpTask")
    m.detailTask.url = m.base + "/api/movies/" + item.movieId.toStr()
    m.detailTask.observeField("response", "onDetailLoaded")
    m.detailTask.control = "RUN"
end sub

sub onDetailLoaded()
    resp = m.detailTask.response
    json = ParseJson(resp)
    if json = invalid or json.files = invalid or json.files.count() = 0 then
        m.status.text = "No playable file"
        m.status.visible = true
        logmsg("detail: no playable file")
        return
    end if

    chosen = json.files[0]
    for each f in json.files
        if f.kind <> invalid then
            if f.kind = "feature" then
                chosen = f
                exit for
            end if
        end if
    end for

    playFile(chosen, json.title)
end sub

sub playFile(file as object, title as dynamic)
    vc = createObject("roSGNode", "ContentNode")
    vc.url = m.base + "/api/stream/" + file.id.toStr() + "/direct"
    vc.streamFormat = streamFormatFor(file.container)
    if title <> invalid then vc.title = title

    logmsg("play " + vc.url + " (container=" + firstStr(file.container) + " -> " + vc.streamFormat + ")")

    m.video.content = vc
    m.status.visible = false
    m.video.visible = true
    m.video.setFocus(true)
    m.video.control = "play"
end sub

function streamFormatFor(container as dynamic) as string
    if container = invalid then return "mp4"
    c = LCase(container)
    if Instr(1, c, "matroska") > 0 or Instr(1, c, "mkv") > 0 then return "mkv"
    if Instr(1, c, "webm") > 0 then return "mkv"
    if Instr(1, c, "mpegts") > 0 or Instr(1, c, "ts") > 0 then return "ts"
    return "mp4"
end function

sub onVideoState()
    st = m.video.state

    extra = " pos=" + Int(m.video.position).toStr() + "s audio=" + firstStr(m.video.audioFormat)
    si = m.video.streamInfo
    if si <> invalid then
        if si.measuredBitrate <> invalid then extra = extra + " measKbps=" + si.measuredBitrate.toStr()
        if si.streamBitrate <> invalid then extra = extra + " streamKbps=" + si.streamBitrate.toStr()
        if si.isUnderrun <> invalid then extra = extra + " underrun=" + si.isUnderrun.toStr()
    end if

    if st = "error" then
        logmsg("video ERROR code=" + m.video.errorCode.toStr() + " msg=" + firstStr(m.video.errorMsg) + extra)
        backToRows()
    else if st = "finished" then
        logmsg("video finished" + extra)
        backToRows()
    else
        logmsg("video state=" + st + extra)
    end if
end sub

sub backToRows()
    m.video.control = "stop"
    m.video.visible = false
    m.rows.visible = true
    m.rows.setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back" and m.video.visible then
        backToRows()
        return true
    end if
    return false
end function

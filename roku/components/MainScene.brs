' NASCinema main scene: load the server-composed home (carousel rails) and play
' on select. The backend decides what rails exist (Continue Watching, Popular,
' Recently Added, Top Rated, genres) — the TV just renders them.

sub init()
    ' Backend base URL — through NPM/HTTPS like every other app (not the raw LAN
    ' IP). HttpTask sets the cert bundle; the Video node streams HTTPS fine.
    m.base = "https://nascinema.simpson1045.com"
    m.logTasks = []

    m.brand = m.top.findNode("brand")
    m.status = m.top.findNode("status")
    m.hero = m.top.findNode("hero")
    m.rows = m.top.findNode("rows")
    m.video = m.top.findNode("video")
    m.zone = "hero"   ' which area has focus: "hero" or "rows"

    ' RowList sizing (per Roku's working sample): rowItemSize = each tile's size;
    ' itemSize = the RowList's overall visible width x per-row height. WITHOUT
    ' itemSize the list collapses to ~44px wide and renders zero tiles. These are
    ' set in code so the array types are unambiguous.
    ' Per-row sizes (rowItemSize / rowHeights) are set in onHomeLoaded, since
    ' Continue Watching uses wide backdrop cards and the other rails use posters.
    m.rows.rowItemSize = [[200, 350]]
    m.rows.itemSize = [1830, 410]
    m.rows.itemSpacing = [26, 30]
    m.rows.showRowLabel = [true]

    m.rows.observeField("rowItemSelected", "onItemSelected")
    m.hero.observeField("playMovieId", "onHeroPlay")
    m.video.observeField("state", "onVideoState")
    ' Roku defaults to the first audio track, which on our remuxes is lossless
    ' TrueHD/Atmos — Roku CAN'T bitstream that (silence + freeze). When the track
    ' list arrives, switch to the best track Roku CAN pass through (E-AC3/Atmos,
    ' then AC-3), skipping TrueHD/DTS-HD and commentaries. Direct play, file
    ' untouched — we just point it at the right existing track.
    m.video.observeField("availableAudioTracks", "onAudioTracks")
    m.audioPicked = false

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
    itemSizes = []
    heights = []
    for each rail in json.rails
        ' A rail whose movies carry a resume point (Continue Watching) gets wide
        ' backdrop cards with a progress bar; everything else gets posters.
        wide = false
        if rail.movies <> invalid and rail.movies.count() > 0 then
            if rail.movies[0].resume_position <> invalid then wide = true
        end if
        row = root.createChild("ContentNode")
        if rail.title <> invalid then row.title = rail.title
        if rail.movies <> invalid then
            for each mv in rail.movies
                appendMovie(row, mv, wide)
                total = total + 1
            end for
        end if
        if wide then
            itemSizes.push([480, 320])   ' 480x270 card + one-line title
            heights.push(370)
        else
            itemSizes.push([200, 350])   ' 200x300 poster + two-line title
            heights.push(410)
        end if
    end for

    logmsg("home: " + json.rails.count().toStr() + " rails, " + total.toStr() + " tiles")

    m.rows.rowItemSize = itemSizes
    m.rows.rowHeights = heights
    m.rows.content = root
    m.status.visible = false
    m.rows.visible = true

    ' Featured hero on top. Start focus on the rails so the hero begins MUTED;
    ' pressing up moves to the hero and brings its audio in.
    if json.featured <> invalid and json.featured.count() > 0 then
        m.hero.base = m.base
        m.hero.featured = json.featured
        m.hero.visible = true
    end if

    if root.getChildCount() > 0 then
        m.zone = "rows"
        m.hero.active = false
        m.rows.setFocus(true)
    else
        m.zone = "hero"
        m.hero.active = true
        m.hero.setFocus(true)
    end if
end sub

function firstStr(v as dynamic) as string
    if v = invalid then return "(none)"
    return v.toStr()
end function

sub appendMovie(row as object, mv as object, wide as boolean)
    item = row.createChild("ContentNode")
    item.title = mv.title
    progress = 0.0
    if wide then
        if mv.backdrop_path <> invalid and mv.backdrop_path <> "" then
            item.HDPOSTERURL = "https://image.tmdb.org/t/p/w780" + mv.backdrop_path
        end if
        ' resume_position is seconds, runtime is minutes.
        if mv.resume_position <> invalid and mv.runtime <> invalid and mv.runtime > 0 then
            progress = mv.resume_position / (mv.runtime * 60.0)
            if progress > 1 then progress = 1.0
        end if
    else if mv.poster_path <> invalid then
        if mv.poster_path <> "" then
            item.HDPOSTERURL = "https://image.tmdb.org/t/p/w500" + mv.poster_path
        end if
    end if
    item.addFields({ movieId: mv.id, wide: wide, progress: progress })
end sub

sub onItemSelected()
    sel = m.rows.rowItemSelected   ' [rowIndex, itemIndex]
    if sel = invalid or sel.count() < 2 then return
    row = m.rows.content.getChild(sel[0])
    if row = invalid then return
    item = row.getChild(sel[1])
    if item = invalid then return
    playMovie(item.movieId)
end sub

' OK pressed on the featured hero -> play that movie.
sub onHeroPlay()
    id = m.hero.playMovieId
    if id <> invalid and id > 0 then playMovie(id)
end sub

sub playMovie(movieId as dynamic)
    if movieId = invalid then return
    m.status.text = "Loading…"
    m.status.visible = true
    m.detailTask = createObject("roSGNode", "HttpTask")
    m.detailTask.url = m.base + "/api/movies/" + movieId.toStr()
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
    m.audioPicked = false   ' re-pick the audio track for this movie
    vc = createObject("roSGNode", "ContentNode")
    vc.url = m.base + "/api/stream/" + file.id.toStr() + "/direct"
    vc.streamFormat = streamFormatFor(file.container)
    if title <> invalid then vc.title = title

    logmsg("play " + vc.url + " (container=" + firstStr(file.container) + " -> " + vc.streamFormat + ")")

    m.hero.suspended = true   ' stop the hero trailer so two videos don't fight

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

    pickAudio()   ' switch off TrueHD ASAP; also covers a late-arriving track list

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

' Roku reports the file's audio tracks here once it has parsed the container.
sub onAudioTracks()
    pickAudio()
end sub

' Pick the best passthrough-friendly track (EAC3/Atmos -> AC-3) and switch to it
' ONCE, as early as possible — ideally while still buffering, before any frames
' decode, so we never sit on (or mid-stream switch off) the TrueHD track. A
' mid-stream switch throws "malformed data" on Roku's MKV demuxer; switching
' before playback starts avoids it. Called from both the track-list observer and
' onVideoState so the pick can't be missed.
sub pickAudio()
    if m.audioPicked = true then return
    tracks = m.video.availableAudioTracks
    if tracks = invalid or tracks.count() = 0 then return

    best = -1
    bestScore = -1000000
    info = ""
    for i = 0 to tracks.count() - 1
        t = tracks[i]
        nm = ""
        if t.Name <> invalid then nm = t.Name
        lang = ""
        if t.Language <> invalid then lang = t.Language
        sc = scoreAudio(nm)
        info = info + " [" + i.toStr() + " '" + nm + "'/" + lang + "=" + sc.toStr() + "]"
        if sc > bestScore then
            bestScore = sc
            best = i
        end if
    end for

    ' Roku's default is track 0. If it's ALREADY passthrough-friendly, leave it
    ' be — forcing an audioTrack switch wedges/garbles some MKVs (a 4K TrueHD
    ' REMUX never reaches 'playing' after a switch). Only override a default Roku
    ' can't bitstream (TrueHD/DTS-HD) — and even then it may not take; such files
    ' belong on the native renderer.
    defName = ""
    if tracks[0].Name <> invalid then defName = tracks[0].Name
    defaultOk = scoreAudio(defName) > 0

    logmsg("audioTracks(" + tracks.count().toStr() + ")" + info + " -> pick " + best.toStr() + " defaultOk=" + defaultOk.toStr() + " state=" + m.video.state)

    if best >= 0 and bestScore > 0 and not defaultOk then
        m.video.audioTrack = tracks[best].Track
    end if
    m.audioPicked = true
end sub

' Rank an audio track by how well the Roku/Denon chain handles it, using the
' track's title. EAC3/Atmos (DD+) bitstreams to the Denon as Atmos; AC-3 as 5.1.
' TrueHD/DTS-HD can't be formed into a Roku passthrough bitstream. Commentaries
' are never auto-selected.
function scoreAudio(name as string) as integer
    u = UCase(name)
    if Instr(1, u, "COMMENT") > 0 then return -1000
    if Instr(1, u, "TRUEHD") > 0 or Instr(1, u, "TRUE-HD") > 0 or Instr(1, u, "MLP") > 0 then return -900
    if Instr(1, u, "DTS-HD") > 0 or Instr(1, u, "DTSHD") > 0 or Instr(1, u, "DTS:X") > 0 or Instr(1, u, "DTS-X") > 0 then return -800
    if Instr(1, u, "EAC3") > 0 or Instr(1, u, "E-AC3") > 0 or Instr(1, u, "E-AC-3") > 0 or Instr(1, u, "DIGITAL PLUS") > 0 or Instr(1, u, "DD+") > 0 or Instr(1, u, "DDP") > 0 or Instr(1, u, "JOC") > 0 or Instr(1, u, "ATMOS") > 0 then return 100
    if Instr(1, u, "AC3") > 0 or Instr(1, u, "AC-3") > 0 or Instr(1, u, "DOLBY DIGITAL") > 0 then return 50
    if Instr(1, u, "DTS") > 0 then return 30
    if Instr(1, u, "AAC") > 0 then return 20
    return 0
end function

sub backToRows()
    m.video.control = "stop"
    m.video.visible = false
    m.hero.suspended = false   ' resume the hero (restarts its trailer)
    ' Restore focus + rail visibility for whichever zone we launched from.
    if m.zone = "hero" then
        m.rows.visible = false   ' hero is fullscreen
        m.hero.setFocus(true)
    else
        m.rows.visible = true
        m.rows.setFocus(true)
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.video.visible then
        if key = "back" then
            backToRows()
            return true
        end if
        return false
    end if

    ' Zone switching between the hero and the rails. The hero bubbles "down"
    ' (its onKeyEvent returns false); the RowList only bubbles "up" when it's at
    ' the top row and can't move further — exactly when we want to jump to hero.
    if key = "down" and m.zone = "hero" then
        m.zone = "rows"
        m.hero.active = false   ' collapse to banner, mute, resume cycling
        m.rows.visible = true
        m.rows.setFocus(true)
        return true
    else if key = "up" and m.zone = "rows" then
        m.zone = "hero"
        m.hero.active = true    ' go fullscreen, unmute, pause cycling
        m.rows.visible = false  ' hide the rails behind the fullscreen hero
        m.hero.setFocus(true)
        return true
    end if
    return false
end function

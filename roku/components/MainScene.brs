' NASCinema main scene: load the server-composed home (carousel rails); a poster
' or the hero opens the movie page, whose Play starts the video with the
' page's version/audio/subtitle picks. The * key opens the options panel
' everywhere (switch tracks mid-movie, flag a problem). The backend decides what rails exist (Continue Watching, Popular,
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

    m.movie = m.top.findNode("movie")
    m.panel = m.top.findNode("panel")
    m.toast = m.top.findNode("toast")
    m.toastText = m.top.findNode("toastText")
    m.toastTimer = m.top.findNode("toastTimer")
    m.saveTimer = m.top.findNode("saveTimer")
    m.movie.base = m.base
    m.movie.observeField("play", "onMoviePlay")
    m.movie.observeField("wantOptions", "onMovieOptions")
    m.movie.observeField("closed", "onMovieClosed")
    m.movie.observeField("externals", "onMovieExternals")
    m.panel.observeField("changed", "onPanelChanged")
    m.panel.observeField("flag", "onPanelFlag")
    m.panel.observeField("closed", "onPanelClosed")
    m.toastTimer.observeField("fire", "onToastDone")
    m.saveTimer.observeField("fire", "onSaveTick")
    m.video.observeField("availableSubtitleTracks", "onSubTracks")
    m.screen = "home"   ' "home" | "movie" | "video"
    ' What's playing: {movieId, title, files, fileIdx, audio, subKey, externals, subSaved}.
    m.cur = invalid
    m.panelMode = ""

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
    if m.logTasks.count() > 40 then m.logTasks.shift()
end sub

function http(method as string, path as string, body as string) as object
    t = createObject("roSGNode", "HttpTask")
    t.url = m.base + path
    t.method = method
    t.body = body
    t.control = "RUN"
    m.logTasks.push(t)   ' keep a reference so it isn't collected mid-flight
    if m.logTasks.count() > 40 then m.logTasks.shift()
    return t
end function

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
    openMovie(item.movieId)
end sub

' OK pressed on the featured hero -> that movie's page.
sub onHeroPlay()
    id = m.hero.playMovieId
    if id <> invalid and id > 0 then openMovie(id)
end sub

sub openMovie(movieId as dynamic)
    if movieId = invalid then return
    m.hero.suspended = true   ' stop the hero trailer behind the page
    m.rows.visible = false
    m.movie.visible = true
    m.movie.movieId = movieId
    m.movie.setFocus(true)
    m.screen = "movie"
    logmsg("open movie " + movieId.toStr())
end sub

sub onMovieClosed()
    m.movie.visible = false
    m.screen = "home"
    m.hero.suspended = false   ' resume the hero (restarts its trailer)
    restoreHome()
end sub

' Play on the movie page: its detail + picks -> the video.
sub onMoviePlay()
    d = m.movie.detail
    c = m.movie.choice
    req = m.movie.play
    if d = invalid or c = invalid or req = invalid then return
    if d.files = invalid or d.files.count() = 0 then return
    idx = Int(c.fileIdx)
    if idx < 0 or idx >= d.files.count() then idx = 0
    ext = m.movie.externals
    if ext = invalid then ext = []
    m.cur = {
        movieId: d.id
        title: strOf(d.title)
        files: d.files
        fileIdx: idx
        audio: Int(c.audio)
        subKey: strOf(c.subKey)
        externals: ext
        subSaved: strOf(m.movie.subSaved)
    }
    pos = 0
    if req.position <> invalid then pos = req.position
    startPlayback(pos)
end sub

sub startPlayback(pos as dynamic)
    f = m.cur.files[m.cur.fileIdx]
    m.audioPicked = false   ' re-pick the audio track for this file
    vc = createObject("roSGNode", "ContentNode")
    vc.url = m.base + "/api/stream/" + f.id.toStr() + "/direct"
    vc.streamFormat = streamFormatFor(f.container)
    vc.title = m.cur.title
    if pos > 0 then vc.playStart = Int(pos)
    ' Downloaded subtitles ride along as side-loaded WebVTT tracks.
    subs = []
    for each x in m.cur.externals
        subs.push({ Language: lang3(strOf(x.lang)), TrackName: m.base + strOf(x.url), Description: strOf(x.label) + " (downloaded)" })
    end for
    if subs.count() > 0 then vc.subtitleTracks = subs

    logmsg("play " + vc.url + " at " + Int(pos).toStr() + "s (container=" + firstStr(f.container) + " -> " + vc.streamFormat + ", audio=" + m.cur.audio.toStr() + ", subs=" + m.cur.subKey + ")")

    m.hero.suspended = true   ' stop the hero trailer so two videos don't fight
    m.movie.visible = false
    m.rows.visible = false
    m.status.visible = false
    m.video.content = vc
    m.video.visible = true
    m.video.setFocus(true)
    m.video.control = "play"
    m.screen = "video"
    m.saveTimer.control = "start"
    applySubs()
end sub

' Roku wants ISO 639-2 codes on side-loaded tracks; downloads are named "en".
function lang3(l as string) as string
    map = { "en": "eng", "es": "spa", "fr": "fre", "de": "ger", "it": "ita", "pt": "por", "nl": "dut", "sv": "swe", "da": "dan", "fi": "fin", "pl": "pol", "ru": "rus", "ja": "jpn", "ko": "kor", "zh": "chi" }
    k = LCase(l)
    if map.doesExist(k) then return map[k]
    return l
end function

' Leave playback (Back, the end, or an error) for the movie page, saving where
' we got to first so its Resume button is right.
sub stopVideo(reason as string)
    m.saveTimer.control = "stop"
    saved = invalid
    if m.cur <> invalid then
        pos = m.video.position
        dur = m.video.duration
        if reason = "finished" or (dur > 0 and pos > dur * 0.95) then
            saved = putProgress(0)   ' watched to the credits: no Resume
        else if pos > 5 then
            saved = putProgress(pos)
        end if
    end if
    m.video.control = "stop"
    m.video.visible = false
    if m.movie.detail <> invalid then
        m.screen = "movie"
        m.movie.visible = true
        m.movie.setFocus(true)
        ' Re-read the resume point once the save has landed.
        if saved <> invalid then
            saved.observeField("response", "onSavedRefresh")
        else
            m.movie.refresh = true
        end if
    else
        m.screen = "home"
        m.hero.suspended = false
        restoreHome()
    end if
end sub

sub onSavedRefresh()
    m.movie.refresh = true
end sub

function putProgress(pos as dynamic) as object
    f = m.cur.files[m.cur.fileIdx]
    body = { position: pos }
    ' Keep the subtitle another app remembered for this file.
    if m.cur.subSaved <> "" then body.subtitle = m.cur.subSaved
    return http("PUT", "/api/progress/" + f.id.toStr(), FormatJson(body))
end function

sub onSaveTick()
    if m.screen <> "video" or m.cur = invalid then return
    if m.video.state <> "playing" then return
    pos = m.video.position
    if pos > 5 then putProgress(pos)
end sub

sub onSubTracks()
    applySubs()
end sub

' Turn on the picked subtitle once Roku has listed the tracks. Embedded text
' tracks map by order among the file's Roku-playable ones; downloaded ones by
' URL.
sub applySubs()
    if m.cur = invalid then return
    key = m.cur.subKey
    if key = "" or key = "off" then
        m.video.globalCaptionMode = "Off"
        return
    end if
    tracks = m.video.availableSubtitleTracks
    if tracks = invalid or tracks.count() = 0 then return
    target = ""
    if Left(key, 2) = "x:" then
        url = m.base + Mid(key, 3)
        for each t in tracks
            if strOf(t.TrackName) = url then target = url
        end for
    else if Left(key, 2) = "e:" then
        n = Mid(key, 3).toInt()
        k = -1
        cnt = 0
        f = m.cur.files[m.cur.fileIdx]
        if f.subtitle_tracks <> invalid then
            for each s in f.subtitle_tracks
                if rokuSubOk(s) then
                    if s.id = n then k = cnt
                    cnt = cnt + 1
                end if
            end for
        end if
        emb = []
        for each t in tracks
            if Left(strOf(t.TrackName), 4) <> "http" then emb.push(t)
        end for
        if k >= 0 and k < emb.count() then target = strOf(emb[k].TrackName)
    end if
    info = ""
    for each t in tracks
        info = info + " [" + strOf(t.TrackName) + "/" + strOf(t.Language) + "]"
    end for
    logmsg("subs: want " + key + " -> '" + target + "' of" + info)
    if target <> "" then
        m.video.subtitleTrack = target
        m.video.globalCaptionMode = "On"
    end if
end sub

sub onMovieOptions()
    openPanel("movie")
end sub

sub onMovieExternals()
    if m.panel.visible and m.panelMode = "movie" then m.panel.externals = m.movie.externals
end sub

' The * panel. "movie": picks for the next Play; "video": live switching;
' "home": just "Flag a problem".
sub openPanel(mode as string)
    md = { files: [], fileIdx: 0, audio: 0, subKey: "off", externals: [], allowVersion: false, flag: true }
    if mode = "movie" then
        d = m.movie.detail
        c = m.movie.choice
        if d <> invalid and c <> invalid then
            md.files = d.files
            md.fileIdx = c.fileIdx
            md.audio = c.audio
            md.subKey = c.subKey
            ext = m.movie.externals
            if ext <> invalid then md.externals = ext
            md.allowVersion = true
        end if
    else if mode = "video" and m.cur <> invalid then
        md.files = m.cur.files
        md.fileIdx = m.cur.fileIdx
        md.audio = m.cur.audio
        md.subKey = m.cur.subKey
        md.externals = m.cur.externals
        md.allowVersion = true
    end if
    m.panelMode = mode
    m.panel.model = md
    m.panel.visible = true
    m.panel.setFocus(true)
    logmsg("options panel (" + mode + ")")
end sub

sub onPanelClosed()
    m.panel.visible = false
    if m.panelMode = "movie" then
        m.movie.setFocus(true)
    else if m.panelMode = "video" and m.screen = "video" then
        m.video.setFocus(true)
    else
        restoreHome()
    end if
end sub

' A pick in the panel. On the movie page it just updates the page. During
' playback subtitles switch live; audio/version restart at the same spot (a
' mid-stream audio switch breaks Roku's MKV demuxer — "malformed data").
sub onPanelChanged()
    c = m.panel.changed
    if c = invalid then return
    if m.panelMode = "movie" then
        m.movie.choice = c
    else if m.panelMode = "video" and m.cur <> invalid then
        m.movie.choice = c   ' keep the page in step for when playback ends
        idx = Int(c.fileIdx)
        if idx <> m.cur.fileIdx or Int(c.audio) <> m.cur.audio then
            pos = m.video.position
            ' Downloaded subtitles belong to one version.
            if idx <> m.cur.fileIdx then m.cur.externals = []
            m.cur.fileIdx = idx
            m.cur.audio = Int(c.audio)
            m.cur.subKey = strOf(c.subKey)
            m.video.control = "stop"
            startPlayback(pos)
            m.panel.setFocus(true)   ' the panel stays open over the restart
        else if strOf(c.subKey) <> m.cur.subKey then
            m.cur.subKey = strOf(c.subKey)
            applySubs()
        end if
    end if
end sub

sub onPanelFlag()
    mode = m.panelMode
    m.panel.visible = false
    onPanelClosed()
    sendFlag(mode)
end sub

' Same flags list as the Windows app's View button (GET /api/flags), with
' where we were and what was playing.
sub sendFlag(mode as string)
    body = { app_version: createObject("roAppInfo").GetVersion(), platform: "roku", screen: "roku-" + mode, kind: "roku" }
    ctx = { zone: m.zone }
    if mode = "video" and m.cur <> invalid then
        f = m.cur.files[m.cur.fileIdx]
        body.movie_id = m.cur.movieId
        body.movie_title = m.cur.title
        body.media_file_id = f.id
        body.position_seconds = m.video.position
        ctx.version = strOf(f.label)
        ctx.audio = m.cur.audio
        ctx.subtitles = m.cur.subKey
        ctx.state = m.video.state
        ctx.audio_format = firstStr(m.video.audioFormat)
    else if mode = "movie" then
        d = m.movie.detail
        if d <> invalid then
            body.movie_id = d.id
            body.movie_title = strOf(d.title)
        end if
    end if
    body.context = ctx
    http("POST", "/api/flags", FormatJson(body))
    showToast("Flag sent — thanks")
    logmsg("flag sent (" + mode + ")")
end sub

sub showToast(s as string)
    m.toastText.text = s
    m.toast.visible = true
    m.toastTimer.control = "stop"
    m.toastTimer.control = "start"
end sub

sub onToastDone()
    m.toast.visible = false
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
        stopVideo("error")
        showToast("Couldn't play this version")
    else if st = "finished" then
        logmsg("video finished" + extra)
        stopVideo("finished")
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

    ' The viewer picked a track (movie page or * panel): use it. Track ids are
    ' 1-based in file order, the same order Roku lists them.
    if m.cur <> invalid then
        if m.cur.audio > 0 and m.cur.audio <= tracks.count() then
            want = m.cur.audio - 1
            logmsg("audio: viewer picked " + m.cur.audio.toStr() + " -> '" + firstStr(tracks[want].Name) + "'")
            if want > 0 then m.video.audioTrack = tracks[want].Track
            m.audioPicked = true
            return
        end if
    end if

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

' Back on the home screen: focus whichever zone we left from.
sub restoreHome()
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

    if m.screen = "video" then
        if key = "back" then
            stopVideo("back")
            return true
        else if key = "options" then
            openPanel("video")
            return true
        end if
        return false
    end if
    if m.screen = "movie" then return false   ' MovieScreen handles its own keys

    if key = "options" then
        openPanel("home")
        return true
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

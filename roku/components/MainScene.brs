' NASCinema main scene: load the library as a poster grid, play on select.

sub init()
    ' Backend base URL — the NASCinema server on the LAN (ALPINE).
    m.base = "http://192.168.0.150:8400"

    m.brand = m.top.findNode("brand")
    m.status = m.top.findNode("status")
    m.grid = m.top.findNode("grid")
    m.video = m.top.findNode("video")

    m.grid.observeField("itemSelected", "onItemSelected")
    m.video.observeField("state", "onVideoState")

    loadLibrary()
end sub

sub loadLibrary()
    m.status.text = "Loading your library…"
    m.status.visible = true
    m.libraryTask = createObject("roSGNode", "HttpTask")
    m.libraryTask.url = m.base + "/api/movies"
    m.libraryTask.observeField("response", "onLibraryLoaded")
    m.libraryTask.control = "RUN"
end sub

sub onLibraryLoaded()
    resp = m.libraryTask.response
    if resp = invalid or resp = "" then
        m.status.text = "Couldn't reach the server at " + m.base
        return
    end if

    json = ParseJson(resp)
    if json = invalid then
        m.status.text = "Bad response from the server"
        return
    end if
    if json.movies = invalid or json.movies.count() = 0 then
        m.status.text = "No movies found — run a scan"
        return
    end if

    content = createObject("roSGNode", "ContentNode")
    for each mv in json.movies
        item = content.createChild("ContentNode")
        item.title = mv.title
        if mv.poster_path <> invalid then
            if mv.poster_path <> "" then
                item.HDPOSTERURL = "https://image.tmdb.org/t/p/w500" + mv.poster_path
            end if
        end if
        item.addFields({ movieId: mv.id })
    end for

    m.grid.content = content
    m.status.visible = false
    m.grid.visible = true
    m.grid.setFocus(true)
    print "[NASCinema] loaded "; json.movies.count(); " movies"
end sub

sub onItemSelected()
    idx = m.grid.itemSelected
    item = m.grid.content.getChild(idx)
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
        return
    end if

    ' Prefer the feature file; fall back to the first.
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

    m.video.content = vc
    m.status.visible = false
    m.video.visible = true
    m.video.setFocus(true)
    m.video.control = "play"
    print "[NASCinema] play "; vc.url; " ("; vc.streamFormat; ")"
end sub

' Map the probed container to a Roku stream format.
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
    print "[NASCinema] video state: "; st
    if st = "finished" or st = "error" then
        if st = "error" then
            print "[NASCinema] video error: "; m.video.errorMsg; " code="; m.video.errorCode
        end if
        backToGrid()
    end if
end sub

sub backToGrid()
    m.video.control = "stop"
    m.video.visible = false
    m.grid.visible = true
    m.grid.setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back" and m.video.visible then
        backToGrid()
        return true
    end if
    return false
end function

' Featured hero: cycles through the backend's featured list, showing each movie's
' backdrop + clearlogo (or title) + ratings/quality, with paging dots. Auto-advances
' on a timer; Left/Right cycle manually; OK asks MainScene to play the movie.

sub init()
    m.content = m.top.findNode("content")
    m.backdrop = m.top.findNode("backdrop")
    m.trailer = m.top.findNode("trailer")
    m.scrim = m.top.findNode("scrim")
    m.logo = m.top.findNode("logo")
    m.title = m.top.findNode("title")
    m.meta = m.top.findNode("meta")
    m.dotsGroup = m.top.findNode("dots")
    m.fader = m.top.findNode("fader")
    m.timer = m.top.findNode("auto")
    m.trailerDelay = m.top.findNode("trailerDelay")
    m.fadeOut = m.top.findNode("fadeOut")
    m.fadeIn = m.top.findNode("fadeIn")
    m.timer.observeField("fire", "onTick")
    m.trailerDelay.observeField("fire", "onTrailerDelay")
    m.trailer.observeField("state", "onTrailerState")
    m.fadeOut.observeField("state", "onFadeOutDone")
    m.index = 0
    m.items = []
    m.dots = []
    m.activeState = false
    m.fadeReason = "advance"   ' "advance" (next item) or "mode" (banner<->fullscreen)

    setMode(false)   ' start collapsed (banner)
end sub

' Collapsed = the 560px banner (backdrop/trailer cropped, shifted up to keep faces).
' Fullscreen = the trailer fills the whole 1920x1080 (no crop) when the user hovers.
sub setMode(fs as boolean)
    if fs then
        m.content.clippingRect = [0, 0, 1920, 1080]
        m.backdrop.translation = [0, 0]
        m.trailer.translation = [0, 0]
        m.scrim.height = 1080
        m.fader.height = 1080
        m.logo.translation = [90, 830]
        m.meta.translation = [92, 990]
        m.dotsGroup.visible = false
    else
        m.content.clippingRect = [0, 0, 1920, 560]
        m.backdrop.translation = [0, -200]
        m.trailer.translation = [0, -200]
        m.scrim.height = 560
        m.fader.height = 560
        m.logo.translation = [90, 300]
        m.meta.translation = [92, 476]
        m.dotsGroup.visible = true
    end if
end sub

sub onFeatured()
    src = m.top.featured
    if src = invalid or src.count() = 0 then return
    ' Copy + shuffle so each launch scrolls a different order (Rnd is auto-seeded
    ' per run). A local copy avoids mutating the field's array in place.
    m.items = []
    for each it in src
        m.items.push(it)
    end for
    shuffle(m.items)

    buildDots(m.items.count())
    m.index = 0
    showItem()   ' first one shows immediately (no fade); showItem starts the timer
end sub

sub shuffle(a as object)
    for i = a.count() - 1 to 1 step -1
        j = Int(Rnd(0) * (i + 1))   ' 0..i
        tmp = a[i]
        a[i] = a[j]
        a[j] = tmp
    end for
end sub

sub showItem()
    if m.items = invalid or m.items.count() = 0 then return
    it = m.items[m.index]

    stopTrailer()   ' new item: drop any playing trailer, show its backdrop first

    bp = it.backdrop_path
    if bp <> invalid and bp <> "" then
        m.backdrop.uri = "https://image.tmdb.org/t/p/w1280" + bp
    else
        m.backdrop.uri = ""
    end if

    lg = it.logo
    if lg <> invalid and lg <> "" then
        m.logo.uri = lg
        m.logo.visible = true
        m.title.visible = false
    else
        m.logo.uri = ""
        m.logo.visible = false
        m.title.text = firstStr(it.title)
        m.title.visible = true
    end if

    m.meta.text = metaLine(it)
    updateDots()

    ' Fallback advance timer, always running per item: if NO trailer ends up
    ' playing (not cached, error), this still moves us on. A playing trailer
    ' overrides it — idle keeps the 25s cap, fullscreen stops it for full play.
    m.timer.duration = dwellSeconds()
    m.timer.control = "start"

    ' Show the backdrop for a beat, then start this item's trailer.
    if not m.top.suspended then m.trailerDelay.control = "start"
end sub

function dwellSeconds() as integer
    if m.activeState then return 15   ' fullscreen: short fallback if nothing plays
    return 25                         ' idle banner cap
end function

sub onTrailerDelay()
    playTrailer()
end sub

sub playTrailer()
    if m.top.suspended then return
    if m.items = invalid or m.items.count() = 0 then return
    it = m.items[m.index]
    if it = invalid then return
    ' Only play a trailer that's already cached on the server — never wait on a
    ' cold download (it'd hang the video). Not ready -> just show the backdrop.
    if it.trailer_ready <> true then return
    turl = it.trailer_url
    base = m.top.base
    if turl = invalid or turl = "" or base = invalid or base = "" then return

    vc = createObject("roSGNode", "ContentNode")
    vc.url = base + turl
    vc.streamFormat = "mkv"
    m.trailer.content = vc
    m.trailer.mute = not m.activeState   ' audio only when the hero is active
    ' Stay hidden (backdrop showing) until real frames flow — see onTrailerState.
    m.trailer.control = "play"
end sub

sub stopTrailer()
    m.trailerDelay.control = "stop"
    m.trailer.control = "stop"
    m.trailer.visible = false
end sub

sub onTrailerState()
    st = m.trailer.state
    if st = "playing" then
        ' Real frames now — dissolve from backdrop to video.
        m.trailer.visible = true
        if m.activeState then
            m.timer.control = "stop"    ' fullscreen: let the trailer play to the end
        else
            m.timer.duration = 25       ' idle: 25s cap, counted from playback start
            m.timer.control = "start"
        end if
    else if st = "finished" then
        advance(1)
    else if st = "error" then
        stopTrailer()   ' no trailer cached / 404 — just keep the backdrop
    end if
end sub

' Hero gained/lost focus: unmute instantly on hover (Roku can't fade volume, and a
' delay just feels wrong) and pause auto-advance while the user is watching.
sub onActiveChange()
    m.activeState = m.top.active
    if m.activeState then
        m.trailer.mute = false
        if m.trailer.state = "playing" then
            m.timer.control = "stop"    ' let the playing trailer finish (no cap)
        else
            m.timer.duration = 15       ' fullscreen fallback if nothing's playing
            m.timer.control = "start"
        end if
    else
        m.trailer.mute = true
        m.timer.duration = 25
        m.timer.control = "start"       ' idle cap resumes
    end if
    ' Smoothly fade through black into/out of fullscreen instead of snapping.
    m.fader.height = 1080          ' cover the whole screen during the transition
    m.fadeReason = "mode"
    m.fadeOut.control = "start"
end sub

' A fullscreen movie is playing — stop everything so two videos don't fight.
sub onSuspendedChange()
    if m.top.suspended then
        stopTrailer()
        m.timer.control = "stop"
    else
        m.timer.control = "start"
        showItem()   ' resume the current item (restarts its trailer)
    end if
end sub

function firstStr(v as dynamic) as string
    if v = invalid then return ""
    return v.toStr()
end function

function metaLine(it as object) as string
    parts = []
    if it.year <> invalid then parts.push(it.year.toStr())
    if it.imdb_rating <> invalid then
        parts.push("IMDb " + it.imdb_rating.toStr())
    else if it.rating <> invalid then
        parts.push(it.rating.toStr())
    end if
    if it.rt_score <> invalid then parts.push("RT " + it.rt_score.toStr() + "%")
    q = qualityTag(it)
    if q <> "" then parts.push(q)

    s = ""
    for i = 0 to parts.count() - 1
        if i > 0 then s = s + "   " + Chr(8226) + "   "
        s = s + parts[i]
    end for
    return s
end function

function qualityTag(it as object) as string
    tag = ""
    res = it.resolution
    if res <> invalid and res <> "" then
        if Instr(1, res, "3840") > 0 or Instr(1, res, "2160") > 0 then
            tag = "4K"
        else if Instr(1, res, "1920") > 0 or Instr(1, res, "1080") > 0 then
            tag = "1080p"
        end if
    end if
    if it.hdr = true then
        if tag <> "" then
            tag = tag + " HDR"
        else
            tag = "HDR"
        end if
    end if
    return tag
end function

sub buildDots(n as integer)
    while m.dotsGroup.getChildCount() > 0
        m.dotsGroup.removeChildIndex(0)
    end while
    m.dots = []
    for i = 0 to n - 1
        d = m.dotsGroup.createChild("Rectangle")
        d.width = 16
        d.height = 16
        d.translation = [i * 26, 0]
        d.color = "0x55557FFF"
        m.dots.push(d)
    end for
end sub

sub updateDots()
    if m.dots = invalid then return
    for i = 0 to m.dots.count() - 1
        if i = m.index then
            m.dots[i].color = "0xFFB020FF"
        else
            m.dots[i].color = "0x55557FFF"
        end if
    end for
end sub

sub onTick()
    advance(1)
end sub

sub advance(dir as integer)
    if m.items = invalid or m.items.count() = 0 then return
    if m.fadeOut.state = "running" then return   ' debounce overlapping advances
    m.index = (m.index + dir + m.items.count()) mod m.items.count()
    ' Fade the black overlay IN (it covers the still-playing video, which ignores
    ' opacity); onFadeOutDone then stops the trailer + swaps under the black cover,
    ' so there's no flash of the old backdrop.
    m.fadeReason = "advance"
    m.fadeOut.control = "start"
end sub

sub onFadeOutDone()
    if m.fadeOut.state = "stopped" then
        if m.fadeReason = "mode" then
            setMode(m.activeState)   ' resize banner<->fullscreen under the black
        else
            showItem()               ' swap to the next item under the black
        end if
        m.fadeIn.control = "start"
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "right" then
        advance(1)
        if not m.activeState then m.timer.control = "start"
        return true
    else if key = "left" then
        advance(-1)
        if not m.activeState then m.timer.control = "start"
        return true
    else if key = "OK" then
        if m.items <> invalid and m.items.count() > 0 then
            it = m.items[m.index]
            if it <> invalid and it.id <> invalid then m.top.playMovieId = it.id
        end if
        return true
    end if
    return false   ' up/down/back bubble up to MainScene for zone switching
end function

sub init()
    setNodes()
end sub

sub setNodes()
    if m.poster = invalid then m.poster = m.top.findNode("poster")
    if m.ph = invalid then m.ph = m.top.findNode("ph")
    if m.track = invalid then m.track = m.top.findNode("track")
    if m.fill = invalid then m.fill = m.top.findNode("fill")
    if m.label = invalid then m.label = m.top.findNode("label")
    if m.fshade = invalid then m.fshade = m.top.findNode("fshade")
    if m.flogo = invalid then m.flogo = m.top.findNode("flogo")
    if m.fname = invalid then m.fname = m.top.findNode("fname")
end sub

' Defensive: onChange can fire before init() in some cases, so re-find nodes.
sub onContentSet()
    setNodes()
    item = m.top.itemContent
    if item = invalid then return

    ' Tiles are recycled across rows: reset the franchise overlay every time.
    fr = (item.franchise <> invalid and item.franchise = true)
    m.fshade.visible = fr
    m.flogo.visible = false
    m.fname.visible = false
    if fr then
        if item.logo <> invalid and item.logo <> "" then
            m.flogo.uri = item.logo
            m.flogo.visible = true
        else
            m.flogo.uri = ""
            m.fname.text = item.name
            m.fname.visible = true
        end if
    end if

    if item.wide = true then
        ' Continue Watching card: backdrop, progress bar, one-line title.
        m.ph.width = 480
        m.ph.height = 270
        m.poster.width = 480
        m.poster.height = 270
        m.label.translation = [0, 280]
        m.label.width = 480
        m.label.height = 36
        m.label.horizAlign = "left"
        m.label.maxLines = 1
        p = 0.0
        if item.progress <> invalid then p = item.progress
        m.track.visible = not fr
        m.fill.visible = p > 0 and not fr
        m.fill.width = Int(480 * p)
    else
        m.ph.width = 200
        m.ph.height = 300
        m.poster.width = 200
        m.poster.height = 300
        m.label.translation = [0, 306]
        m.label.width = 200
        m.label.height = 44
        m.label.horizAlign = "center"
        m.label.maxLines = 2
        m.track.visible = false
        m.fill.visible = false
    end if

    if item.HDPOSTERURL <> invalid then
        if item.HDPOSTERURL <> "" then m.poster.uri = item.HDPOSTERURL
    end if
    if item.title <> invalid then m.label.text = item.title
end sub

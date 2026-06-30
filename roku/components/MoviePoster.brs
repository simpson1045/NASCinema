sub init()
    setNodes()
end sub

sub setNodes()
    if m.poster = invalid then m.poster = m.top.findNode("poster")
    if m.label = invalid then m.label = m.top.findNode("label")
end sub

' Defensive: onChange can fire before init() in some cases, so re-find nodes.
sub onContentSet()
    setNodes()
    item = m.top.itemContent
    if item = invalid then return
    if item.HDPOSTERURL <> invalid then
        if item.HDPOSTERURL <> "" then m.poster.uri = item.HDPOSTERURL
    end if
    if item.title <> invalid then m.label.text = item.title
end sub

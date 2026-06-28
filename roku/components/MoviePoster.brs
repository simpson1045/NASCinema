sub init()
    m.poster = m.top.findNode("poster")
    m.label = m.top.findNode("label")
end sub

sub onContentSet()
    item = m.top.itemContent
    if item = invalid then return
    if item.HDPOSTERURL <> invalid then
        if item.HDPOSTERURL <> "" then m.poster.uri = item.HDPOSTERURL
    end if
    m.label.text = item.title
end sub

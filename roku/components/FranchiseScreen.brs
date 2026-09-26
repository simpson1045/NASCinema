' Franchise page logic: loads /api/collections/{id} and lays out its movies as
' one poster row. The RowList handles Left/Right/OK; Back closes; * bubbles up
' to MainScene (flag).

sub init()
    m.backdrop = m.top.findNode("backdrop")
    m.logo = m.top.findNode("logo")
    m.title = m.top.findNode("title")
    m.info = m.top.findNode("info")
    m.overview = m.top.findNode("overview")
    m.list = m.top.findNode("list")
    m.status = m.top.findNode("status")
    m.list.rowItemSize = [[200, 350]]
    m.list.itemSize = [1740, 410]
    m.list.itemSpacing = [26, 30]
    m.list.showRowLabel = [false]
    m.list.observeField("rowItemSelected", "onSelected")
    ' Focus given to the page goes to its poster row.
    m.top.observeField("focusedChild", "onFocusChange")
    m.tasks = []
end sub

sub onFocusChange()
    if m.top.hasFocus() then m.list.setFocus(true)
end sub

sub onCollectionId()
    id = m.top.collectionId
    if id = invalid or id <= 0 then return
    m.backdrop.uri = ""
    m.logo.uri = ""
    m.logo.visible = false
    m.title.visible = false
    m.info.text = ""
    m.overview.text = ""
    m.list.content = createObject("roSGNode", "ContentNode")
    m.status.text = "Loading…"
    m.status.visible = true
    t = createObject("roSGNode", "HttpTask")
    t.url = m.top.base + "/api/collections/" + id.toStr()
    t.observeField("response", "onLoaded")
    t.control = "RUN"
    m.task = t
end sub

sub onLoaded()
    json = ParseJson(m.task.response)
    if json = invalid then
        m.status.text = "Couldn't load this franchise"
        return
    end if
    if json.id <> m.top.collectionId then return   ' a late reply for one we left
    m.status.visible = false

    bd = json.backdrop
    if bd <> invalid and bd <> "" then m.backdrop.uri = bd.replace("/original/", "/w1280/")
    lg = json.logo
    if lg <> invalid and lg <> "" then
        m.logo.uri = lg
        m.logo.visible = true
    else
        if json.name <> invalid then m.title.text = json.name
        m.title.visible = true
    end if

    n = 0
    if json.movies <> invalid then n = json.movies.count()
    info = n.toStr() + " movies"
    if json.years <> invalid and json.years <> "" then info = info + "  ·  " + json.years
    m.info.text = info
    if json.overview <> invalid then m.overview.text = json.overview
    centerLogo()

    root = createObject("roSGNode", "ContentNode")
    row = root.createChild("ContentNode")
    if json.movies <> invalid then
        for each mv in json.movies
            item = row.createChild("ContentNode")
            item.title = mv.title
            if mv.poster_path <> invalid and mv.poster_path <> "" then
                item.HDPOSTERURL = "https://image.tmdb.org/t/p/w500" + mv.poster_path
            end if
            item.addFields({ movieId: mv.id, wide: false, progress: 0.0, franchise: false })
        end for
    end if
    m.list.content = root
    if m.top.hasFocus() or m.top.isInFocusChain() then m.list.setFocus(true)
end sub

' The logo sits centered over the info line beneath it (house rule); neither
' moves left of the usual edge.
sub centerLogo()
    if not m.logo.visible then return
    w = m.info.boundingRect().width
    b = 520
    if w > b then b = w
    m.logo.translation = [90 + Int((b - 520) / 2), 110]
    m.info.translation = [92 + Int((b - w) / 2), 280]
end sub

sub onSelected()
    sel = m.list.rowItemSelected
    if sel = invalid or sel.count() < 2 then return
    row = m.list.content.getChild(sel[0])
    if row = invalid then return
    item = row.getChild(sel[1])
    if item = invalid then return
    m.top.openMovie = item.movieId
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then
        m.top.closed = true
        return true
    end if
    return false   ' * bubbles to MainScene
end function

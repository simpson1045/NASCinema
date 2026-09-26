' Rating-row helpers (year, content rating, IMDb, RT, quality) for the movie
' page. Every function takes the target LayoutGroup. FeaturedHero keeps its own
' copy of this logic.

sub metaBuild(g as object, it as object, quality as string)
    while g.getChildCount() > 0
        g.removeChildIndex(0)
    end while
    if it.year <> invalid then metaText(g, it.year.toStr())
    if it.certification <> invalid and it.certification <> "" then metaCert(g, it.certification)
    if it.imdb_rating <> invalid then
        ' IMDb mark is ~2:1, so render it wide, not in a square badge.
        metaRating(g, "pkg:/images/imdb.png", it.imdb_rating.toStr(), 60, 30)
    else if it.rating <> invalid then
        metaText(g, it.rating.toStr())
    end if
    if it.rt_score <> invalid then
        ' >=75 certified, 60-74 fresh, else rotten (same rule as the hero).
        img = "pkg:/images/rt_rotten1.png"
        if it.rt_score >= 75 then
            img = "pkg:/images/rt_certified1.png"
        else if it.rt_score >= 60 then
            img = "pkg:/images/rt_fresh.png"
        end if
        metaRating(g, img, it.rt_score.toStr() + "%", 32, 32)
    end if
    if quality <> "" then metaText(g, quality)
end sub

' Content rating (PG-13, R …) in an outlined badge, like the TV's ratings bug.
sub metaCert(g as object, s as string)
    h = 40
    w = Len(s) * 15 + 26
    badge = g.createChild("Group")
    outer = badge.createChild("Rectangle")
    outer.width = w
    outer.height = h
    outer.color = "0xEEF1FFFF"
    inner = badge.createChild("Rectangle")
    inner.translation = [3, 3]
    inner.width = w - 6
    inner.height = h - 6
    inner.color = "0x0A0E27FF"
    lbl = badge.createChild("Label")
    lbl.width = w
    lbl.height = h
    lbl.horizAlign = "center"
    lbl.vertAlign = "center"
    lbl.text = s
    lbl.color = "0xEEF1FFFF"
    lbl.font = "font:SmallBoldSystemFont"
end sub

sub metaText(g as object, s as string)
    lbl = g.createChild("Label")
    lbl.text = s
    lbl.color = "0xEEF1FFFF"
    lbl.font = "font:MediumBoldSystemFont"
end sub

sub metaRating(g as object, img as string, val as string, w as integer, h as integer)
    row = g.createChild("LayoutGroup")
    row.layoutDirection = "horiz"
    row.vertAlignment = "center"
    row.itemSpacings = [8]
    p = row.createChild("Poster")
    p.uri = img
    p.width = w
    p.height = h
    p.loadDisplayMode = "scaleToFit"
    lbl = row.createChild("Label")
    lbl.text = val
    lbl.color = "0xEEF1FFFF"
    lbl.font = "font:MediumBoldSystemFont"
end sub

' A LayoutGroup's width summed from its children (its own boundingRect can lag
' behind children added this frame).
function metaWidth(g as object, gap as integer) as float
    n = g.getChildCount()
    total = 0
    for i = 0 to n - 1
        nd = g.getChild(i)
        if nd.subtype() = "LayoutGroup" then
            total = total + metaWidth(nd, 8)
        else if nd.subtype() = "Poster" then
            total = total + nd.width
        else
            total = total + nd.boundingRect().width
        end if
    end for
    if n > 1 then total = total + gap * (n - 1)
    return total
end function

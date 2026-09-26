' Async HTTP off the render thread. Set `url` (+ optional `method` GET/POST/
' PUT/DELETE and `body`),
' observe `response` (body as a string; "" on failure).
sub init()
    m.top.functionName = "fetch"
end sub

sub fetch()
    ut = createObject("roUrlTransfer")
    ut.setUrl(m.top.url)
    ' HTTPS support (TMDB etc.); harmless for plain-HTTP LAN calls.
    ut.setCertificatesFile("common:/certs/ca-bundle.crt")
    ut.initClientCertificates()

    ' POST / PUT / DELETE all send the JSON body (roUrlTransfer uses the
    ' method set here for postFromString).
    if m.top.method = "POST" or m.top.method = "PUT" or m.top.method = "DELETE"
        ut.setRequest(m.top.method)
        ut.addHeader("Content-Type", "application/json")
        resp = ut.postFromString(m.top.body)
        if type(resp) = "Integer" then resp = ""   ' postFromString returns a code
    else
        ut.setRequest("GET")
        resp = ut.getToString()
    end if

    if resp = invalid then resp = ""
    m.top.response = resp
end sub

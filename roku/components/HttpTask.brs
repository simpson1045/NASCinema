' Async HTTP off the render thread. Set `url` (+ optional `method`/`body`),
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

    if m.top.method = "POST"
        ut.setRequest("POST")
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

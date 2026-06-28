' Async HTTP GET off the render thread. Set `url`, observe `response` (the body
' as a string; "" on failure).
sub init()
    m.top.functionName = "fetch"
end sub

sub fetch()
    ut = createObject("roUrlTransfer")
    ut.setUrl(m.top.url)
    ut.setRequest("GET")
    ' HTTPS support (TMDB etc.); harmless for plain-HTTP LAN calls.
    ut.setCertificatesFile("common:/certs/ca-bundle.crt")
    ut.initClientCertificates()
    resp = ut.getToString()
    if resp = invalid then resp = ""
    m.top.response = resp
end sub

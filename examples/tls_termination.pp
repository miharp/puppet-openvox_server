# Behind a reverse proxy on the same host that terminates TLS on 8140 and
# passes the client certificate in headers; the server listens on plain HTTP
# on 127.0.0.1:8141. The proxy itself is not managed here.
class { 'openvox_server':
  tls_termination => true,
}

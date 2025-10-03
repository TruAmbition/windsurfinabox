docker exec -u 0:0 -it windsurf bash -lc '
  mkdir -p /root/.vnc
'
# VNC server (passwordless for speed; swap -nopw with -passwdfile /root/.vnc/passwd if you want a pw)
docker exec -d windsurf bash -lc 'x11vnc -display :1 -nopw -forever -shared -rfbport 5901'

# noVNC websocket wrapper (serves a browser client)
docker exec -d windsurf bash -lc 'websockify --web=/usr/share/novnc 6080 localhost:5901'
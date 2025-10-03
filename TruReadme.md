docker run -it --name windsurf \
  --user "$(id -u):$(id -g)" \
  -e WINDSURF_TOKEN="$WINDSURF_TOKEN" \
  -e XDG_CONFIG_HOME=/config \
  -e HOME=/workspace \
  -e WORKSPACE_DIR=/workspace \
  -e PROJECT_NAME=tru-r3f-cube \
  -e LIBGL_ALWAYS_SOFTWARE=1 \
  -e MESA_LOADER_DRIVER_OVERRIDE=llvmpipe \
  -e ELECTRON_DISABLE_GPU=1 \
  -v windsurf_config:/config \
  -v ~/windsurf-workspace:/workspace \
  -p 6080:6080 \
  -p 5901:5901 \
  --shm-size=2g \
  windsurf


docker exec -u 0:0 -it windsurf bash -lc '
  mkdir -p /root/.vnc
'
# VNC server (passwordless for speed; swap -nopw with -passwdfile /root/.vnc/passwd if you want a pw)
docker exec -d windsurf bash -lc 'x11vnc -display :1 -nopw -forever -shared -rfbport 5901'

# noVNC websocket wrapper (serves a browser client)
docker exec -d windsurf bash -lc 'websockify --web=/usr/share/novnc 6080 localhost:5901'
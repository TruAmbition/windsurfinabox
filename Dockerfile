FROM ubuntu:latest
# Install Ubuntu repository dependencies
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && \
    apt install -y xvfb xdotool gpg curl imagemagick x11-apps i3

#TO DEBUG: REMOVE
RUN apt install -y xterm

# Install Windsurf
RUN curl -fsSL "https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/windsurf.gpg" | \
    gpg --dearmor -o /usr/share/keyrings/windsurf-stable-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/windsurf-stable-archive-keyring.gpg arch=amd64] \
    https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/apt stable main" | \
    tee /etc/apt/sources.list.d/windsurf.list > /dev/null
RUN apt update
RUN apt install -y windsurf
# Node 20.x + git + helpers used by the script
RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg git x11-utils xclip && \
    install -d -m 0755 /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y nodejs && \
    node -v && npm -v

RUN apt-get install -y x11vnc novnc websockify
# Cleanup packages installation artifacts
RUN apt clean && \
    rm -rf /var/lib/apt/lists/*

# Prepare and configure entrypoint
COPY src/scripts/entrypoint.sh /entrypoint.sh
RUN chmod ugo+x /entrypoint.sh


# General configuration
USER ubuntu:ubuntu
RUN mkdir /home/ubuntu/workspace
RUN chmod ugo+rwx -R /home/ubuntu/workspace
RUN chown ubuntu:ubuntu -R /home/ubuntu/workspace


# Prepare resource files
# Copy workflow file into baked resources dir
COPY entry-workflow.md /usr/local/share/windsurf/entry-workflow.md

# Make sure it's world-readable

#RUN mkdir -p /home/ubuntu/.config/Windsurf/User/globalStorage
#COPY --chown=ubuntu:ubuntu src/config/state.vscdb /home/ubuntu/.config/Windsurf/User/globalStorage/state.vscdb
RUN mkdir -p /home/ubuntu/.config/i3
COPY --chown=ubuntu:ubuntu src/config/i3.conf /home/ubuntu/.config/i3/config

USER root
RUN chmod 644 /usr/local/share/windsurf/entry-workflow.md

COPY --chown=ubuntu src/workflows/entry-workflow.md /home/ubuntu/entry-workflow.md
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
USER ubuntu

CMD ["/entrypoint.sh"]

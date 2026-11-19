# Servidor dedicado de Project Zomboid (Build 42) - gerenciado pelo Ansible
# (role gs_zomboid). O servidor em si NÃO fica na imagem: é baixado pelo
# steamcmd para um volume persistente (/opt/pzserver) no entrypoint.
FROM ubuntu:24.04

# UID/GID do usuário "games" do host, para o container gravar nos volumes
# com o mesmo dono (passados pelo compose).
ARG PUID=1000
ARG PGID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    HOME=/home/pzserver

# steamcmd oficial do Ubuntu: pacote i386 do componente multiverse. A
# licença do Steam é aceita via debconf para a instalação não ser interativa.
RUN set -eux; \
    dpkg --add-architecture i386; \
    sed -i -E 's/^Components: .*/Components: main restricted universe multiverse/' \
        /etc/apt/sources.list.d/ubuntu.sources; \
    echo 'steam steam/question select I AGREE' | debconf-set-selections; \
    echo 'steam steam/license note ""' | debconf-set-selections; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates lib32gcc-s1 steamcmd; \
    rm -rf /var/lib/apt/lists/*

# Usuário não-root com o UID/GID do host. O UID do "games" (5) já existe na
# imagem (e o 1000 é o "ubuntu"). Esse usuário é removido antes: o Java pega o
# user.home do /etc/passwd pelo UID (não do $HOME), e com dois usuários no
# mesmo UID valia o primeiro (/usr/games), quebrando o ~/Zomboid.
RUN set -eux; \
    olduser="$(getent passwd "${PUID}" | cut -d: -f1)"; \
    if [ -n "${olduser}" ]; then userdel "${olduser}"; fi; \
    getent group "${PGID}" >/dev/null || groupadd -g "${PGID}" pzserver; \
    useradd -u "${PUID}" -g "${PGID}" -m -d /home/pzserver -s /usr/sbin/nologin pzserver; \
    mkdir -p /opt/pzserver /state /config /home/pzserver/Zomboid; \
    chown -R "${PUID}:${PGID}" /opt/pzserver /state /home/pzserver

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER ${PUID}:${PGID}
WORKDIR /home/pzserver

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

FROM fedora:39 as build

RUN dnf install gcc xz git libsodium -y

WORKDIR /app

ADD ./ /app

RUN curl https://nim-lang.org/choosenim/init.sh -sSf -o init.sh \ 
    && chmod +x init.sh \
    && sh init.sh -y \
    && echo "export PATH=/root/.nimble/bin:$PATH" >> /root/.bashrc

RUN source /root/.bashrc \ 
    && cd / && git clone https://github.com/jaar23/octolog.git \
    && cd /octolog && nimble install --verbose \
    && nimble install uuid4 -y --verbose \
    && cd /app && nimble build -d:release --threads:on --verbose 

FROM fedora:39

RUN useradd -m -u 1001 nim \
    && mkdir -p /home/nim/app \
    && chown nim /home/nim/app \
    && dnf install libsodium -y

WORKDIR /home/nim/app

COPY --from=build /app/octoque /home/nim/octoque

ENTRYPOINT ["/home/nim/octoque", "run"]

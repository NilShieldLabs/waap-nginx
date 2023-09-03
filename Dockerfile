FROM rust:1-slim-buster as builder1

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV APP_ROOT="/code/modsec-pro-rs"
RUN mkdir -p $APP_ROOT

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN cat /etc/apt/sources.list

RUN apt-get update -y

WORKDIR $APP_ROOT

COPY modsec-pro-rs $APP_ROOT

RUN ls -lhrt $APP_ROOT

RUN apt-get install -y --no-install-recommends locales openssl libssl-dev uuid-dev zlib1g-dev

RUN cargo build -r

RUN ls -lhrt $APP_ROOT/target/release/

RUN mkdir -p /usr/local/modsecurity/lib

RUN cp -rf $APP_ROOT/include /usr/local/modsecurity/
RUN cp -rf $APP_ROOT/target/release/libmodsecurity.so /usr/local/modsecurity/lib/

# clean cache
RUN cargo clean && rm -rf /var/lib/apt/lists/* && rm -rf /var/cache/apt/archives

RUN echo "modsec-pro-rs module build finished!!!\n\n"


FROM debian:buster-slim as builder2

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV APP_ROOT="/code/waap-nginx"
RUN mkdir -p $APP_ROOT

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update -y

RUN apt-get install -y build-essential python3 gcc g++ libxslt1-dev libxml2-dev libgd-dev libgeoip-dev patchelf patch sed gawk autoconf automake libtool libyajl-dev libyajl2

COPY --from=builder1 /usr/local/modsecurity /usr/local/modsecurity

WORKDIR $APP_ROOT

COPY . $APP_ROOT

RUN bash build_waap_linux.sh

RUN ls -lh $APP_ROOT/waap/

RUN echo "waap finished!!!\n\n"



# 下面是构建最小化的镜像，从上面的builder镜像中复制文件
FROM debian:buster-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update -y

RUN apt-get install -y libxslt1-dev libxml2-dev libgd-dev libgeoip-dev

RUN mkdir -p /logs/nginx && mkdir -p /opt/ngx-temp

COPY --from=builder2 /code/waap-nginx/waap /opt/waap
COPY --from=builder2 /code/waap-nginx/LICENSE /opt/waap/LICENSE
COPY --from=builder2 /code/waap-nginx/LICENSES.txt /opt/waap/LICENSES.txt

EXPOSE 80
EXPOSE 443
EXPOSE 8080
WORKDIR /opt/waap

CMD ["/opt/waap/nginx", "-g",  "daemon off;"]

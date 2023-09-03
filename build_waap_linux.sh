#!/usr/bin/env bash

unalias -a
set -xe

id
if [ -f /etc/os-release ]; then
  source /etc/os-release
fi

APP_ROOT=$(dirname "$(realpath "$0")")
echo "APP_ROOT: ${APP_ROOT}"

Sudo=""
if [ -f /usr/bin/sudo ]; then
  Sudo=sudo
fi
if [ -f /.dockerenv ]; then
  Sudo=""
fi

NGX_ROOT="$APP_ROOT/openresty-1.21.4.2"
MODULE_DIR="$APP_ROOT/modules"
DEPS_DIR="$APP_ROOT/deps"

NGX_INST="/opt/waap"

function do_prepare() {
  cd "$DEPS_DIR" || exit

  build_patched_openssl

  build_mini_librdkafka

  build_mini_libjansson

  build_lib_maxmind_db
}

function build_patched_openssl() {
  cd "$DEPS_DIR/openssl" || exit

  if [ -f "/usr/local/openssl/lib/libssl.so" ]; then
    # have been installed
    return
  fi

  ./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl
  make -j 4 || exit
  $Sudo make install

  # Update System Path
  # $Sudo echo "/usr/local/openssl/lib" >/etc/ld.so.conf.d/openssl.conf
  # $Sudo ldconfig
}

function build_mini_librdkafka() {
  if [ -f "/usr/local/lib/librdkafka.so" ]; then
    return
  fi

  cd "$DEPS_DIR/librdkafka" || exit
  ./configure --disable-zstd --disable-gssapi --disable-sasl --disable-curl \
    --disable-lz4-ext --disable-lz4 --enable-static --enable-shared
  make -j4 && $Sudo make install
}

function build_mini_libjansson() {
  if [ -f "/usr/local/lib/libjansson.a" ]; then
    return
  fi

  cd "$DEPS_DIR/jansson" || exit
  autoreconf -i
  ./configure --enable-shared=false
  make -j4 && $Sudo make install
}

# $LIB_MAXMINDDB
function build_lib_maxmind_db() {
  if [ -f "/usr/local/lib/libmaxminddb.a" ]; then
    return
  fi
  cd "$DEPS_DIR/libmaxminddb" || exit
  autoreconf -i
  ./configure --enable-static --enable-shared=false
  make -j4 && $Sudo make install
}

function install_dep() {
  echo "id: $ID"
  case $ID in
  debian | ubuntu)
    $Sudo apt-get update -y
    $Sudo apt-get install -y build-essential python3 gcc g++ libxslt1-dev libxml2-dev libgd-dev libgeoip-dev patchelf patch sed gawk autoconf automake libtool libyajl-dev libyajl2
    ;;
  centos | rhel)
    # $Sudo yum groupinstall -y 'Development Tools'
    $Sudo yum install -y epel-release centos-release-scl-rh python3 make which libxslt-devel GeoIP-devel libxml2-devel libgcrypt-devel gd-devel perl-ExtUtils-Embed
    $Sudo yum install -y patchelf patch sudo autoconf libtool
    $Sudo yum install -y devtoolset-10-gcc devtoolset-10-gcc-c++ devtoolset-10-elfutils
    $Sudo source /opt/rh/devtoolset-10/enable
    ;;
  *)
    echo "TODO: unsupported system platform"
    exit 1
    ;;
  esac
}

function ngx_configure_linux() {
  cd "$NGX_ROOT" || exit
  sed -i 's#prefix/nginx#prefix#g' configure

  export LD_LIBRARY_PATH=/usr/local/openssl/lib:$LD_LIBRARY_PATH

  ./configure --prefix="$NGX_INST" \
    --sbin-path="$NGX_INST/bin/nginx" \
    --conf-path="$NGX_INST/conf/nginx.conf" \
    --modules-path="$NGX_INST/modules" \
    --http-log-path=/opt/ngx-temp/log_access.log \
    --error-log-path=/opt/ngx-temp/log_error.log \
    --lock-path=/opt/ngx-temp/nginx.lock \
    --pid-path=/opt/ngx-temp/nginx.pid \
    --http-client-body-temp-path=/opt/ngx-temp/nginx_temp_body \
    --http-fastcgi-temp-path=/opt/ngx-temp/nginx_temp_fastcgi \
    --http-proxy-temp-path=/opt/ngx-temp/nginx_temp_proxy \
    --http-scgi-temp-path=/opt/ngx-temp/nginx_temp_scgi \
    --http-uwsgi-temp-path=/opt/ngx-temp/nginx_temp_uwsgi \
    --with-ld-opt="-L/usr/local/openssl/lib -static-libgcc" \
    --with-cc-opt="-I/usr/local/openssl/include" \
    --with-file-aio \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-http_auth_request_module \
    --with-http_v2_module \
    --with-http_dav_module \
    --with-http_slice_module \
    --with-http_addition_module \
    --with-http_geoip_module=dynamic \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_sub_module \
    --with-http_image_filter_module=dynamic \
    --with-http_xslt_module=dynamic \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-mail=dynamic \
    --with-mail_ssl_module \
    --with-threads \
    --with-compat \
    --with-pcre-jit \
    --with-pcre="$DEPS_DIR/pcre-8.45" \
    --add-module="$MODULE_DIR/nginx-module-vts" \
    --add-module="$MODULE_DIR/nginx-module-stream-sts" \
    --add-module="$MODULE_DIR/nginx-module-sts" \
    --add-module="$MODULE_DIR/nginx-stream-upsync-module" \
    --add-module="$MODULE_DIR/nginx-upsync-module" \
    --add-module="$MODULE_DIR/ngx_dynamic_upstream" \
    --add-module="$MODULE_DIR/ngx_http_geoip2_module" \
    --add-module="$MODULE_DIR/nginx-ssl-ja3" \
    --add-module="$MODULE_DIR/nginx-sticky-module-ng" \
    --add-module="$MODULE_DIR/nginx-json-log" \
    --add-module="$MODULE_DIR/ModSecurity-nginx" \
    --add-dynamic-module="$MODULE_DIR/njs/nginx" \
    $@
}

function clean_build() {
  cd "$NGX_ROOT" || exit
  make clean || true
}

function build_nginx() {
  cd "$NGX_ROOT" || exit
  time make -j7
}

# make install
function waap_install() {
  cd "$NGX_ROOT" || exit
  rm -rf /tmp"$NGX_INST"

  DESTDIR=/tmp make install

  rm -rf "$APP_ROOT"/waap || true
  mv /tmp"$NGX_INST" "$APP_ROOT"/waap
  cd "$APP_ROOT/waap" || exit

  rm -rf nginx || true
  rm -f bin/openresty || true
  mv bin/nginx nginx
  mkdir lib
  mv luajit/bin/luajit-2.1.0-beta3 bin/

  mv luajit/lib/libluajit-5.1.so.2.1.0 lib/libluajit-5.1.so.2
  # patchelf
  readelf -d nginx
  patchelf --force-rpath --set-rpath "\$ORIGIN/lib" nginx

  deps="$(ldd nginx modules/*.so)"
  files=$(echo "$deps" | python3 -c 'import re; import sys; files=set(re.findall(r"/lib64/(lib(?:e?xslt|gd|GeoIP).so\S+)", sys.stdin.read())); [print(x) for x in files]')
  echo "$files" | xargs -I{} cp -f /lib64/{} lib/{}

  cp -f /usr/local/openssl/lib/libssl.so.1.1 lib/
  cp -f /usr/local/openssl/lib/libcrypto.so.1.1 lib/
  cp -f /usr/local/lib/librdkafka.so.1 lib/
  cp -f /usr/local/modsecurity/lib/libmodsecurity.so lib/

  # strip : Release with DebugInfo
  # strip -s "$APP_ROOT"/openresty/nginx/nginx
  # strip -s "$APP_ROOT"/openresty/nginx/modules/*.so

  rm -rf luajit
}

function do_configure() {
  # linux
  if [ "$BUILD_DEBUG" ]; then
    ngx_configure_linux --with-debug
  else
    ngx_configure_linux -j7
  fi
}

clean_build

install_dep

do_prepare

do_configure

build_nginx

waap_install

cd "$APP_ROOT" || exit

if [ "$CLEAN_CACHE" ]; then
  clean_build
fi

echo "build nginx success!!!"
echo

#!/usr/bin/env bash

shopt -s extglob

name=ruby

msg() {
    echo -e "\033[1;32m-->\033[0m $0:" $*
}

die() {
    msg $*
    exit 1
}

move_to_approot() {
    [ -n "$SERVICE_APPROOT" ] && cd $SERVICE_APPROOT
}

upgrade_rvm() {
    msg "upgrading rvm"

    rvm get latest
    rvm reload

    . "/usr/local/rvm/scripts/rvm"
}

install_ruby() {
    local ruby_version=$SERVICE_CONFIG_RUBY_VERSION

    if [ -n $ruby_version ] ; then
        msg "installing ruby $ruby_version"

        rvm install $ruby_version
        rvm use $ruby_version --default
    fi
}

install_nginx_passenger() {
    local passenger_url="http://rubyforge.org/frs/download.php/75548/passenger-3.0.11.tar.gz"
    local passenger_install_dir="$HOME/data/passenger"
    local nginx_install_dir="$HOME/data/nginx"

    # install nginx/passenger requirements
    if [ ! -d $passenger_install_dir ] ; then
        msg "fetch and installing Nginx/Passenger"

        mkdir -p $passenger_install_dir
        wget -O - $passenger_url | tar -C $passenger_install_dir --strip-components=1 -zxf -
        [ $? -eq 0 ] || die "can't fetch Passenger"

        msg "installing rack"
        gem install --no-ri --no-rdoc rack
    else
        msg "Passenger already installed"
    fi

    # install nginx
    if [ ! -d $nginx_install_dir ] ; then
        mkdir -p $nginx_install_dir

        export CFLAGS="-O3 -pipe"
        $passenger_install_dir/bin/passenger-install-nginx-module   \
            --auto                                                  \
            --prefix=$nginx_install_dir                             \
            --auto-download                                         \
            --extra-configure-flags=" \
            --with-http_addition_module \
            --with-http_dav_module \
            --with-http_geoip_module \
            --with-http_gzip_static_module \
            --with-http_realip_module \
            --with-http_stub_status_module \
            --with-http_ssl_module \
            --with-http_sub_module \
            --with-http_xslt_module \
            --with-ipv6 \
            --with-sha1=/usr/include/openssl \
            --with-md5=/usr/include/openssl"
        [ $? -eq 0 ] || die "Nginx install failed"

        rm $nginx_install_dir/conf/*.default
    else
        msg "Nginx already installed"
    fi

    # update nginx configuration file
    # XXX: PORT_WWW is missing in the environment at build time
    sed > $nginx_install_dir/conf/nginx.conf < nginx.conf.in    \
        -e "s/@PORT_WWW@/${PORT_WWW:-42800}/g"                  \
        -e "s/@RACK_ENV@/${SERVICE_CONFIG_RACK_ENV:-production}/g"
}

install_gems() {
    gem install --no-ri --no-rdoc bundler
    bundle install
}

install_application() {
    mv profile ~/
    # Use ~/code and ~/current like the regular Ruby service for better compatibility
    msg "installing application to ~/current/"
    rsync -aH --delete --exclude "data" * ~/current/
}

env

move_to_approot
upgrade_rvm
install_ruby
install_nginx_passenger # could be replaced by something else
install_gems
install_application

#!/bin/sh

nginx_rtmp_repo="https://github.com/arut/nginx-rtmp-module"

#workdir="$(dirname $(readlink -f "$0"))"
me="$(readlink -f "$0")"
basedir="$(realpath .)"
srcdir="${basedir}/src"
builddir="${basedir}/build/dpkg"
ngxdebsrcdir="${srcdir}/nginx-dpkg"
ngxrtmpsrcdir="${srcdir}/$(basename ${nginx_rtmp_repo} .git)"

check_pkg() {
    dpkg -l | cut -d' ' -f3 |  grep -P "^${1}(:\\w+)?$" > /dev/null
    return $?
}

nginx_rtmp_diff() {
    l="$(grep -n '^__nginx-rtmp.diff__$' "$me" | cut -d: -f1)"
    tail -n +$(( 1 + l )) "$me"
}

echo "=> Using current dir ($workdir) as base dir"

# directory checking
for dir in "${srcdir}" "${ngxdebsrcdir}" "${builddir}"; do
    mkdir -p "${dir}" 2> /dev/null
    if [ ! -w "${dir}" ]; then
       echo "\nerror: Cannot write in ${dir}\n" >&2
       exit 1
    fi
done

# Package checking
for package in git dpkg-dev devscripts build-essential; do
    echo -n "=> Cheking for package ${package}..."

    if check_pkg "${package}"; then
        echo " found"
    else
        echo ""
        echo -n "==> Installing ${package}\n"
        apt-get install -y ${package}
        echo -n "\n==> Installation complete"
    fi        
done


# Get nginx RTMP source
echo "=> Getting nginx-rtmp source"
if [ -d "${ngxrtmpsrcdir}" ]; then
    echo "==> NOTICE: The directory of the repo (${ngxrtmpsrcdir}) exists, leave it untouched"
else
    cd ${srcdir} 
    echo "==> Cloning nginx-rtmp repo from ${nginx_tmp_repo}\n"
    git clone "${nginx_rtmp_repo}" 
    echo "\n==> Clone complete"
fi


# Get nginx deb source
echo "=> Getting nginx source"
echo "==> Installing development libraries\n"

apt-get -y build-dep nginx
echo "\n==> Install complete"

echo "==> Cleaning old source directories"
find "${ngxdebsrcdir}" -mindepth 1 -maxdepth 1 -type d -name 'nginx-*' -exec rm -rf '{}' \; 2> /dev/null

echo "==> Downloading source"
cd "${ngxdebsrcdir}"
apt-get -y source nginx

echo "\n==> Download complete" 

workdir="$(find "${ngxdebsrcdir}" -mindepth 1 -maxdepth 1 -type d -name 'nginx-*')"
cd "${workdir}"

echo "==> Patching source\n"
nginx_rtmp_diff | patch -p1
ln -vs "${ngxrtmpsrcdir}" "${workdir}/debian/modules"
echo "\n==> Patching complete"

echo "==> Building source"
debuild -us -uc -rfakeroot
echo "\n==> Build complete"


echo "==> Moving debs"
mv -v "${ngxdebsrcdir}"/*.deb "${builddir}"
echo "==> Move 0complete"

echo "=> Packages now are in ${builddir}"
exit 0

__nginx-rtmp.diff__
diff -Naur a/debian/conf/nginx.conf b/debian/conf/nginx.conf
--- a/debian/conf/nginx.conf	2016-04-26 14:51:14.000000000 +0000
+++ b/debian/conf/nginx.conf	2016-08-25 15:55:40.865183631 +0000
@@ -62,6 +62,29 @@
 	include /etc/nginx/sites-enabled/*;
 }

+##
+# RTMP multi worker settings (disable if you use a single worker)
+##
+ 
+rtmp_auto_push on;
+rtmp_auto_push_reconnect 500ms;
+rtmp_socket_dir /tmp;
+
+rtmp {
+    server {
+        listen 1935;
+
+        ##
+        # Fine tuning settings
+        ##
+
+        # chunk_size 8192;
+        # max_message 1M;     
+        # buflen 3000ms;  
+        
+        include rtmp-apps-enabled/*;
+    }
+}
 
 #mail {
 #	# See sample authentication script at:
diff -Naur a/debian/conf/rtmp-apps-available/default b/debian/conf/rtmp-apps-available/default
--- a/debian/conf/rtmp-apps-available/default	1970-01-01 00:00:00.000000000 +0000
+++ b/debian/conf/rtmp-apps-available/default	2016-08-25 15:56:11.276756681 +0000
@@ -0,0 +1,8 @@
+application live {
+    live on;
+
+    # sample HLS
+    #hls on;
+    #hls_path /tmp/hls;
+    #hls_sync 100ms;
+}
diff -Naur a/debian/conf/sites-available/rtmp b/debian/conf/sites-available/rtmp
--- a/debian/conf/sites-available/rtmp	1970-01-01 00:00:00.000000000 +0000
+++ b/debian/conf/sites-available/rtmp	2016-08-25 15:45:25.476972827 +0000
@@ -0,0 +1,40 @@
+server {
+    listen       8080;
+    server_name  localhost;
+
+    # sample handlers
+    #location /on_play {
+    #    if ($arg_pageUrl ~* localhost) {
+    #        return 201;
+    #    }
+    #    return 202;
+    #}
+    #location /on_publish {
+    #    return 201;
+    #}
+
+    #location /vod {
+    #    alias /var/myvideos;
+    #}
+
+    # rtmp stat
+    location /stat {
+        rtmp_stat all;
+        rtmp_stat_stylesheet stat.xsl;
+    }
+
+    location /stat.xsl {
+        # you can move stat.xsl to a different location
+        root /usr/share/nginx/rtmp;
+    }
+
+    # rtmp control
+    location /control {
+        rtmp_control all;
+    }
+
+    error_page   500 502 503 504  /50x.html;
+    location = /50x.html {
+        root   html;
+    }
+}
diff -Naur a/debian/nginx-common.dirs b/debian/nginx-common.dirs
--- a/debian/nginx-common.dirs	2016-04-26 14:51:14.000000000 +0000
+++ b/debian/nginx-common.dirs	2016-08-25 15:45:45.166267144 +0000
@@ -1,6 +1,8 @@
 etc/nginx
 etc/nginx/sites-available
 etc/nginx/sites-enabled
+etc/nginx/rtmp-apps-available
+etc/nginx/rtmp-apps-enabled
 etc/nginx/conf.d
 etc/ufw/applications.d
 usr/share/nginx

diff -Naur a/debian/nginx-common.install b/debian/nginx-common.install
--- a/debian/nginx-common.install	2016-04-26 14:51:14.000000000 +0000
+++ b/debian/nginx-common.install	2016-08-25 15:45:45.166267144 +0000
@@ -2,5 +2,6 @@
 debian/ufw/nginx etc/ufw/applications.d
 debian/apport/source_nginx.py usr/share/apport/package-hooks
 html/index.html usr/share/nginx/html/
+debian/modules/nginx-rtmp-module/stat.xsl usr/share/nginx/rtmp/
 debian/vim/nginx.yaml usr/share/vim/registry
 contrib/vim/* usr/share/vim/addons
diff -Naur a/debian/nginx-common.postinst b/debian/nginx-common.postinst
--- a/debian/nginx-common.postinst	2016-04-26 14:51:14.000000000 +0000
+++ b/debian/nginx-common.postinst	2016-08-25 15:56:56.698093439 +0000
@@ -30,6 +30,12 @@
     if [ -z $2 ] && [ ! -e /etc/nginx/sites-enabled/default ] &&
        [ -d /etc/nginx/sites-enabled ] && [ -d /etc/nginx/sites-available ]; then
       ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
+      ln -s /etc/nginx/sites-available/rtmp /etc/nginx/sites-enabled/rtmp
+    fi
+
+    if [ -z $2 ] && [ ! -e /etc/nginx/rtmp-apps-enabled/default ] &&
+       [ -d /etc/nginx/rtmp-apps-enabled ] && [ -d /etc/nginx/rtmp-apps-available ]; then
+      ln -s /etc/nginx/rtmp-apps-available/default /etc/nginx/rtmp-apps-enabled/default
     fi
 
     # Create a default index page when not already present.
diff -Naur a/debian/rules b/debian/rules
--- a/debian/rules	2016-04-26 14:51:14.000000000 +0000
+++ b/debian/rules	2016-08-25 15:31:48.749395292 +0000
@@ -47,7 +47,8 @@
 			--with-http_ssl_module \
 			--with-http_stub_status_module \
 			--with-http_realip_module \
-			--with-http_auth_request_module
+			--with-http_auth_request_module \
+			--add-module=$(MODULESDIR)/nginx-rtmp-module
 
 core_configure_flags := \
                         $(common_configure_flags) \
diff -Naur a/debian/source/include-binaries b/debian/source/include-binaries
--- a/debian/source/include-binaries	1970-01-01 00:00:00.000000000 +0000
+++ b/debian/source/include-binaries	2016-08-25 15:31:48.749879344 +0000
@@ -0,0 +1,6 @@
+debian/modules/nginx-rtmp-module/test/rtmp-publisher/RtmpPlayer.swf
+debian/modules/nginx-rtmp-module/test/rtmp-publisher/RtmpPublisher.swf
+debian/modules/nginx-rtmp-module/test/rtmp-publisher/RtmpPlayerLight.swf
+debian/modules/nginx-rtmp-module/test/www/bg.jpg
+debian/modules/nginx-rtmp-module/test/www/jwplayer_old/player.swf
+debian/modules/nginx-rtmp-module/test/www/jwplayer/jwplayer.flash.swf

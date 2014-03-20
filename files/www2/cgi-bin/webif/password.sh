#!/usr/bin/webif-page
<? 
. /usr/lib/webif/webif.sh

if ! empty "$FORM_submit" ; then
	SAVED=1
	validate <<EOF
string|FORM_pw1|@TR<<Password>>|required min=5|$FORM_pw1
EOF
	equal "$FORM_pw1" "$FORM_pw2" || {
		[ -n "$ERROR" ] && ERROR="${ERROR}<br />"
		ERROR="${ERROR}@TR<<两次输入密码不匹配>><br />"
	}
	if [ "$REMOTE_USER" = "root" -o "$REMOTE_USER" = "admin" ]; then
		empty "$ERROR" && {
			RES=$(
				(
					echo "$FORM_pw1"
					sleep 1
					echo "$FORM_pw2"
				) | passwd root 2>&1
			)
			equal "$?" 0 || ERROR="<pre>$RES</pre>"
		}
	else
		exists /tmp/.webif/file-httpd.conf && HTTPD_CONFIG_FILE=/tmp/.webif/file-httpd.conf || HTTPD_CONFIG_FILE=/etc/httpd.conf
		empty "$ERROR" && {
			cat $HTTPD_CONFIG_FILE | awk '
BEGIN {
	FS=":"
	system("/bin/rm /tmp/.webif/file-httpd.conf; mkdir /tmp/.webif/; touch /tmp/.webif/file-httpd.conf");
}
($1 != "") {
	if (($1 == "/cgi-bin/webif/") && (ENVIRON["REMOTE_USER"] != $2)) {
		print $1":"$2":"$3 >> "/tmp/.webif/file-httpd.conf"
	}
	if ($1 != "/cgi-bin/webif/") {
		print $1":"$2 >> "/tmp/.webif/file-httpd.conf"
	}
	if (ENVIRON["REMOTE_USER"] == $2) {
		("uhttpd -m " ENVIRON["FORM_pw1"]) | getline password
		print $1":"$2":"password >> "/tmp/.webif/file-httpd.conf"
	}
}'
	}
	fi
fi

wifisong_header "System" "Password" "@TR<<>>" '' "$SCRIPT_NAME"

cat <<EOF
<div id="page">
	<div id="header">
		<h1 class="logo"><a href="info.sh">路由器设置</a></h1>
	</div>
	<div id="main">
		<div class="main-border clearfix">
			<div class="main-aside">
				<ul class="sidenav">
					<li><a href="info.sh">网络设置</a></li>
					<li><a href="password.sh" class="active">修改密码</a></li>
					<li><a href="reboot.sh">重启路由器</a></li>
				</ul>
				<span class="sidelogo"></span>
			</div>
			<div class="main-body">
				<div class="col-box">
					<h4 class="col-title">修改密码</h4>
					<div class="col-bd">
EOF

display_form <<EOF
start_form|@TR<<>>
field|@TR<<请输入新密码>>:
password|pw1
field|@TR<<确认新密码>>:
password|pw2
end_form
EOF

cat <<EOF
					</div>
				</div>
			</div>
		</div>	
	</div>
</div>
EOF

wifisong_footer ?>

<!--
##WEBIF:name:System:250:Password
-->

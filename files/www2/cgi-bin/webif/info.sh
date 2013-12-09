#!/usr/bin/webif-page
<?
. "/usr/lib/webif/webif.sh"

config_cb() {
	local cfg_type="$1"
	local cfg_name="$2"

	case "$cfg_type" in
		system)
			hostname_cfg="$cfg_name"
		;;
	        wifi-device)
	                append DEVICES "$cfg_name"
	        ;;
	        wifi-iface)
	                append vface "$cfg_name" "$N"
	        ;;
	        interface)
		        append network "$cfg_name" "$N"
	        ;;
	esac
}

uci_load "system"
eval CONFIG_systemhostname="\$CONFIG_${hostname_cfg}_hostname"
FORM_hostname="${FORM_hostname:-$CONFIG_systemhostname}"
FORM_hostname="${FORM_hostname:-OpenWrt}"
config_clear "$hostname_cfg"

board_type=$(cat /proc/cpuinfo 2>/dev/null | sed 2,20d | cut -c16-)
wifisong_version=$(cat /etc/version)

wan_address=`ubus call network.interface.wan status | grep -A2 pv4-address | awk 'NR==3, /.+/{ print $2 }' | sed -r 's/(")([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(",)/\2/'`
wan_mask=`ifconfig | grep -A1 eth1 | awk 'NR==2, /.+/{ print $4}' | sed -r 's/(Mask:)(.+)/\2/'`
wan_gateway=`route -n | grep UG | awk '/.+/ { print $2 }'`
wan_dns1=`ubus call network.interface.wan status | grep -A2 dns-server | awk 'NR==2, /.+/{ print $1 }' | sed -r '/(")([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(",?)/!d;s//\2/'`
wan_dns2=`ubus call network.interface.wan status | grep -A2 dns-server | awk 'NR==3, /.+/{ print $1 }' | sed -r '/(")([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(",?)/!d;s//\2/'`
wan_uptime=`ubus call network.interface.wan status | grep uptime | awk '/.+/{print $2}' | sed -r 's/([0-9]+)(,?)/\1/'`
wan_uptime_days=$(( $wan_uptime/3600/24 ))                                                    
wan_uptime_hours=$(( $wan_uptime/3600 - $wan_uptime_days*24 ))                                
wan_uptime_minutes=$(( $wan_uptime/60 - $wan_uptime_days*24*60 - $wan_uptime_hours*60 ))

lan_address=`uci get network.lan.ipaddr`
lan_mask=`uci get network.lan.netmask`

generate_channels() {
	iwlist channel 2>&- |grep -q "GHz"
	if [ "$?" != "0" ]; then
		is_package_installed kmod-madwifi
		if [ "$?" = "0" ]; then
			wlanconfig ath create wlandev wifi0 wlanmode ap 2>/dev/null >/dev/null
			cleanup=1
                	BGCHANNELS="$(iwlist channel 2>&- |grep -v "no frequency information." |grep -v "[Ff]requenc" |grep -v "Current" |grep "2.[0-9]" |cut -d' ' -f12|sort |uniq)"
			ACHANNELS="$(iwlist channel 2>&- |grep -v "no frequency information." |grep -v "[Ff]requenc" |grep -v "Current" |grep "5.[0-9]" |cut -d' ' -f12|sort |uniq)"
		fi
		is_package_installed kmod-mac80211
		if [ "$?" = "0" ]; then
			BGCHANNELS="$(iw list |grep 24[0-9][0-9] |grep "dBm" |cut -d '[' -f2 |cut -d ']' -f1 |uniq)"
			ACHANNELS="$(iw list |grep 5[0-9][0-9][0-9] |grep "dBm" |cut -d '[' -f2 |cut -d ']' -f1 |uniq)"
		fi
	else
		BGCHANNELS="$(iwlist channel 2>&- |grep -v "no frequency information." |grep -v "[Ff]requenc" |grep -v "Current" |grep "2.[0-9]" |cut -d' ' -f12|sort |uniq)"
		ACHANNELS="$(iwlist channel 2>&- |grep -v "no frequency information." |grep -v "[Ff]requenc" |grep -v "Current" |grep "5.[0-9]" |cut -d' ' -f12|sort |uniq)"
		echo "BGCHANNELS=\"${BGCHANNELS}\"" > /usr/lib/webif/channels.lst
		echo "ACHANNELS=\"${ACHANNELS}\"" >> /usr/lib/webif/channels.lst
	fi
	if [ "$cleanup" = "1" ]; then
		wifi 2>/dev/null >/dev/null
	fi
}

if [ ! -f /usr/lib/webif/channels.lst ]; then
	generate_channels
fi

[ -f /usr/lib/webif/channels.lst ] && . /usr/lib/webif/channels.lst
[ -f /usr/lib/webif/countrycodes.lst ] && . /usr/lib/webif/countrycodes.lst

if [ -z "$BGCHANNELS" -a -z "$ACHANNELS" ]; then
	generate_channels
fi

dmesg_txt="$(dmesg)"
adhoc_count=0
ap_count=0
sta_count=0
validate_wireless() {
	case "$adhoc_count:$sta_count:$ap_count" in
		0:0:?)
			if [ "$ap_count" -gt "4" ]; then
				append validate_error "string|<h3>@TR<<Error: Only 4 virtual adapters are allowed in ap mode.>></h3><br />"
			fi
			;;
		0:?:?)
			if [ "$sta_count" -gt "1" ]; then
				append validate_error "string|<h3>@TR<<Error: Only 1 adaptor is allowed in client mode.>></h3><br />"
			fi
			if [ "$1"="broadcom" ]; then
				if [ "$ap_count" -gt "3" ]; then
					append validate_error "string|<h3>@TR<<Error: Only 3 virtual adapters are allowed in ap mode with a adapter in client mode.>></h3><br />"
				fi
			elif [ "$1"="atheros" ]; then
				if [ "$ap_count" -gt "4" ]; then
					append validate_error "string|<h3>@TR<<Error: Only 4 virtual adapters are allowed in ap mode.>></h3><br />"
				fi	
			fi
			;;
	esac
	#reset variables
	adhoc_count=0
	ap_count=0
	sta_count=0
}

uci_load network
network=$(echo "$network" |uniq)
NETWORK_DEVICES="none $network_devices"
uci_load webif
uci_load wireless

#FIXME: uci_load bug
#uci_load will pass the same config twice when there is a section to be added by using uci_add before a uci_commit happens
#we will use uniq so we don't try to parse the same config section twice.
vface=$(echo "$vface" |uniq)

vcfg_number=$(echo "$DEVICES $N $vface" |wc -l)
let "vcfg_number+=1"
device_count=0
#####################################################################
#setup network device form for vfaces
#
for iface in $NETWORK_DEVICES; do
	network_options="$network_options 
			option|$iface|$iface"
done

################## interface - wan ################
config_get delete_check wan proto
if empty "$FORM_submit"; then
	config_get FORM_proto wan proto
	config_get FORM_ipaddr wan ipaddr
	config_get FORM_netmask wan netmask
	config_get FORM_gateway wan gateway
	config_get FORM_username wan username
	config_get FORM_passwd wan passwd
	config_get FORM_dns wan dns
else
	eval FORM_proto="\$FORM_wan_proto"
	eval FORM_ipaddr="\$FORM_wan_ipaddr"
	eval FORM_netmask="\$FORM_wan_netmask"
	eval FORM_gateway="\$FORM_wan_gateway"
	eval FORM_username="\$FORM_wan_username"
	eval FORM_passwd="\$FORM_wan_passwd"
	eval FORM_dns="\$FORM_wan_dns"
	[ "$?" = "0" ] && {
		uci_set "network" "wan" "proto" "$FORM_proto"
		uci_set "network" "wan" "ipaddr" "$FORM_ipaddr"      
		uci_set "network" "wan" "netmask" "$FORM_netmask"
		uci_set "network" "wan" "gateway" "$FORM_gateway"
		uci_set "network" "wan" "username" "$FORM_username"
		uci_set "network" "wan" "passwd" "$FORM_passwd"
		uci_set "network" "wan" "dns" "$FORM_dns"
		
		case "$FORM_proto" in
			dhcp)
				uci_remove "network" "wan" "gateway"
				;;
		esac
		
		exists /tmp/.webif/file-chilli.conf && CHILLI_CONFIG_FILE=/tmp/.webif/file-chilli.conf || CHILLI_CONFIG_FILE=/etc/chilli/defaults
		mkdir /tmp/.webif/
		
		case "$FORM_proto" in
			dhcp|static)
		       		cat $CHILLI_CONFIG_FILE | sed -r 's/(HS_WANIF=)(.+)/\1eth1/' > /tmp/.webif/file-chilli.conf;;
		     	pppoe)          
				cat $CHILLI_CONFIG_FILE | sed -r 's/(HS_WANIF=)(.+)/\1pppoe-wan/' > /tmp/.webif/file-chilli.conf;;
		esac
	}                                                            
fi                                                                   
 
if [ $FORM_type = "" ]; then
	wan_options="start_form|
		field|@TR<<网络连接类型>>
		string|中继模式
		end_form"
else
	wan_options="start_form|
		field|@TR<<网络连接类型>>
		select|wan_proto|$FORM_proto
		option|static|@TR<<静态地址>>
		option|dhcp|@TR<<动态地址>>
		option|pppoe|@TR<<PPPOE>>
		end_form

		start_form||wan_ip_settings|hidden
		field|@TR<<IP地址>>|field_wan_ipaddr|hidden
		text|wan_ipaddr|$FORM_ipaddr
		field|@TR<<子网掩码>>|field_wan_netmask|hidden
		text|wan_netmask|$FORM_netmask
		field|@TR<<网关>>|field_wan_gateway|hidden
		text|wan_gateway|$FORM_gateway
		field|@TR<<DNS服务器>>|field_wan_dns|hidden
		text|wan_dns|$FORM_dns
		end_form
															
		start_form||wan_ppp_settings|hidden
		field|@TR<<上网账号>>|field_wan_username|hidden
		text|wan_username|$FORM_username
		field|@TR<<上网密码>>|field_wan_passwd|hidden
		password|wan_passwd|$FORM_passwd
		end_form"
fi

append forms2 "$wan_options" "$N"

wan_js_forms="                                                                                                               
	v = (isset('wan_proto', 'pppoe')) 
	set_visible('wan_ppp_settings', v);                                                                             
	set_visible('field_wan_username', v);                                                                           
	set_visible('field_wan_passwd', v);                                                                             

	v = (isset('wan_proto', 'static'));
	set_visible('wan_ip_settings', v);
	set_visible('field_wan_ipaddr', v);
	set_visible('field_wan_netmask', v);
	set_visible('field_wan_gateway', v);
	set_visible('field_wan_dns', v);"

append js "$wan_js_forms" "$N"
###################################################


################## interface - lan ################
if empty "$FORM_submit"; then
	config_get FORM_ipaddr lan ipaddr
	config_get FORM_netmask lan netmask
else
	eval FORM_ipaddr="\$FORM_lan_ipaddr"
	eval FORM_netmask="\$FORM_lan_netmask"
	
	[ "$?" = "0" ] && {
		uci_set "network" "lan" "ipaddr" "$FORM_ipaddr"
		uci_set "network" "lan" "netmask" "$FORM_netmask"
	}
fi

lan_options="start_form||lan_ip_settings
field|@TR<<IP地址>>|field_lan_ipaddr
text|lan_ipaddr|$FORM_ipaddr
field|@TR<<子网掩码>>|field_lan_netmask
text|lan_netmask|$FORM_netmask
end_form"

append forms1 "$lan_options" "$N"
#####################################################

################## device ###########################
if empty "$FORM_submit"; then
	config_get FORM_channel radio0 channel
else
	eval FORM_channel="\$FORM_bgchannel_radio0"
	if [ "$?" = 0 ]; then
		uci_set "wireless" "radio0" "channel" "$FORM_channel"
	fi                                                                                                                               
fi

BG_CHANNELS="field|@TR<<工作频道>>|bgchannelform_$device
	select|bgchannel_radio0|$FORM_channel"
        for ch in $BGCHANNELS; do
       		BG_CHANNELS="$BG_CHANNELS
                	option|$ch"
	done
                                                                                                                                                               
append forms_3 "$BG_CHANNELS" "$N" 
#####################################################

###################### wifi-iface ###################
if empty "$FORM_submit"; then
	config_get FORM_ssid cfg033579 ssid
	config_get FORM_key cfg073579 key
else
	eval FORM_ssid_prefix="\$FORM_ssid_cfg033579"
	eval FORM_key="\$FORM_wpa_psk_cfg073579"

	if [ "$?" = 0 ]; then
		uci_set "wireless" "cfg033579" "ssid" "$FORM_ssid_prefix"-WiFiSong
		uci_set "wireless" "cfg073579" "ssid" "$FORM_ssid_prefix"-Office
		uci_set "wireless" "cfg073579" "key" "$FORM_key"
	fi

	FORM_ssid="$FORM_ssid_prefix"-WiFiSong
fi

ssid="field|@TR<<公用无线网>>|ssid_form_cfg033579
text|ssid_cfg033579|$(echo $FORM_ssid | sed -r 's/(.+)-WiFiSong/\1/')
string|-WiFiSong"
append forms_1 "$ssid" "$N"
	
ssid="field|@TR<<内部无线网>>|ssid_form_cfg073579
string|$(echo $FORM_ssid | sed -r 's/(.+)-WiFiSong/\1/')
string|-Office"
append forms_2 "$ssid" "$N"

wpa="field|@TR<<密码设置>>|wpapsk_cfg073579
password|wpa_psk_cfg073579|$FORM_key"
append forms_2 "$wpa" "$N"
######################################################

################## QoS ###############################




######################################################

#
# if form submit, then ...
# else ...
#
! empty "$FORM_submit" && {
	current_qos_item="$FORM_current_rule_index"
	! empty "$current_qos_item" && {
		# for validation purposes, replace non-numeric stuff in
		# ports list and port range with integer.
		ports_validate=$(echo "$FORM_current_ports" | sed s/','/'0'/g)
		portrange_validate=$(echo "$FORM_current_portrange" | sed s/'-'/'0'/g)
validate <<EOF
int|ports_validate|@TR<<Port Listing>>||$ports_validate
int|portrange_validate|@TR<<Port Range>>||$portrange_validate
ip|FORM_current_srchost|@TR<<Source IP>>||$FORM_current_srchost
ip|FORM_current_dsthost|@TR<<Dest IP>>||$FORM_current_dsthost
EOF
		if ! equal "$?" "0"; then
			echo "<div class=\"warning\">@TR<<qos_validation_failed#Validation of one or more fields failed! Not saving.>></div>"
		else
			SAVED=1
			uci_set "qos" "$current_qos_item" "target" "$FORM_current_target"
			uci_set_value_remove_if_empty "qos" "$current_qos_item" "srchost" "$FORM_current_srchost"
			uci_set_value_remove_if_empty "qos" "$current_qos_item" "dsthost" "$FORM_current_dsthost"
			uci_set_value_remove_if_empty "qos" "$current_qos_item" "proto" "$FORM_current_proto"
			uci_set_value_remove_if_empty "qos" "$current_qos_item" "ports" "$FORM_current_ports"
			uci_set_value_remove_if_empty "qos" "$current_qos_item" "portrange" "$FORM_current_portrange"
			uci_set_value_remove_if_empty "qos" "$current_qos_item" "layer7" "$FORM_current_layer7"
			uci_set_value_remove_if_empty "qos" "$current_qos_item" "ipp2p" "$FORM_current_ipp2p"
			uci_set_value_remove_if_empty "qos" "$current_qos_item" "mark" "$FORM_current_mark"
			uci_set_value_remove_if_empty "qos" "$current_qos_item" "tcpflags" "$FORM_current_tcpflags"
			uci_set_value_remove_if_empty "qos" "$current_qos_item" "pktsize" "$FORM_current_pktsize"
		fi
	}

	validate <<EOF
int|FORM_wan_dowload|@TR<<WAN Download Speed>>||$FORM_wan_download
int|FORM_wan_upload|@TR<<WAN Upload Speed>>||$FORM_wan_upload
EOF
	equal "$?" "0" && {
		SAVED=1
		uci_load qos # to check existing variables
		! equal "$FORM_wan_enabled" "$CONFIG_wan_enabled" && {
		 	uci_set "qos" "wan" "enabled" "$FORM_wan_enabled"
		}
		! equal "FORM_wan_overhead" "$CONFIG_wan_overhead" && {
			uci_set "qos" "wan" "overhead" "$FORM_wan_overhead"
		}
		! empty "$FORM_wan_download" && ! equal "$FORM_wan_download" "$CONFIG_wan_download" && {
			uci_set "qos" "wan" "download" "$FORM_wan_download"
		}
		! empty "$FORM_wan_upload" && ! equal "$FORM_wan_upload" "$CONFIG_wan_upload" && {
			uci_set "qos" "wan" "upload" "$FORM_wan_upload"
		}
		! empty "$FORM_webif_advanced" && ! equal "$FORM_webif_advanced" "$CONFIG_qos_show_advanced_rules" && {
			uci_set "webif" "qos" "show_advanced_rules" "$FORM_webif_advanced"
		}
	}
}

uci_load "qos"                                                                                                                                           
FORM_wan_enabled="$CONFIG_wan_enabled"
FORM_wan_download="$CONFIG_wan_download"
FORM_wan_upload="$CONFIG_wan_upload" 

#####################################################################
wifisong_header "System" "Settings" "@TR<<>>" ' onload="modechange()" ' "$SCRIPT_NAME"

#####################################################################
# initialize forms
if empty "$FORM_submit"; then
	# initialize all defaults

	has_nvram_support && {
		FORM_boot_wait="${boot_wait:-$(nvram get boot_wait)}"
		FORM_boot_wait="${FORM_boot_wait:-off}"
		FORM_wait_time="${wait_time:-$(nvram get wait_time)}"
		FORM_wait_time="${FORM_wait_time:-1}"
	}
	# webif settings
	FORM_effect="${CONFIG_general_use_progressbar}"		# -- effects checkbox
	if equal $FORM_effect "1" ; then FORM_effect="checked" ; fi	# -- effects checkbox
else
#####################################################################
# save forms
	SAVED=1
	validate <<EOF
hostname|FORM_hostname|@TR<<Host Name>>|nodots required|$FORM_hostname
EOF
	if equal "$?" 0 ; then
		empty "$hostname_cfg" && {
			uci_add system system
			hostname_cfg="$CONFIG_SECTION"
		}
		uci_set "system" "$hostname_cfg" "hostname" "$FORM_hostname"

		has_nvram_support && {
			case "$FORM_boot_wait" in
				on|off) save_setting system boot_wait "$FORM_boot_wait";;
			esac
			! empty "$FORM_wait_time" &&
			{
				save_setting system wait_time "$FORM_wait_time"
			}
		}
		FORM_effect=$FORM_effect_enable ; if equal $FORM_effect "1" ; then FORM_effect="checked" ; fi
	else
		echo "<br /><div class=\"warning\">@TR<<Warning>>: @TR<<system_settings_Hostname_failed_validation#Hostname failed validation. Can not be saved.>></div><br />"
	fi
fi

#####################################################################
# boot wait time
#
has_nvram_support && {
	#####################################################################
	# Initialize wait_time form
	for wtime in $(seq 1 30); do
		FORM_wait_time="$FORM_wait_time
			option|$wtime"
	done
}

cat <<EOF
<script type="text/javascript" src="/webif.js"></script>
<script type="text/javascript">
<!--
function modechange()
{
	var v;
	$js;
	
	hide('save');
	show('save');	

  	if(isset('wan_enabled','1'))                                                                     
	{                                                                                        
		document.getElementById('wan_upload').disabled = false;                                                       
                document.getElementById('wan_download').disabled = false;                                               
 	}                                                                                               
      	else                                                                                     
        {                                                                               
        	document.getElementById('wan_upload').disabled = true;          
           	document.getElementById('wan_download').disabled = true;
	}
EOF

has_nvram_support && cat <<EOF
	if(isset('boot_wait','on'))
	{
		document.getElementById('wait_time').disabled = false;
	}
	else
	{
		document.getElementById('wait_time').disabled = true;
	}
EOF
cat <<EOF
	var tz_info = value('system_timezone');
	if ((tz_info=='') || (tz_info==null)){
		set_value('show_TZ', tz_info);
	}
	else {
		var tz_split = tz_info.split('@');
		set_value('show_TZ', tz_split[1]);
	}
}
-->
</script>
EOF

#Translate the _uptime
_uptime_ch=""
_uptime_days=$(echo $_uptime | sed -r '/([0-9]+) days, .+/!d;s//\1/')
if [[ -z "$_uptime_days" ]]; then
	_uptime_minutes=$(echo $_uptime | sed -r '/([0-9]+) min, .+/!d;s//\1/')
	if [[ -z "$_uptime_minutes" ]]; then
		_uptime_hours=$(echo $_uptime | sed -r 's/([0-9]+):([0-9]+),.+/\1/')
		_uptime_minutes=$(echo $_uptime | sed -r 's/([0-9]+):([0-9]+),.+/\2/')
		_uptime_ch=$_uptime_ch$_uptime_hours小时$_uptime_minutes分钟    
	else
		_uptime_ch=$_uptime_ch$_uptime_minutes分钟
	fi
else
	_uptime_days=$(echo $_uptime | sed -r 's/([0-9]+) days, ([0-9]+):([0-9]+),.+/\1/')
	_uptime_hours=$(echo $_uptime | sed -r 's/([0-9]+) days, ([0-9]+):([0-9]+),.+/\2/')
	_uptime_minutes=$(echo $_uptime | sed -r 's/([0-9]+) days, ([0-9]+):([0-9]+),.+/\3/')
	_uptime_ch=$_uptime_ch$_uptime_days天$_uptime_hours小时$_uptime_minutes分钟
fi

cat <<EOF
<div id="page">
	<div id="header">
		<h1 class="logo"><a href="info.sh">WifiSong路由器设置</a></h1>
	</div>
	<div id="main">
		<div class="main-border clearfix">
			<div class="main-aside">
				<ul class="sidenav">
					<li><a href="info.sh" class="active">网络设置</a></li>
					<li><a href="password.sh">修改密码</a></li>
					<li><a href="reboot.sh">重启路由器</a></li>
				</ul>
				<span class="sidelogo"></span>
			</div>
			<div class="main-body">
				<div class="autorefresh">
					<input type="checkbox" id="chkRefresh" value="" />
					<label for="chkRefresh">自动刷新</label>
				</div>
				<div class="col-box">
					<h4 class="col-title">路由器基本信息</h4>
					<div class="col-bd">
EOF

display_form <<EOF
onchange|modechange
start_form|@TR<<>>
field|@TR<<路由器型号：>>                                                                                                                          
string|WiFiSong第二代智能路由器
field|@TR<<固件版本：>>
string|$wifisong_version
field|@TR<<工作模式：>>
string|认证模式+AP模式
field|@TR<<当前本地时间：>>
string|$_date $_time
field|@TR<<运行时间：>>
string|$_uptime_ch
end_form
EOF

cat <<EOF
					</div>
				</div>
				<div class="col-box">
					<h4 class="col-title">网络状态（外网WAN）</h4>
					<div class="col-bd">
EOF

display_form <<EOF
onchange|modechange
start_form|@TR<<>>
field|@TR<<IP地址：>>
string|$wan_address
field|@TR<<子网掩码：>>
string|$wan_mask
field|@TR<<网关：>>  
string|$wan_gateway
field|@TR<<DNS服务器1：>>
string|$wan_dns1
field|@TR<<DNS服务器2：>>
string|$wan_dns2
field|@TR<<联网时间：>>
string|$wan_uptime_days天$wan_uptime_hours小时$wan_uptime_minutes分钟
end_form
$forms2
EOF

cat <<EOF
					</div>
				</div>
				<div class="col-box">
					<h4 class="col-title">网络状态（内网LAN）</h4>
					<div class="col-bd">
EOF

display_form <<EOF
onchange|modechange
$forms1
EOF
                                                                                              
cat <<EOF
					</div>
				</div>
				<div class="col-box">
					<h4 class="col-title">无线状态</h4>                                                                         
					<div class="col-bd">
EOF

display_form <<EOF
onchange|modechange
start_form|@TR<<>>
$validate_error
$forms_1
end_form
start_form|@TR<<>>                                                                                                                                       
$validate_error
$forms_2
end_form
start_form|@TR<<>>                                                                                                                                       
$validate_error
$forms_3
end_form
EOF

cat <<EOF
					</div>
				</div>
				<div class="col-box">
					<h4 class="col-title">QoS</h4>
				  	<div class="col-bd">
EOF

display_form <<EOF
onchange|modechange
start_form|@TR<<>>
field|@TR<<QoS 服务>>|field_n_enabled
select|wan_enabled|$FORM_wan_enabled
option|1|@TR<<qos_enabled#启动>>
option|0|@TR<<qos_disabled#停止>>
field|@TR<<WAN 上传速度>>|field_n_wan_upload
text|wan_upload|$FORM_wan_upload| @TR<<千比特每秒>>
field|@TR<<WAN 下载速度>>|field_n_wan_download
text|wan_download|$FORM_wan_download| @TR<<千比特每秒>>
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

footer ?>

<!--
##WEBIF:name:System:010:Settings
-->

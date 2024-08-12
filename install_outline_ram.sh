#!/bin/sh
# Outline scripted, xjasonlyu/tun2socks based installer for OpenWRT (RAM).
# https://github.com/1andrevich/outline-bgp-install-wrt
echo 'Starting Shadowsocks + Antifilter BGP OpenWRT install to RAM script'

# Step 1: Check for kmod-tun
opkg list-installed | grep kmod-tun > /dev/null
if [ $? -ne 0 ]; then
    echo "kmod-tun is not installed. Exiting."
    exit 1
    echo 'kmod-tun installed'
fi

# Step 2: Check for ip-full
opkg list-installed | grep ip-full > /dev/null
if [ $? -ne 0 ]; then
    echo "ip-full is not installed. Exiting."
    exit 1
    echo 'ip-full installed'
fi

# Step 3: Check for bird2c
opkg list-installed | grep bird2c > /dev/null
if [ $? -ne 0 ]; then
    echo "bird2c is not installed. Exiting."
    exit 1
    echo 'bird2c installed'                                                                                            fi 
fi

# Step 4: Check for tun2socks then download tun2socks binary from GitHub (to RAM)
if [ ! -f "/tmp/tun2socks*" ]; then
ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')
wget https://github.com/1andrevich/outline-install-wrt/releases/download/v2.5.1/tun2socks-linux-$ARCH -O /tmp/tun2socks
 # Check wget's exit status
    if [ $? -ne 0 ]; then
        echo "Download failed. No file for your Router's architecture"
        exit 1
   fi
fi
# Step 5: Executing chmod +x command
chmod +x /tmp/tun2socks

# Step 6: Check for existing config in /etc/config/network then add entry
if ! grep -q "config interface 'tunnel'" /etc/config/network; then
echo "
config interface 'tunnel'
    option device 'tun1'
    option proto 'static'
    option ipaddr '172.16.10.1'
    option netmask '255.255.255.252'
" >> /etc/config/network
    echo 'added entry into /etc/config/network'
fi
echo 'found entry into /etc/config/network'

# Step 7:Check for existing config /etc/config/firewall then add entry
if ! grep -q "option name 'proxy'" /etc/config/firewall; then 
echo "
config zone
    option name 'proxy'
    list network 'tunnel'
    option forward 'REJECT'
    option output 'ACCEPT'
    option input 'REJECT'
    option masq '1'
    option mtu_fix '1'
    option device 'tun1'
    option family 'ipv4'

config forwarding
    option name 'lan-proxy'
    option dest 'proxy'
    option src 'lan'
    option family 'ipv4'
" >> /etc/config/firewall
    echo 'added entry into /etc/config/firewall'
fi

echo 'found entry into /etc/config/firewall'
# Step 8: Restart network
/etc/init.d/network restart
echo 'Restarting Network....'

sleep 2

# Step 9: Read user variable for Outline config
read -p "Enter Outline (Shadowsocks) Config (format ss://base64coded@HOST:PORT/?outline=1): " OUTLINECONF
# Extract the domain/hostname part from the link using sed
domain_or_ip=$(echo $OUTLINECONF | sed 's/.*@\(.*\):.*/\1/')

# Check if the extracted string is an IP address or a domain name
if echo "$domain_or_ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    # It's an IP address
    echo "IP of Outline Server is: $domain_or_ip"
	OUTLINEIP=$domain_or_ip
else
    # It's a domain name, resolve it to an IP address using ping
    resolved_ip=$(ping -c 1 $domain_or_ip | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    if [ -n "$resolved_ip" ]; then
        echo "Resolved IP for Outline Server is $domain_or_ip: $resolved_ip"
		OUTLINEIP=$resolved_ip
    else
        echo "Failed to resolve IP for domain $domain_or_ip . Check DNS settings and re-run the script"
		exit 1  # Halt the script with a non-zero exit status
    fi
fi

#Step 10. Check for default gateway and save it into DEFGW
DEFGW=$(ip route | grep default | awk '{print $3}')
echo 'checked default gateway'

#Step 11. Check for default interface and save it into DEFIF
DEFIF=$(ip route | grep default | awk '{print $5}')
echo 'checked default interface'

# Step 12: Create script /etc/init.d/tun2socks
if [ ! -f "/etc/init.d/tun2socks" ]; then
cat <<EOL > /etc/init.d/tun2socks
#!/bin/sh /etc/rc.common
USE_PROCD=1

# starts after network starts
START=99
# stops before networking stops
STOP=89

#PROG=/usr/bin/tun2socks
#IF="tun1"
#OUTLINE_CONFIG="$OUTLINECONF"
#LOGLEVEL="warning"
#BUFFER="64kb"

#Check for tun2socks then download tun2socks binary from GitHub to RAM
before_start() {
if [ ! -f "/tmp/tun2socks*" ]; then
  ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')
  wget https://github.com/1andrevich/outline-install-wrt/releases/download/v2.5.1/tun2socks-linux-$ARCH -O /tmp/tun2socks
 # Check wget's exit status
    if [ $? -ne 0 ]; then
        echo "Download failed. No file for your Router's architecture"
        exit 1
   fi
fi
#Executing chmod +x command
chmod +x /tmp/tun2socks
}

start_service() {
    before_start
    procd_open_instance
    procd_set_param user root
    procd_set_param command /tmp/tun2socks -device tun1 -tcp-rcvbuf 64kb -tcp-sndbuf 64kb  -proxy "$OUTLINECONF" -loglevel "warning"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn "${respawn_threshold:-3600}" "${respawn_timeout:-5}" "${respawn_retry:-5}"
    procd_close_instance
    ip route add "$OUTLINEIP" via "$DEFGW" #Adds route to OUTLINE Server
	echo 'route to Outline Server added'
	ip route add 45.154.73.71 via 172.16.10.2 dev tun1
	echo 'route to Antifilter BGP server through Shadowsocks added'
    ip route save default > /tmp/defroute.save  #Saves existing default route
    echo "tun2socks is working!"
}

boot() {
    # This gets run at boot-time.
    start
}

shutdown() {
    # This gets run at shutdown/reboot.
    stop
}

stop_service() {
    service_stop /tmp/tun2socks
    ip route restore default < /tmp/defroute.save #Restores saved default route
    ip route del "$OUTLINEIP" via "$DEFGW" #Removes route to OUTLINE Server
    echo "tun2socks has stopped!"
}

reload_service() {
    stop
    sleep 3s
    echo "tun2socks restarted!"
    start
}
EOL
start() {
    start_service
    service_started
}
EOL
chmod +x /etc/init.d/tun2socks
fi

# Step 13: Create symbolic link, autostart
if [ ! -f "/etc/rc.d/S99tun2socks" ]; then
ln -s /etc/init.d/tun2socks /etc/rc.d/S99tun2socks
echo '/etc/init.d/tun2socks /etc/rc.d/S99tun2socks symlink created'
fi

# Step 14: Start service
/etc/init.d/tun2socks start

#Step 15: Create config for bird2 BGP Client (Antifilter)

#First we make /etc/bird.conf empty:
echo -n "" > /etc/bird.conf
RANDOM_SEED=$(cat /dev/urandom | tr -dc '0-9' | head -c 5)
ASN=$((64512 + RANDOM_SEED % 20))
#Then we create new config based on previous data
cat <<EOL >> /etc/bird.conf
log syslog all;
log stderr all;

router id $resolved_ip ;

protocol device {
    scan time 300;
}

protocol kernel kernel_routes {
    scan time 60;
    ipv4 {
        import none;
        export all;
    };
}

protocol bgp antifilter {
    ipv4 {
        import filter {
            ifname = "tun1";
            accept;
        };
        export none;
    };
    local as $ASN;
    neighbor 45.154.73.71 as 65432;
    multihop;
    hold time 240;
}
EOL

#Restarting bird2 service to apply new configuration
service bird restart
echo 'Bird2 restarted'
# Check the number of 'Import updates' from the bird2 show protocols
import_updates=$(birdc show protocols all antifilter | grep 'Import updates' | awk '{print $3}')

if [ -z "$import_updates" ]; then
    echo "Error: No import updates found."
    exit 1  # Halt the script with a failure status
else
    echo "Antifilter BGP is working with $import_updates import updates."
fi	

# Diagnostics: Run traceroute to facebook.com and capture the output
traceroute_output=$(traceroute -m1 facebook.com)

# Display the traceroute output to the user
echo "Traceroute to facebook.com:"
echo "$traceroute_output"

echo 'Script has finished'

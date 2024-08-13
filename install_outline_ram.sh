#!/bin/sh
# Shadowsocks scripted, xjasonlyu/tun2socks, bird2 based installer for OpenWRT (RAM).
# https://github.com/1andrevich/outline-bgp-install-wrt
echo 'Starting Shadowsocks + Antifilter BGP OpenWRT install to RAM script'

# Step 1: Check for kmod-tun
if opkg list-installed | grep -q kmod-tun; then
    echo -e "\033[0;32m kmod-tun is installed. \033[0m"
else
    echo -e "\033[0;31m kmod-tun is not installed. Run 'opkg install kmod-tun' to install the package. Exiting. \033[0m"
    exit 1
fi

# Step 2: Check for ip-full
if opkg list-installed | grep ip-full; then
    echo -e "\033[0;32m ip-full is installed. \033[0m"
else
    echo -e "\033[0;31m ip-full is not installed. Run 'opkg install ip-full' to install package. Exiting. \033[0m"
    exit 1
fi

# Step 3: Check for bird2c
if opkg list-installed | grep -q bird2c; then
    echo -e "\033[0;32m bird2c is installed. \033[0m"
else
    echo -e "\033[0;31m bird2c is not installed. Run 'opkg install bird2c' to install package. Exiting. \033[0m"
    exit 1
fi

# Step 4: Check for tun2socks then download tun2socks binary from GitHub (to RAM)
if [ ! -f "/tmp/tun2socks*" ]; then
ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')
wget https://github.com/1andrevich/outline-install-wrt/releases/download/v2.5.1/tun2socks-linux-$ARCH -O /tmp/tun2socks
 # Check wget's exit status
    if [ $? -ne 0 ]; then
        echo -e "\033[0;31m Download failed. No file for your Router's architecture \033[0m"
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
    echo -e '\033[0;32m added entry into /etc/config/network \033[0m'
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
    echo -e '\033[0;32m added entry into /etc/config/firewall \033[0m'
fi

echo 'found entry into /etc/config/firewall'
echo 'Restarting Network....'
# Step 8: Restart network
/etc/init.d/network restart

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
        echo -e "\033[0;31m Failed to resolve IP for domain $domain_or_ip . Check DNS settings and re-run the script \033[0m"
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
START=69
# stops before networking stops
STOP=89

#PROG=/usr/bin/tun2socks
#IF="tun1"
#OUTLINE_CONFIG="$OUTLINECONF"
#LOGLEVEL="warning"
#BUFFER="64kb"

#Check for tun2socks then download tun2socks binary from GitHub to RAM
before_start() {
    attempts=0
    max_attempts=5

    while [ "\$attempts" -lt "\$max_attempts" ]; do
        if [ ! -f "/tmp/tun2socks" ]; then
            ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')
            wget https://github.com/1andrevich/outline-install-wrt/releases/download/v2.5.1/tun2socks-linux-$ARCH -O /tmp/tun2socks
            # Check wget's exit status
            if [ \$? -ne 0 ]; then
                echo -e "\033[0;31m Download failed. No file for your Router's architecture. Attempt \$((attempts + 1)) of \$max_attempts failed. \033[0m"
            else
                # Executing chmod +x command only if wget is successful
                chmod +x /tmp/tun2socks
                echo "\033[0;32m /tmp/tun2socks downloaded successfully. \033[0m"
                return 0  # Exit the function successfully
            fi
        else
            echo "/tmp/tun2socks exists. Proceeding..."
            return 0  # Exit the function successfully
        fi
		
        attempts="\$((attempts + 1))"
        echo "Retrying in 5 seconds... (\$attempts/\$max_attempts)"
        sleep 5
    done

    echo -e "\033[0;31m Failed to download /tmp/tun2socks after \$max_attempts attempts. Aborting. \033[0m"
    exit 1  # Exit the script with an error
}
start_service() {
    before_start
    # Wait for /tmp/tun2socks to exist, with a timeout of 30 seconds
    timeout=30
    while [ ! -f "/tmp/tun2socks" ]; do
        sleep 1
        timeout="\$((timeout - 1))"
        
        echo "Current timeout value: "\$timeout""  # Debugging line

        if [ \$timeout -le 0 ]; then
            echo -e "\033[0;31m /tmp/tun2socks not found after 30 seconds. Try manually restarting tun2socks service. Exiting. \033[0m"
            break  # Exit the loop when timeout reaches 0
        fi
    done

    # After the loop, check if it exited due to timeout reaching 0
    if [ \$timeout -le 0 ]; then
        exit 1
    fi
	
    procd_open_instance
    procd_set_param user root
    procd_set_param command /tmp/tun2socks -device tun1 -tcp-rcvbuf 64kb -tcp-sndbuf 64kb  -proxy "$OUTLINECONF" -loglevel "warning"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn \${respawn_threshold:-3600} \${respawn_timeout:-5} \${respawn_retry:-5}
    procd_close_instance
    ip route add "$OUTLINEIP" via "$DEFGW" #Adds route to OUTLINE Server
	echo -e '\033[0;32m route to Outline Server added \033[0m'
    echo -e "\033[0;32m tun2socks is working! \033[0m"
}

service_started() {
    attempts=0
    max_attempts=5

    while [ "\$attempts" -lt "\$max_attempts" ]; do
        if ip link show tun1 | grep -q "tun1"; then
            ip route add 45.154.73.71 dev tun1
            echo -e '\033[0;32m Route to Antifilter BGP server through Shadowsocks added \033[0m'
            return 0  # Exit the function successfully
        else
            echo "tun1 interface is not up yet. Attempt \$((attempts + 1)) of \$max_attempts. Retrying in 5 seconds..."
        fi

        attempts=\$((attempts + 1))
        sleep 2
    done

    echo "Failed to bring up tun1 interface after \$max_attempts attempts. Aborting."
    exit 1  # Exit the script with an error
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
    ip route del "$OUTLINEIP" via "$DEFGW" #Removes route to OUTLINE Server
	ip route del 45.154.73.71 dev tun1
	echo 'route to Antifilter BGP server through Shadowsocks deleted'
    echo "tun2socks has stopped!"
}

reload_service() {
    stop
    sleep 3s
    echo -e "\033[0;32m tun2socks restarted! \033[0m"
    start
}

start() {
    start_service
    service_started
}
EOL
chmod +x /etc/init.d/tun2socks
fi

# Step 13: Create symbolic link, autostart
if [ ! -f "/etc/rc.d/S69tun2socks" ]; then
ln -s /etc/init.d/tun2socks /etc/rc.d/S69tun2socks
echo '/etc/init.d/tun2socks /etc/rc.d/S69tun2socks symlink created'
fi

# Step 14: Start service
/etc/init.d/tun2socks start
echo 'Starting tun2socks service'

#Step 15: Create config for bird2 BGP Client (Antifilter)
echo 'Creating config for Antifilter client'

#First we make /etc/bird.conf empty:
echo -n "" > /etc/bird.conf
echo 'Clearing /etc/bird.conf file'
RANDOM_SEED=$(cat /dev/urandom | tr -dc '0-9' | head -c 5)
ASN=$((64512 + RANDOM_SEED % 20)) #Generate Random ASN number
echo "Generating ASN Number: $ASN"
#Then we create new config based on previous data

cat <<EOL >> /etc/bird.conf
log syslog all;
log stderr all;

router id $OUTLINEIP;

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
echo 'new /etc/bird.conf file created'

#Restarting bird2 service to apply new configuration
sleep 3
service bird restart
echo 'Bird2 restarted'
echo 'Waiting for bird2 to connect to Antifilter.download BGP'
sleep 15
# Check the number of 'Import updates' from the bird2 show protocols
import_updates=$(birdc show protocols all antifilter | grep 'Import updates' | awk '{print $3}')
sleep 1
if [ -z "$import_updates" ]; then
    echo -e "\033[0;31m Error: No route import updates found. BGP Server might be not available. \033[0m"
    exit 1  # Halt the script with a failure status
else
    echo -e "\033[0;32m Antifilter BGP is working with $import_updates routes. \033[0m"
fi	

# Diagnostics: Run traceroute to facebook.com and capture the output
ping_output_fb=$( ping -4 -w2 facebook.com)
ping_output_yt=$( ping -4 -w2 youtube.com)
ping_output_tw=$( ping -4 -w2 x.com)

# Display the traceroute output to the user
echo "Ping to facebook.com:"
echo "$ping_output_fb"
echo "Ping to youtube.com:"
echo "$ping_output_yt"
echo "Ping to x.com (Twitter):"
echo "$ping_output_tw"
echo "If time is less then 0.5ms it means that tunneling is working"

echo -e "\033[0;32m Script has finished working \033[0m"

# outline-bgp-install-wrt
OpenWRT /bin/sh script to install Outline (Shadowsocks) + bird2 BGP Client for Antifilter.download with [xjasonlyu/tun2socks](https://github.com/xjasonlyu/tun2socks)

## How to use:

First, get the script and make it executable:

    cd /tmp
    wget https://raw.githubusercontent.com/1andrevich/outline-bgp-install-wrt/main/install_outline.sh -O install_outline.sh
    chmod +x install_outline.sh

Check if you have kmod-tun, bird2c and ip-full installed, if not run:

    opkg update
    opkg install kmod-tun ip-full bird2c

**Then run the script:**
You'll need at least **10 MiB of free space** on /

    ./install_outline.sh

You'll be asked for:

 - Outline (Shadowsocks) config in "ss://base64coded@HOST:PORT" format

**If you don't have enough free space** on / , you can install executable to RAM (You'll need **up to** **35 MiB** of RAM):

    cd /tmp
    wget https://raw.githubusercontent.com/1andrevich/outline-bgp-install-wrt/main/install_outline_ram.sh -O install_outline_ram.sh
    chmod +x install_outline_ram.sh
    ./install_outline_ram.sh

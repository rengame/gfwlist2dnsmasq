./gfwlist2dnsmasq.sh -d 8.8.8.8 -p 53 -s gfwlist -o gfwlist.conf --exclude-domain-file exclude.domain --extra-domain-file extra.domain
cp gfwlist.conf  /tmp/dnsmasq.d/
cp gfwlist.conf  /etc/dnsmasq.d/
/etc/init.d/dnsmasq restart

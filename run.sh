./gfwlist2dnsmasq.sh -d 1.1.1.1 -p 53 -s gfwlist -o gfwlist.conf --exclude-domain-file exclude.domain --extra-domain-file extra.domain
# ./gfwlist2dnsmasq.sh --group vpn --ipset gfwlist --out-type smartdns --exclude-domain-file exclude.domain --extra-domain-file extra.domain --output gfwlistforsmartdns.conf

cp gfwlist.conf  /tmp/dnsmasq.d/
cp gfwlist.conf  /etc/dnsmasq.d/
/etc/init.d/dnsmasq restart
# /etc/init.d/adguardhome restart

# cp gfwlistforsmartdns.conf /etc/smartdns/
# /etc/init.d/smartdns restart

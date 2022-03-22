./gfwlist2dnsmasq.sh -d 8.8.8.8 -p 53 -s gfwlist -o gfwlist.conf --exclude-domain-file exclude.domain --extra-domain-file extra.domain
./gfwlist2dnsmasq.sh -g vpn -s gfwlist -o ./test.conf -t smartdns --exclude-domain-file exclude.domain --extra-domain-file extra.domain -o gfwlistforsmartdns.conf

cp gfwlist.conf  /tmp/dnsmasq.d/
cp gfwlist.conf  /etc/dnsmasq.d/
/etc/init.d/dnsmasq restart

cp gfwlistforsmartdns.conf /etc/smartdns/
/etc/init.d/smartdns restart

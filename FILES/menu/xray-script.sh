#!/bin/bash

function add-user() {
	clear
	echo -e "Add Xray User"
	echo -e "-------------"
	read -p "Username : " user
	if grep -qw "$user" /admin/xray/xray-clients.txt; then
		echo -e ""
		echo -e "User '$user' already exist."
		echo -e ""
		exit 0
	fi
	read -p "Duration (day) : " duration

	uuid=$(uuidgen)
	exp=$(date -d +${duration}days +%Y-%m-%d)
	expired=$(date -d "${exp}" +"%d %b %Y")
	domain=$(cat /usr/local/etc/xray/domain)
	email=${user}@${domain}
	echo -e "${user}\t${uuid}\t${exp}" >> /admin/xray/xray-clients.txt

	cat /usr/local/etc/xray/config.json | jq '.inbounds[0].settings.clients += [{"id": "'${uuid}'","flow": "xtls-rprx-direct","email": "'${email}'"}]' > /usr/local/etc/xray/config_tmp.json
	mv -f /usr/local/etc/xray/config_tmp.json /usr/local/etc/xray/config.json
	cat /usr/local/etc/xray/config.json | jq '.inbounds[1].settings.clients += [{"id": "'${uuid}'","email": "'${email}'"}]' > /usr/local/etc/xray/config_tmp.json
	mv -f /usr/local/etc/xray/config_tmp.json /usr/local/etc/xray/config.json
	service xray restart

	clear
	echo -e "Xray User Information"
	echo -e "---------------------"
	echo -e "Username : $user"
	echo -e "Expired date : $expired"
	echo -e ""
}

function delete-user() {
	clear
	echo -e "Delete Xray User"
	echo -e "----------------"
	read -p "Username : " user
	echo -e ""
	if ! grep -qw "$user" /admin/xray/xray-clients.txt; then
		echo -e ""
		echo -e "User '$user' does not exist."
		echo -e ""
		exit 0
	fi
	uuid="$(cat /admin/xray/xray-clients.txt | grep -w "$user" | awk '{print $2}')"

	cat /usr/local/etc/xray/config.json | jq 'del(.inbounds[0].settings.clients[] | select(.id == "'${uuid}'"))' > /usr/local/etc/xray/config_tmp.json
	mv -f /usr/local/etc/xray/config_tmp.json /usr/local/etc/xray/config.json
	cat /usr/local/etc/xray/config.json | jq 'del(.inbounds[1].settings.clients[] | select(.id == "'${uuid}'"))' > /usr/local/etc/xray/config_tmp.json
	mv -f /usr/local/etc/xray/config_tmp.json /usr/local/etc/xray/config.json
	sed -i "/\b$user\b/d" /admin/xray/xray-clients.txt
	service xray restart

	echo -e "User '$user' deleted successfully."
	echo -e ""
}

function extend-user() {
	clear
	echo -e "Extend Xray User"
	echo -e "----------------"
	read -p "Username : " user
	if ! grep -qw "$user" /admin/xray/xray-clients.txt; then
		echo -e ""
		echo -e "User '$user' does not exist."
		echo -e ""
		exit 0
	fi
	read -p "Duration (day) : " extend

	uuid=$(cat /admin/xray/xray-clients.txt | grep -w $user | awk '{print $2}')
	exp_old=$(cat /admin/xray/xray-clients.txt | grep -w $user | awk '{print $3}')
	diff=$((($(date -d "${exp_old}" +%s)-$(date +%s))/(86400)))
	duration=$(expr $diff + $extend + 1)
	exp_new=$(date -d +${duration}days +%Y-%m-%d)
	exp=$(date -d "${exp_new}" +"%d %b %Y")

	sed -i "/\b$user\b/d" /admin/xray/xray-clients.txt
	echo -e "$user\t$uuid\t$exp_new" >> /admin/xray/xray-clients.txt

	clear
	echo -e "Xray User Information"
	echo -e "---------------------"
	echo -e "Username : $user"
	echo -e "Expired date : $exp"
	echo -e ""
}

function user-list() {
	clear
	echo -e ""
	echo -e "==============================="
	echo -e "Username          Exp. Date"
	echo -e "-------------------------------"
	while read expired
	do
		user=$(echo $expired | awk '{print $1}')
		exp=$(echo $expired | awk '{print $3}')
		exp_date=$(date -d"${exp}" "+%d %b %Y")
		printf "%-17s %2s\n" "$user" "$exp_date"
	done < /admin/xray/xray-clients.txt
	total=$(wc -l /admin/xray/xray-clients.txt | awk '{print $1}')
	echo -e "-------------------------------"
	echo -e "Total accounts: $total"
	echo -e "==============================="
	echo -e ""
}

function user-monitor() {
	data=($(cat /admin/xray/xray-clients.txt | awk '{print $1}'))
	data2=($(netstat -anp | grep ESTABLISHED | grep tcp6 | grep xray | grep -w 443 | awk '{print $5}' | cut -d: -f1 | sort | uniq))
	domain=$(cat /usr/local/etc/xray/domain)
	touch /tmp/{ipvless.txt,ipvless-other.txt}
	clear
	echo -e ""
	echo -e "========================="
	echo -e "  Xray Login Monitor"
	echo -e "-------------------------"
	for user in "${data[@]}"
	do
		for ip in "${data2[@]}"
		do
			total=$(cat /var/log/xray/access.log | grep -w ${user}@${domain} | awk '{print $3}' | cut -d: -f1 | grep -w $ip | sort | uniq)
			if [[ "$total" = "$ip" ]]; then
				echo -e "$total" >> /tmp/ipvless.txt
			else
				echo -e "$ip" >> /tmp/ipvless-other.txt
			fi
			total2=$(cat /tmp/ipvless.txt)
			sed "/${total2}/d" /tmp/ipvless-other.txt
		done
		total=$(cat /tmp/ipvless.txt)
		if [[ -n "$total" ]]; then
			total2=$(cat /tmp/ipvless.txt | nl)
			echo -e "$user :"
			echo -e "$total2"
		fi
	done
	other=$(cat /tmp/ipvless-other.txt | sort | uniq | nl)
	if [[ -n "$other" ]]; then
		echo -e "other :"
		echo -e "$other"
	fi
	echo -e "========================="
	echo -e ""
	rm -f /tmp/{ipvless.txt,ipvless-other.txt}
}

function show-config() {
	echo -e "Xray Config"
	echo -e "-----------"
	read -p "User : " user
	if ! grep -qw "$user" /admin/xray/xray-clients.txt; then
		echo -e ""
		echo -e "User '$user' does not exist."
		echo -e ""
		exit 0
	fi
	uuid=$(cat /admin/xray/xray-clients.txt | grep -w "$user" | awk '{print $2}')
	domain=$(cat /usr/local/etc/xray/domain)
	exp=$(cat /admin/xray/xray-clients.txt | grep -w "$user" | awk '{print $3}')
	exp_date=$(date -d"${exp}" "+%d %b %Y")

	echo -e "Expired : $exp_date"
	echo -e ""
	echo -e "VLESS + WebSocket + TLS"
	echo -e "-----------------------"
	echo -e "Host : $domain"
	echo -e "Server Port : 443"
	echo -e "User ID : $uuid"
	echo -e "Security : none"
	echo -e "Network Type : ws"
	echo -e "WebSocket Path : /xray"
	echo -e "TLS : tls"
	echo -e ""
	echo -e "Link : vless://$uuid@$domain:443?type=ws&security=tls&path=%2fxray#WS_TLS-$domain"
	echo -e "QR : https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless://$uuid@$domain:443?type=ws%26security=tls%26path=%2fxray%23WS_TLS-$domain"
	echo -e ""
	echo -e "VLESS + TLS / XTLS"
	echo -e "------------------"
	echo -e "Adress: $domain"
	echo -e "Port: 443"
	echo -e "ID: $uuid"
	echo -e "Flow: xtls-rprx-direct"
	echo -e "Encryption: none"
	echo -e "Network: tcp"
	echo -e "Head Type: none"
	echo -e "TLS: tls / xtls"
	echo -e ""
	echo -e "Link : vless://$uuid@$domain:443?security=xtls&flow=xtls-rprx-direct#XTLS-$domain"
	echo -e "QR : https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless://$uuid@$domain:443?security=xtls%26flow=xtls-rprx-direct%23XTLS-$domain"
	echo -e ""
}

clear
echo -e "==========[ Xray Menu ]=========="
echo -e ""
echo -e "  [1] Add Xray user"
echo -e "  [2] Delete Xray user"
echo -e "  [3] Extend Xray user"
echo -e "  [4] Xray user list"
echo -e "  [5] Xray user monitor"
echo -e "  [6] Show Xray configuration"
echo -e "  [7] Exit"
echo -e ""
until [[ ${option} =~ ^[1-7]$ ]]; do
	read -rp "Select an option [1-7]: " option
done
case "${option}" in
1)
	add-user
	;;
2)
	delete-user
	;;
3)
	extend-user
	;;
4)
	user-list
	;;
5)
	user-monitor
	;;
6)
	clear
	show-config
	;;
7)
	clear
	exit 0
	;;
esac
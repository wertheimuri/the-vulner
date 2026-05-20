#!/bin/bash
############################################################
# Student Name: Uri Wertheim
# Student Code: S9
# Class Code: TMagen773638
# Lecturer: Natalie Erez
# Project: PENETRATION TESTING | PROJECT: VULNER | ZX301
############################################################
#
#
welcome() 
{
	# Define a separator for the terminal
    SEP="---------------------------------------------------------------------------------------------"
    SEP1="- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    echo
	echo "$SEP1"
    echo "                           Welcome to THE VULNER v1.0        "
    echo "$SEP1"
    echo
    # Get the absolute path of where the script is located
    BASE_PATH=$(pwd)
}
#
#  - - - 1.1 ROOT CHECK 
#
#Function: check root: Check the current user; exit if not ‘root’.
#
check_root()
{
    if [[ $EUID -ne 0 ]]; 
		then
			echo "This script must be run as root. Exiting."
			exit 1
		#else 
		#	echo "Hello Superuser"
		#	echo
    fi
}
#
# --- Function: Tool Check and Installation ---
#
tools_setup()
{
	echo "running a quick check to see if your system can run this progaram" 	
	TOOLS=("nmap" "hydra" "exploitdb" "sshpass")
	UPDATED=false
	for tool in "${TOOLS[@]}";
		do
			# command -v checking if the tool in installed
			if ! command -v "$tool" &>/dev/null ; then
				echo "[!] $tool missing. Preparing to install..."
			#first installation need an update first.
				if [ "$UPDATED" = false ] ; then
					sudo apt-get update
					UPDATED=true
				fi
		#second or third instalation should not do update again.
			sudo apt install -y "$tool"
			#checking that the instalation succeeded it is essential for later.
				if ! command -v "$tool" ; then
					echo "[!!!] installation failed. please check your connections and re-run the program"
					echo "[!!!] Exiting..."
					exit 1
				fi 
			else
				echo "[+] $tool" "is already installed"
				sleep 1
			fi
		done
	# checking if geoiplookup is installed ( package name is different than program name ) 
	if ! command -v geoiplookup &>/dev/null; then
			echo "[!] geoiplookup missing. Installing package geoip-bin..."
			sudo apt install -y geoip-bin
	fi
	echo "[+] geoiplookup is installed "
	sleep 2
	echo "[+] All tools are set!"
	echo "[*] Moving to anonymity check: "
	sleep 2
    echo "$SEP"
}
# ---- Function install_nipe - Nipe Download Installation & Initiation- 
install_nipe() 
{
    echo "[!] Nipe not found. Starting first-time installation..."
    # 1. System-level install (Reliable)
    sudo apt update && sudo apt install -y libswitch-perl libjson-perl libreadonly-perl liblwp-protocol-https-perl libconfig-simple-perl
    
    # 2. CPAN install (Fallback/Backup)
    # We use -i to install and ensure Switch and JSON are definitely there
    sudo cpan install Switch JSON Config::Simple
    
    cd "$BASE_PATH" || exit
    git clone https://github.com/GouveaHeitor/nipe
    cd "$NIPE_PATH" || exit
    sudo perl nipe.pl install
}

#function: start Nipe - starting Nipe, checking status and extracting ip address
start_nipe()
{
    cd "$NIPE_PATH" || exit
    sudo perl nipe.pl restart
    sleep 5
    
    # Extract status and IP
    STATUS=$(sudo perl nipe.pl status | grep -i "status" | awk -F ': ' '{print $2}' | xargs)
    
    RETRY_COUNT=0
    until [[ "$STATUS" == "true" || $RETRY_COUNT -ge 3 ]]; do
        ((RETRY_COUNT++))
        echo "[*] ($RETRY_COUNT/3) Nipe status is '$STATUS'. Attempting restart..."
        sudo perl nipe.pl restart
        sleep 6
        STATUS=$(sudo perl nipe.pl status | grep -i "status" | awk -F ': ' '{print $2}' | xargs)
    done

    if [[ "$STATUS" != "true" ]]; then
        echo "[!!!] CRITICAL: Nipe failed to start (Status: $STATUS). Aborting for safety."
        exit 1
    fi

    # Record the spoofed IP for the next function to use
    SPOOFED_IP=$(sudo perl nipe.pl status | grep -i "ip" | awk -F ': ' '{print $2}' | xargs)
    echo "[+] Nipe is active. Spoofed IP: $SPOOFED_IP"
}

# ---- Function: anon_check

anon_check()
{
    NIPE_PATH="$BASE_PATH/nipe"
    
    # Step 1: Ensure it's installed
    if [ ! -d "$NIPE_PATH" ]; then
        install_nipe  
    fi

    # Step 2: Ensure it's running (The technical gate)
    
    start_nipe

    # Step 3: Check Geography (The OPSEC gate)
    # Use xargs to clean up any weird spacing in the country string
    S_COUNTRY=$(geoiplookup "$SPOOFED_IP" | awk -F ': ' '{print $2}' | xargs)
    
    GEO_COUNT=0
    # If it's Israel or empty, we loop
    while [[ "$S_COUNTRY" == *"Israel"* || -z "$S_COUNTRY" ]]; do
        ((GEO_COUNT++))
        if [[ $GEO_COUNT -ge 3 ]]; then
            echo "[!!!] CRITICAL: Could not bypass Home location. Quitting."
            exit 1
        fi
        
        echo "[!!!] SECURITY ALERT: Location matches Home Country ($S_COUNTRY). Retrying..."
        start_nipe # Try to get a new IP
        S_COUNTRY=$(geoiplookup "$SPOOFED_IP" | awk -F ': ' '{print $2}' | xargs)
    done

    echo "[+] SUCCESS: Anonymity Verified. Location: $S_COUNTRY"
    echo "$SP"
    cd "$BASE_PATH"
}
#1.2 Get from the user a name for the output directory.
output_folder_determine(){
    #Ask the user for the project name and create the timestamp
		echo "The Vulner will create a folder to keep all it's documantations and logs"
		read -p "Please type your prefered name for the scan operation: " NAME
		TIMESTAMP=$(date +%Y%m%d_%H%M%S)
	#Combine them into one global variable. 
	#using $(pwd) to make sure it is in current working dir
		OUTPUT_DIR="$BASE_PATH/${NAME}_${TIMESTAMP}"
	# Create the folder (-p ensures it doesn't error if the folder exists)
		mkdir -p "$OUTPUT_DIR"
		echo "[+] Output folder created at: $OUTPUT_DIR"
		echo "$SEP"
		cd "$OUTPUT_DIR"
	sleep 1
}

#1.1 Get from the user a network to scan.
targets_determine() 
{
		echo " As target(s). You can use:"
		echo " - Single IP (192.168.1.1)"
		echo " - Range (192.168.1.1-50)"
		echo " - Subnet (192.168.1.0/24)"
		read -p "To start the process, Please type your targets: " TARGET
		echo
		echo "[*] Validating targets"
		#strip trailing/leading whitespace from $TARGET
		TARGET=$(echo "$TARGET" | xargs)
		
#1.4 Make sure the input is valid.
		#test -n to make sure it is not empty.
		#regex and nmap -sL to make sure it is a valid range of addresses.

		IP_REGEX='^[0-9\./-]+$'
		until [[ -n "$TARGET" ]] && [[ "$TARGET" =~ $IP_REGEX ]] && nmap -sL "$TARGET" &>/dev/null ; do
			echo -e "[-] ERROR! $TARGET is not a valid Nmap target"
			echo -e "[-] Hint: Try 192.168.1.1 or 192 .168.1.0/24 or read more at https://nmap.org/book/man-target-specification.html"
			read -p "Please type your targets, again: " TARGET
			echo
		done
		echo $TARGET is valid
		echo "$SEP" 
		TRGT_NTWRK="$TARGET"
		nmap -sL "$TARGET" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" > "$BASE_PATH/targets.txt"
		# THE GATEKEEPER: Check if file exists AND is not empty
			if [[ ! -s "$BASE_PATH/targets.txt" ]]; then
				echo "[!] ERROR: No targets found or resolution failed. Aborting."
				exit 1
			fi
}

get_wordlists() {
    echo "[*] Configuration: Wordlists"
    
    # Password List
    read -p "Enter path to password list (default: $BASE_PATH/password.lst): " CUSTOM_PASS
    PASS_LIST="${CUSTOM_PASS:-$BASE_PATH/password.lst}"
    
    # User List
    read -p "Enter path to user list (default: $BASE_PATH/user.lst): " CUSTOM_USER
    USER_LIST="${CUSTOM_USER:-$BASE_PATH/user.lst}"

    # Verification (The "Stop & Check" step)
    if [[ ! -f "$PASS_LIST" || ! -f "$USER_LIST" ]]; then
        echo "[!] ERROR: Wordlist files not found!"
        echo "    Check: $PASS_LIST"
        echo "    Check: $USER_LIST"
        exit 1
    fi
}
# Initialize the Master Report in the Output Directory
Initialize_Master_Report(){
		REPORT_FILE="${OUTPUT_DIR}/vuln_master_report.txt"
		echo "==========================================" > "$REPORT_FILE"
		echo "VULNER REPORT - $(date)" >> "$REPORT_FILE"
		echo "Target Network: ${TRGT_NTWRK}" >> "$REPORT_FILE"
		echo "==========================================" > "$REPORT_FILE"
}
#
# Modular Logger
log_discovery_results() {
    local ip=$1
    local ports=$(cat "$OUTPUT_DIR/ports_$ip.snapshot")
    
    echo "--- Scan Results for $ip ---" >> "$OUTPUT_DIR/vuln_master_report.txt"
    if [ -n "$ports" ]; then
		printf "\n[+] Open Ports Discovered:\n%s\n" "$ports" | tee -a "$OUTPUT_DIR/vuln_master_report.txt"
    else
        echo "[-] No open ports found." | tee -a "$OUTPUT_DIR/vuln_master_report.txt"
    fi
}
#perform nmap scan by the mode selected in scan_choice
perform_discovery() {
    local ip=$1
    local mode=$2
    local output_file="$OUTPUT_DIR/discovery_$ip.gnmap"

    echo -e "\n[+] Starting Discovery Scan (Mode $mode) on $ip..."

    case $mode in
        1) 
            # Fast TCP Discovery: Top 100 ports
            nmap -Pn -sS --top-ports 100 -T4 "$ip" -oG "$output_file" > /dev/null
            ;;
        2) 
            # Balanced: TCP Top 1000 + UDP Top 1000
            nmap -Pn -sS -sU --top-ports 1000 -T3 "$ip" -oG "$output_file" > /dev/null
            ;;
        3) 
            # Forensic (Mode 3): Full TCP range + UDP Top 2000
            # Note: We split this to ensure accuracy and avoid timeouts
            echo "[*] Phase 1: Full TCP Discovery (May take a moment)..."
            nmap -Pn -sS -p- -T4 "$ip" -oG "$OUTPUT_DIR/discovery_tcp_$ip.gnmap" > /dev/null
            
            echo "[*] Phase 2: UDP Discovery..."
            nmap -Pn -sU --top-ports 2000 -T3 "$ip" -oG "$OUTPUT_DIR/discovery_udp_$ip.gnmap" > /dev/null
            
            # Combine them into one result for the next phase
            cat "$OUTPUT_DIR/discovery_tcp_$ip.gnmap" "$OUTPUT_DIR/discovery_udp_$ip.gnmap" > "$output_file"
            ;;
        *) 
            echo "[-] Invalid Discovery Mode."
            return 1
            ;;
    esac

    echo "[*] Extracting open ports from discovery results..."

    # 1. Strip the "Host: ... Ports: " header, leaving only the port strings
    # 2. Translate all commas/spaces to newlines (so every port is on its own line)
    # 3. Only keep lines containing "/open/"
    # 4. Grab the text before the first slash (the port number)
    # 5. Remove duplicates and commas
    OPEN_PORTS=$(grep "/open/" "$output_file" | \
        sed 's/.*Ports: //' | \
        tr ',' '\n' | \
        grep "/open/" | \
        cut -d'/' -f1 | \
        sort -nu | \
        paste -sd, -)

    # 2. Saving the snapshot
    if [ -n "$OPEN_PORTS" ]; then
        echo "$OPEN_PORTS" > "$OUTPUT_DIR/ports_$ip.snapshot"
        #echo "[+] Found open ports: $OPEN_PORTS"
    else
        #echo "[-] No open ports found."
        echo "" > "$OUTPUT_DIR/ports_$ip.snapshot"
    fi
}
# 3. Credential Audit (Shared Helper)
run_credential_audit() {
    local ip=$1
    local OPEN_PORTS=$(cat "$OUTPUT_DIR/ports_$ip.snapshot")

    if [ -n "$OPEN_PORTS" ]; then
        for port in ${OPEN_PORTS//,/ }; do
            case $port in
                21) service="ftp"; threads=4 ;;
                22) service="ssh"; threads=4 ;;
                23) service="telnet"; threads=1 ;; # Telnet is fragile, reduce threads to 1
                3389) service="rdp"; threads=4 ;;
                *) 
                # ANNOUNCEMENT: This is where you tell the user you're skipping it
                #echo "[!] Skipping credential audit for port $port (Service not supported)." 
                #echo "[!] Skipping credential audit for port $port (Service not supported)." >> "$OUTPUT_DIR/vuln_master_report.txt"
                continue 
                ;;
            esac

            CREDS_FILE="$OUTPUT_DIR/creds_${ip}_${port}.txt"
            echo "[!] Running weak passwords check: $service on port $port..."					
            
            TIMEOUT_LIMIT="45s"
            timeout "$TIMEOUT_LIMIT" hydra -w 5 -L "$USER_LIST" -P "$PASS_LIST" -t "$threads" "$ip" "$service" -o "$CREDS_FILE" -f -V > /dev/null 2>&1
            EXIT_STATUS=$?

            if [ $EXIT_STATUS -eq 124 ]; then
                echo -e "$SEP1\n[!] The scan on $service (port $port) timed out.\n[!] Problem: The service is not responding\n[!] Suggestion: Please try again later or investigate port $port manually." | tee -a "$OUTPUT_DIR/vuln_master_report.txt"
                continue 
            fi
            
            if grep -q "login:" "$CREDS_FILE"; then
                echo "[+] SUCCESS: Credentials found for $service on $ip!"
                echo "[+] SUCCESS: Credentials found for $service on $ip:" >> "$OUTPUT_DIR/vuln_master_report.txt"
                grep "login:" "$CREDS_FILE" | awk '{print "    User: "$5 " | Password: "$7}' | tee -a "$OUTPUT_DIR/vuln_master_report.txt"
                echo "$SEP1"  
            else
                echo "[-] No credentials found for $service on $port."
                echo "[-] No credentials found for $service on $port." >> "$OUTPUT_DIR/vuln_master_report.txt"
                echo "$SEP1"  
            fi
        done
    else
        echo "[-] No open ports found for $ip." >> "$OUTPUT_DIR/vuln_master_report.txt"
    fi
}

#scan choice: choose between full/ basic and the depth of the scan
scan_choice(){
    # 1. Ask for scan type
    read -p "Please choose b for basic scan or f for full scan: " CHOICE
    
    # 2. Ask for mode (scan depth)
    echo "Select Discovery Depth:"
    echo "1) TCP Only(top 100) | 2) TCP+UDP(Top1000) | 3) TCP+UDP(very slow) "
    read -p "Enter choice [1-3]: " SCAN_MODE

    # 3. Pass both choices
    case $CHOICE in
        B|b) basic_scan "$SCAN_MODE" ;;
        F|f) full_scan "$SCAN_MODE" ;;
        *) echo "[-] Invalid choice." ; exit 1 ;;
    esac
}

# 1.3.1 Basic: scans the network for TCP and UDP, including the service version and weak passwords
basic_scan() {
    local mode=$1  # Catch the mode from the menu
    while read -r ip; do
        perform_discovery "$ip" "$mode" # quiet scan for port finding
        log_discovery_results "$ip" #updating the master report file
        run_credential_audit "$ip" # look for week passwords
    done < "$BASE_PATH/targets.txt"
}

# 1.3.2 Full: include Nmap Scripting Engine (NSE), weak passwords, and vulnerability analysis.
full_scan() {
    CACHE_DIR="$OUTPUT_DIR/service_cache"
    mkdir -p "$CACHE_DIR"
    local mode=$1
    
    while read -r ip; do
        # 1. Discovery
        perform_discovery "$ip" "$mode"
        log_discovery_results "$ip"
        
        # 2. Get Raw Ports
        RAW_PORTS=$(cat "$OUTPUT_DIR/ports_$ip.snapshot")
        if [ -z "$RAW_PORTS" ]; then continue; fi

        # 3. STRICT FILTERING: Create a clean list of ONLY our 4 ports
        # This replaces the complicated grep logic with a simple loop
        TARGET_PORTS=""
        IFS=',' read -ra ADDR <<< "$RAW_PORTS"
        for port in "${ADDR[@]}"; do
            if [[ "$port" == "21" || "$port" == "22" || "$port" == "23" || "$port" == "3389" ]]; then
                TARGET_PORTS="${TARGET_PORTS:+$TARGET_PORTS,}$port"
            fi
        done

        # 4. ONLY proceed if we found our specific targets
        if [ -n "$TARGET_PORTS" ]; then
            echo "[!] Target ports found. Running Targeted NSE for: $TARGET_PORTS"
            nmap -Pn -sV -p "$TARGET_PORTS" --script=vuln "$ip" -oN "$OUTPUT_DIR/nse_$ip.txt" > /dev/null 2>&1

            if grep -q "VULNERABLE" "$OUTPUT_DIR/nse_$ip.txt"; then
                echo "--- NSE Vulnerabilities for $ip ---" >> "$OUTPUT_DIR/vuln_master_report.txt"
                grep -B 3 -A 2 "VULNERABLE" "$OUTPUT_DIR/nse_$ip.txt" | tee -a "$OUTPUT_DIR/vuln_master_report.txt"
            fi

            # 5. Searchsploit (Focused only on the target services)
            # We use a static list to avoid the 'file not found' errors
            for svc in ftp ssh telnet rdp; do
                # Only run if that port is actually in our TARGET_PORTS list
                # Port mapping: ftp=21, ssh=22, telnet=23, rdp=3389
                case $svc in
                    "ftp") p="21" ;; "ssh") p="22" ;; "telnet") p="23" ;; "rdp") p="3389" ;;
                esac

                if [[ "$TARGET_PORTS" == *"$p"* ]]; then
                    CACHE_FILE="$CACHE_DIR/$svc.txt"
                    if [ ! -f "$CACHE_FILE" ]; then
                        searchsploit -n "$svc" > "$CACHE_FILE" 2>/dev/null
                    fi
                    
                    if [ -s "$CACHE_FILE" ]; then
                        echo "--- Potential Exploits for $svc ---" >> "$OUTPUT_DIR/vuln_master_report.txt"
                        head -n 10 "$CACHE_FILE" >> "$OUTPUT_DIR/vuln_master_report.txt"
                    fi
                fi
            done

            # 6. Run the Audit (This function already knows to ignore other ports)
            run_credential_audit "$ip"

        else
            echo "[+] No target ports (21,22,23,3389) found on $ip. Skipping targeted scan."
        fi
        
    done < "$BASE_PATH/targets.txt"
}
finalize_scan_artifacts() {
	# deletes unnecessary files
	# Loop through all your creds files and delete those who has no creds in it
		shopt -s nullglob #change globbing behaviour to avoid "no file found" error
		for file in creds_*.txt; do
			# delete filles which DOES NOT contain the string "login:"
			if ! grep -q "login:" "$file"; then
				rm "$file"
			fi
		shopt -u nullglob # Reset globbing behavior
		done
			
	# Clean up snapshot files, hydra.restore, and cache files 
		rm -f "$OUTPUT_DIR"/*.snapshot
		rm -f "$OUTPUT_DIR"/hydra.restore
		[ -d "$OUTPUT_DIR/service_cache" ] && rm -rf "$OUTPUT_DIR/service_cache"	

	# FINAL PACKAGING
		echo "$SEP"
		echo "[*] Packaging scan reports into a ZIP archive..."

		# Ensure permissions are correct before zipping (crucial for Foremost files)
		sudo chown -R $USER:$USER "$OUTPUT_DIR"

		# Setup paths
		PARENT_DIR=$(dirname "$OUTPUT_DIR")
		FOLDER_NAME=$(basename "$OUTPUT_DIR")
		ZIP_NAME="${FOLDER_NAME}.zip"

		# Perform the zip from the parent directory
		# This avoids the "infinite loop" and "path junk" issues
		if ! (cd "$PARENT_DIR" && zip -rq "$ZIP_NAME" "$FOLDER_NAME"); then
			echo "$SP1"
			echo "[!] Error: Failed to create ZIP package."
		fi

	# FINAL SUCCESS MESSAGE
	# We use ${PARENT_DIR}/${ZIP_NAME} to show the REAL location of the file
	{
		echo "$SEP"
		echo "[+] SCAN COMPLETE."
		echo "[+] Final Report: $REPORT_FILE"
		echo "[+] Report Docs Package: ${PARENT_DIR}/${ZIP_NAME}"
		echo "$SEP"
	} | tee -a vuln_master_report.txt
}
#
MAIN()
{
welcome
check_root
tools_setup
anon_check
output_folder_determine
sleep 1
targets_determine
Initialize_Master_Report
sleep 1
get_wordlists
sleep 1
scan_choice
finalize_scan_artifacts
}
MAIN

#!/bin/bash

# --- ASCII FLOWCHART DESCRIPTION ---
# This script is self-contained and handles its own cleanup.
#
# +--------------------------------------------------+         +----------------------------------+
# |                PHASE 1: LOCAL PC                 |         |        PHASE 2: REMOTE PC        |
# |            (./prepare_and_deploy.sh)             |         |          (via sshpass)           |
# +--------------------------------------------------+         +----------------------------------+
#                         |                                                     |
#            1. Prepare Bundle (Bootstrap, Download, Install)                   |
#                         |                                                     |
#                         |---------------- 2. Transfer Bundle ---------------->|
#                                                                               |
#                                                                               |  3. Execute 'offline_setup.sh'
#                                                                               |     ├─ Unpacks Node & Chromium
#                                                                               |     └─ Runs Puppeteer Script
#                         | (Waits for remote success)                          |                |
#                         |                                                     |      +-----------------+
#                         |<--------------- 4. Remote Success/Fail Signal -----|      | BROWSER LOGS IN |
#                         |                                                     |      +-----------------+
#            5. Perform Local Cleanup (On Success)                              |
#                         |                                                     |
#                         v                                                     |
#                  +--------------+                                             |
#                  |  SCRIPT END  |                                             |
#                  +--------------+                                             |
#

# --- USAGE ---
# ./prepare_and_deploy.sh <ip> <user> '<password>' <login_id> <login_pass>

# --- Step 0: Validate Input & Settings ---
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <ip_address> <username> '<password>' <login_id> <login_pass>"
    exit 1
fi
set -e # Exit immediately if a command exits with a non-zero status.

# --- Main Configuration ---
IP_ADDRESS="$1"; USERNAME="$2"; PASSWORD="$3"; LOGIN_ID="$4"; LOGIN_PASS="$5"

# --- Script Configuration ---
NODE_VERSION="v20.15.0"
NODE_ARCHIVE="node-${NODE_VERSION}-linux-x64.tar.xz"
CHROME_BASE_URL="https://snapshot.debian.org/archive/debian-security/20250606T130227Z/pool/updates/main/c/chromium"
CHROME_VERSION="137.0.7151.68-1~deb12u1_amd64"
CHROMIUM_DEB="chromium_${CHROME_VERSION}.deb"; COMMON_DEB="chromium-common_${CHROME_VERSION}.deb"; SANDBOX_DEB="chromium-sandbox_${CHROME_VERSION}.deb"
PROJECT_DIR="PLogin"; SCRIPT_NAME="FireLogin.js"; LOG_FILE="deployment.log"

# --- Generate a unique bundle directory name using absolute paths ---
SCRIPT_EXEC_DIR=$(pwd)
PROJECT_PREFIX="PLogin_bundle"
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
RANDOM_ID=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 6)
BUNDLE_DIR="${SCRIPT_EXEC_DIR}/${PROJECT_PREFIX}_${RANDOM_ID}_${TIMESTAMP}"
LOCAL_NODE_DIR="$BUNDLE_DIR/local_node_bootstrap"
LOCAL_NPM="$LOCAL_NODE_DIR/bin/npm"

# --- Graphical Elements & Functions ---
C_WHITE="\033[1;37m"; C_GREEN="\033[0;32m"; C_RED="\033[0;31m"; C_BLUE="\033[0;34m"; C_YELLOW="\033[1;33m"; C_RESET="\033[0m"

# --- Trap for Ctrl+C ---
function cleanup_on_cancel() {
    echo -e "\n\n${C_RED}[!] Script cancelled by user.${C_RESET}"
    if [ -d "$BUNDLE_DIR" ]; then
        echo "  --> Cleaning up local bundle directory: ${BUNDLE_DIR##*/}"
        rm -rf "$BUNDLE_DIR"
    fi
    exit 1
}
trap cleanup_on_cancel SIGINT

run_stage() {
    local message=$1
    local cmd_string=$2
    printf "  %-50s" "$message"
    if eval "$cmd_string" &>> "$LOG_FILE"; then
        printf "[${C_GREEN}✓${C_RESET}]\n"
    else
        printf "[${C_RED}✗${C_RESET}]\n"
        echo -e "\n${C_RED}Error occurred. Check '${LOG_FILE}' for details.${C_RESET}"
        tail -n 15 "$LOG_FILE"
        exit 1
    fi
}

# --- Main Execution ---
rm -f "$LOG_FILE"
rm -rf "${SCRIPT_EXEC_DIR}/${PROJECT_PREFIX}_"*
clear

# --- ASCII Header ---
echo -e "${C_WHITE}+---------------------------------------------------+"
echo -e "|         Auto-Login Deployment Script              |"
echo -e "+---------------------------------------------------+"
echo -e "| ${C_BLUE}Log File: ${LOG_FILE}${C_RESET}"
echo -e "| ${C_BLUE}Bundle Dir: ${BUNDLE_DIR##*/}${C_RESET}"
echo -e "+---------------------------------------------------+\n"

# --- Prerequisite check ---
echo -e "${C_WHITE}Phase 1: Local Preparation${C_RESET}"
printf "  %-50s" "Prerequisite check (sshpass)"
if command -v sshpass >/dev/null 2>&1; then printf "[${C_GREEN}✓${C_RESET}]\n"; else printf "[${C_RED}✗${C_RESET}]\n"; echo -e "${C_RED}Failed. Please install 'sshpass' to continue.${C_RESET}"; exit 1; fi

# --- Run Stages ---
run_stage "Creating clean bundle directory" "mkdir -p '$BUNDLE_DIR/$PROJECT_DIR' && mkdir -p '$LOCAL_NODE_DIR'"
run_stage "Downloading all dependencies" "wget -qO '$BUNDLE_DIR/$PROJECT_DIR/$NODE_ARCHIVE' https://nodejs.org/dist/$NODE_VERSION/$NODE_ARCHIVE && wget -qO '$BUNDLE_DIR/$PROJECT_DIR/$CHROMIUM_DEB' $CHROME_BASE_URL/$CHROMIUM_DEB && wget -qO '$BUNDLE_DIR/$PROJECT_DIR/$COMMON_DEB' $CHROME_BASE_URL/$COMMON_DEB && wget -qO '$BUNDLE_DIR/$PROJECT_DIR/$SANDBOX_DEB' $CHROME_BASE_URL/$SANDBOX_DEB"
run_stage "Bootstrapping local Node.js" "tar -xJf '$BUNDLE_DIR/$PROJECT_DIR/$NODE_ARCHIVE' -C '$LOCAL_NODE_DIR' --strip-components=1 && [ -f '$LOCAL_NPM' ] || { echo 'FATAL: npm binary not found after extraction.' >&2; exit 1; }"
run_stage "Installing Puppeteer" "(cd '$BUNDLE_DIR/$PROJECT_DIR' && '$LOCAL_NPM' init -y && '$LOCAL_NPM' install puppeteer)"

# --- Generate Scripts ---
printf "  %-50s" "Generating offline scripts"
# Create FireLogin.js (formatted)
cat << 'EOF' > "$BUNDLE_DIR/$PROJECT_DIR/$SCRIPT_NAME"
const puppeteer = require('puppeteer');
async function FireLogin(userId, password) {
    const executablePath = process.env.CHROME_PATH;
    if (!executablePath) { console.error('FATAL: CHROME_PATH environment variable not set.'); process.exit(1); }
    console.log(`Launching browser from local path: ${executablePath}`);
    const browser = await puppeteer.launch({
        headless: false, executablePath: executablePath, ignoreHTTPSErrors: true,
        args: ['--incognito', '--ignore-certificate-errors', '--no-sandbox', '--disable-setuid-sandbox']
    });
    const page = (await browser.pages())[0];
    try {
        // --- IMPORTANT: You must change this URL to your actual target login page ---
        console.log('Navigating...');
        await page.goto('http://example.com', { waitUntil: 'networkidle0' });

        console.log('Entering credentials...');
        // --- IMPORTANT: You must change these selectors to match your login page ---
        await page.waitForSelector('#ft_un', { timeout: 10000 });
        await page.type('#ft_un', userId, { delay: 100 });
        await page.waitForSelector('#ft_pd');
        await page.type('#ft_pd', password, { delay: 100 });
        await page.waitForSelector('input[type="submit"]');
        await page.click('input[type="submit"]');
        
        console.log('Login complete. Browser will remain open.');
        console.log('--> Manually close browser and press Ctrl+C to end script. <---');
    } catch (error) {
        console.error('An error occurred during login:', error);
        await browser.close();
        process.exit(1);
    }
}
if (process.argv.length < 4) { console.error('Usage: node FireLogin.js <userId> <password>'); process.exit(1); }
FireLogin(process.argv[2], process.argv[3]);
EOF
# Create offline_setup.sh (formatted)
cat << EOF > "$BUNDLE_DIR/offline_setup.sh"
#!/bin/bash
set -e
PROJECT_DIR="$PROJECT_DIR"
CHROME_DIR="chromium-local"
echo "--- Starting Offline Setup ---"
cd \$PROJECT_DIR
if ! command -v node &>/dev/null; then
    echo "Unpacking Node.js..."
    tar -xf node-*.tar.xz
    NODE_DIR=\$(find . -maxdepth 1 -type d -name "node-*-linux-x64")
    export PATH=\$PWD/\$NODE_DIR/bin:\$PATH
fi
echo "Using Node.js: \$(node -v)"
if [ ! -d "\$CHROME_DIR" ]; then
    echo "Unpacking Chromium locally..."
    mkdir \$CHROME_DIR
    dpkg-deb -x chromium_*.deb \$CHROME_DIR >/dev/null 2>&1
    dpkg-deb -x chromium-common_*.deb \$CHROME_DIR >/dev/null 2>&1
    dpkg-deb -x chromium-sandbox_*.deb \$CHROME_DIR >/dev/null 2>&1
fi
CHROME_EXECUTABLE_PATH="\$(pwd)/\$CHROME_DIR/usr/bin/chromium"
echo "Local Chromium path is: \$CHROME_EXECUTABLE_PATH"
echo "--- Running Login Script ---"
export CHROME_PATH="\$CHROME_EXECUTABLE_PATH"
export DISPLAY=:0 && node $SCRIPT_NAME \$1 \$2
echo "--- Script has finished. ---"
EOF
chmod +x "$BUNDLE_DIR/offline_setup.sh"
printf "[${C_GREEN}✓${C_RESET}]\n"

# --- Deployment Phase ---
echo -e "\n${C_WHITE}Phase 2: Remote Deployment${C_RESET}"
run_stage "Transferring bundle to remote" "sshpass -p '$PASSWORD' scp -r -o StrictHostKeyChecking=no -o LogLevel=ERROR '$BUNDLE_DIR' '$USERNAME@$IP_ADDRESS:~/'"

# --- Remote Execution ---
echo -e "\n${C_WHITE}--- BEGIN REMOTE LOG ---${C_RESET}"
if sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "$USERNAME@$IP_ADDRESS" "cd ~/'${BUNDLE_DIR##*/}' && ./offline_setup.sh '$LOGIN_ID' '$LOGIN_PASS'"; then
    echo -e "${C_WHITE}---  END REMOTE LOG  ---${C_RESET}"
    echo -e "\n${C_GREEN}[✓] Deployment Successful!${C_RESET}"
    echo -e "${C_YELLOW}INFO: The bundle directory '${BUNDLE_DIR##*/}' was left on the remote machine for inspection.${C_RESET}"

    # --- Post-success cleanup ---
    echo -e "\n${C_WHITE}Phase 3: Local Cleanup${C_RESET}"
    run_stage "Removing local bundle directory" "rm -rf '$BUNDLE_DIR'"

else
    echo -e "${C_WHITE}---  END REMOTE LOG  ---${C_RESET}"
    echo -e "\n${C_RED}[✗] Remote execution failed.${C_RESET}"
    echo -e "${C_YELLOW}INFO: The local bundle directory '${BUNDLE_DIR##*/}' was left for inspection.${C_RESET}"
    exit 1
fi

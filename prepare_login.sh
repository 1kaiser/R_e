#!/bin/bash

# Define variables
NODE_VERSION="v20.15.0" # Replace with the latest Node.js version
PROJECT_DIR="PLogin"
SCRIPT_NAME="FireLogin.js"

# Create project directory
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Download Node.js installer
echo "Downloading Node.js..."
wget -nc https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-x64.tar.xz

# Download Google Chrome installer
echo "Downloading Google Chrome..."
wget -nc https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

# Initialize npm project
echo "Initializing npm project..."
npm init -y

# Install Puppeteer
echo "Installing Puppeteer..."
npm install puppeteer

# Create script
echo "Creating script..."
cat << 'EOF' > $SCRIPT_NAME
const puppeteer = require('puppeteer');

async function FireLogin(userId, password) {
    const browser = await puppeteer.launch({ 
        headless: true,
        executablePath: '/usr/bin/google-chrome' 
    });
    const page = await browser.newPage();
    
    //# Navigate to the login page
    await page.goto('http://www.gstatic.com/generate_204', { waitUntil: 'networkidle0' });


    //# Fill in the username and password
    await page.waitForSelector('#ft_un');
    await page.click('#ft_un');
    await page.type('#ft_un', userId);
    
    await page.waitForSelector('#ft_pd');
    await page.click('#ft_pd');
    await page.type('#ft_pd', password);
    
    await page.waitForSelector('input[type="submit"]');
    await page.click('input[type="submit"]');
    
    //# Wait for navigation after login
    await page.waitForNavigation();

    console.log('Login successful');
    await browser.close();
}

const userId = process.argv[2];
const password = process.argv[3];

FireLogin(userId, password);
EOF

# Create the setup script to be used on the offline machine
cat << 'EOF' > ../offline_setup.sh
#!/bin/bash

# Define variables
PROJECT_DIR="PLogin"
SCRIPT_NAME="FireLogin.js"

# Navigate to the project directory
cd $PROJECT_DIR

# Check if Node.js is installed
if ! command -v node &> /dev/null
then
    echo "Extracting Node.js..."
    tar -xf node-*.tar.xz
    mv node-*-linux-x64 nodejs
    # Set up environment variables for Node.js
    export PATH=$PWD/nodejs/bin:$PATH
fi

# Verify Node.js installation
echo "Node.js version:"
node -v
echo "npm version:"
npm -v

# Check if Google Chrome is installed
if ! command -v google-chrome &> /dev/null
then
    echo "Installing Google Chrome..."
    sudo dpkg -i google-chrome-stable_current_amd64.deb
    sudo apt-get install -f # Install dependencies
else
    echo "Google Chrome is already installed."
fi

# Run the script with provided userId and password
echo "Running the script..."
node $SCRIPT_NAME $1 $2
EOF

chmod +x ../offline_setup.sh

echo "Preparation complete. Transfer the *$PROJECT_DIR* folder and *offline_setup.sh* to the target machine."


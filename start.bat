@echo off
cls
echo ==========================================
echo    cdnmap Windows Setup ^& Deployment   
echo ==========================================

set ENV_FILE=.env
set SSH_DIR=%USERPROFILE%\.ssh
set SSH_KEY=%SSH_DIR%\id_rsa
set PUB_KEY=%SSH_KEY%.pub

:: 1. Check if Docker is installed
where docker >nul 2>nul
if %errorlevel% neq 0 (
    echo [-] Error: Docker or Docker Desktop is not installed on this system.
    echo Please download and install Docker Desktop from https://docker.com
    pause
    exit /b
)

:: 2. Check ^& Generate Automated SSH Keys
if not exist "%SSH_KEY%" (
    echo [*] Private SSH key not found. Generating an automated key pair...
    if not exist "%SSH_DIR%" mkdir "%SSH_DIR%"
    
    :: Generate keys using built-in Windows OpenSSH client
    ssh-keygen -t rsa -b 2048 -f "%SSH_KEY%" -N "" -q
    echo [+] SSH key pair successfully generated at %SSH_DIR%
    
    echo --------------------------------------------------------
    echo ⚠️  CRITICAL STEP REQUIRED FOR MIKROTIK AUTHENTICATION:
    echo Please copy the single-line command below and run it 
    echo inside your MikroTik WinBox Terminal to import the key:
    echo --------------------------------------------------------
    
    :: Safely print the key content inside a MikroTik-friendly routeros command
    set /p key_content=<"%PUB_KEY%"
    call echo /file print file=cdnmap_key.pub; /file set cdnmap_key.pub contents="%%key_content%%"; /user ssh-keys import file=cdnmap_key.pub user=YOUR_MIKROTIK_USER
    
    echo --------------------------------------------------------
    pause
)

:: 3. Interactive Credentials Setup
if exist %ENV_FILE% (
    echo [+] Existing configuration found in %ENV_FILE%
    goto launch
)

echo [*] Creating new local environment config...
set /p m_ip="Enter your MikroTik IP Address [e.g. 192.168.88.1]: "
set /p m_user="Enter your MikroTik SSH Username [e.g. admin]: "

if "%m_ip%"=="" goto error
if "%m_user%"=="" goto error

:: Create local .env file
(
echo MIKROTIK_IP=%m_ip%
echo MIKROTIK_USER=%m_user%
) > %ENV_FILE%

echo [+] Configuration saved locally to %ENV_FILE%

:launch
echo [+] Launching cdnmap production daemon via Docker Compose...
docker compose up -d --build

echo [+] Deployment triggered successfully!
echo [+] To view live logs in real time, run: docker compose logs -f
echo ==========================================
pause
exit /b

:error
echo [-] Error: Credentials cannot be empty!
pause
exit /b